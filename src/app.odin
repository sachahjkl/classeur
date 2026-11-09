package classeur

// The running program: one window, its panels of tabs, the workers that read the file system. The interface is built
// each frame from the App (view.odin); the workers change nothing of it themselves: their results come through ui.post.

import "core:fmt"
import "core:strings"
import "core:time/datetime"
import "core:time/timezone"
import "gt:devtools"
import "gt:font"
import "gt:host"
import lucide "gt:lucide"
import "gt:platform"
import "gt:render"
import "gt:ui"
import "fs"

// Frames owed after an event: what it set off settles (the layout, the reveal of the cursor's row).
FRAMES_AFTER_INPUT :: 3

App :: struct {
	shared:      host.Shared,
	main:        host.Host,
	icons:       font.Font_Id,      // Lucide
	mono:        font.Font_Id,
	devtools:    ^devtools.Server,  // TOOLKIT_DEVTOOLS=<port>: driven and captured over the Chrome DevTools Protocol
	theme_shown: ui.Theme_Shown,
	pool:        Pool,
	tz:          ^datetime.TZ_Region,   // the local time zone (nil: UTC)

	panels:      [dynamic]^Panel,
	focus:       int,               // the panel the keyboard works in
	next_tab_id: u64,
	closed_tabs: [dynamic]string,   // owned: what Ctrl+Shift+T opens again, the last closed last
	home:        string,            // owned
	places:      [dynamic]Place,    // the sidebar (places.odin)
	volumes:     []fs.Volume,

	default_sort: fs.Sort,
	show_hidden:  bool,
	sidebar:      bool,             // shown
	sidebar_px:   f32,              // its width, logical pixels

	palette:     Palette,           // the command palette (palette.odin)
	rename:      Rename,            // the rename in place (actions.odin)
	status:      string,            // a message for the status bar (owned), until status_until (ui clock, ms)
	status_until: f64,
	room:        f32,               // the window's width at this build, logical pixels
	text_keys:   [dynamic]ui.Key,   // the text fields built in this frame (view.odin: the keys of the list are not theirs)
	text_keys_before: [dynamic]ui.Key,   // and in the last one
	menu:        Entry_Menu,        // the entries' menu (menu.odin)
	watch:       Folder_Watch,      // the folders of the tabs, watched (watcher.odin)
	jobs:        Jobs,              // copies, moves, the trash (jobs.odin)
	confirm:     Confirm,           // delete for good? (dialogs.odin)
	conflict:    Conflict_View,     // a name taken: what to do (dialogs.odin)
	headless:    bool,              // the tests: no window of the system, no program started (open_system)
	opened:      [dynamic]string,   // headless: what open_system would have opened (owned)
}

WINDOW_SIZE :: [2]int{1180, 720}

Open_Options :: struct {
	folders:  []string,   // a tab for each (none: the home folder)
	headless: bool,       // no window of the system: offscreen, the software renderer, the fonts compiled in (the tests)
	size:     [2]int,     // 0: WINDOW_SIZE
	home:     string,     // "": the person's (the tests give theirs)
}

app_run :: proc(folders: []string) -> int {
	app := app_open({folders = folders})
	if app == nil { return 1 }
	platform.show_window(app.main.win)
	for !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		app_frame(app)
	}
	app_close(app)
	return 0
}

// Opens the window and its first tabs. nil: no window (said why).
app_open :: proc(o: Open_Options) -> ^App {
	app := new(App)
	app.headless = o.headless
	app.home = o.home != "" ? fs.clean(o.home) : fs.home()
	app.sidebar = true
	app.sidebar_px = 210
	app.tz, _ = timezone.region_load("local")

	platform.set_app_id(APP_NAME)
	size := o.size != {} ? o.size : WINDOW_SIZE
	if !host.host_open(&app.main, &app.shared, {title = "Classeur", size = size, integrated_title = !o.headless, headless = o.headless}, view_build, app) {
		fmt.eprintln("classeur: no window")
		free(app)
		return nil
	}
	h := &app.main
	win := h.win
	app.icons, _ = font.load_embedded(&app.shared.fonts, lucide.DATA)
	app.mono, _ = font.load_embedded(&app.shared.fonts, font.FALLBACK_MONO_DATA)
	h.state.icon_font, _ = font.load_embedded(&app.shared.fonts, ui.ICON_FONT_DATA)
	h.after_input = FRAMES_AFTER_INPUT
	ui.set_rounding(&h.state, ROUNDING)
	ui.set_density(&h.state, DENSITY)
	h.partial_redraw = true
	h.params = app_params
	app.devtools = devtools.start_from_env(win, APP_NAME)
	h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }

	pool_start(&app.pool)
	jobs_start(app)
	watcher_start(app)
	places_load(app)
	first := new(Panel)
	append(&app.panels, first)
	if len(o.folders) == 0 {
		tab_open(app, first, app.home)
	} else {
		for f in o.folders { tab_open(app, first, f) }
		first.active = 0
	}
	return app
}

app_frame :: proc(app: ^App) {
	host.host_frame(&app.main)
}

app_close :: proc(app: ^App) {
	watcher_stop(app)
	jobs_stop(app)
	pool_stop(&app.pool, proc(data: rawptr) {})   // (a read left waiting: its memory goes with the process)
	devtools.stop(app.devtools)
	host.host_close(&app.main)
	app_free(app)
	free(app)
}

@(private = "file")
app_free :: proc(app: ^App) {
	for p in app.panels { panel_destroy(p) }
	delete(app.panels)
	for p in app.closed_tabs { delete(p) }
	delete(app.closed_tabs)
	places_free(app)
	delete(app.places)
	palette_free(&app.palette)
	rename_free(&app.rename)
	confirm_free(&app.confirm)
	delete(app.home)
	delete(app.status)
	delete(app.text_keys)
	delete(app.text_keys_before)
	for p in app.opened { delete(p) }
	delete(app.opened)
	if app.tz != nil { timezone.region_destroy(app.tz) }
}

// What each build is given: the palette and the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	choice := ui.Theme_Choice{name = "Graphite", mode = .System, finish = .Machined, glow = 0.6}
	if ui.theme_show(&app.shared.theme, themes(), choice, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
	}
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(26)}, font = app.shared.font, font_size = 13, text_pad = 5, cursor = .Arrow}
}

// More frames: something changed outside of an input (a worker's result).
app_frames :: proc(app: ^App) {
	app.main.settle = max(app.main.settle, FRAMES_AFTER_INPUT)
}

// Shows a message in the status bar for a few seconds.
say :: proc(app: ^App, format: string, args: ..any) {
	delete(app.status)
	app.status = fmt.aprintf(format, ..args)
	app.status_until = ui.now_ms() + STATUS_SHOWN_MS
	ui.wake_within(&app.main.state, STATUS_SHOWN_MS + 1)
}

STATUS_SHOWN_MS :: 4000

// classeur's own theme, first of the list: graphite. Neutral greys far enough apart that every surface reads (the
// bars, the list, the wells, the lines), a clear blue for the selection; a light version of the same steps.
THEME_CLASSEUR :: ui.Theme_Def{"Graphite",
	{{0x0f1012ff, 0x18191cff, 0x222429ff, 0x1c1d21ff, 0x2e3137ff, 0x3b3f47ff}, {0x5d626cff, 0x959ba6ff, 0xdfe2e7ff, 0xffffffff},
		{0x4f9de8ff, 0x60a5faff, 0xa78bfaff, 0x5dc48aff, 0xe8b84eff, 0xe9605fff, 0x4cc2ffff, 0xe476a8ff}},
	{{0xffffffff, 0xf7f8f9ff, 0xe4e6eaff, 0xeef0f2ff, 0xfbfbfcff, 0xbfc4cbff}, {0xa1a7b0ff, 0x5c636dff, 0x1a1d21ff, 0x000000ff},
		{0x1f6fd1ff, 0x2563ebff, 0x7c3aedff, 0x2f8f46ff, 0xb7820cff, 0xd23c3cff, 0x0e7490ff, 0xc2477aff}},
	.Both, nil, false, 0}

// How square the corners are (1: the toolkit's) and how dense the rows (1: comfortable).
ROUNDING :: 0.3
DENSITY  :: 0.82

// The themes the window can show: classeur's, then the toolkit's (gui_toolkit docs/themes.md).
themes :: proc() -> []ui.Theme_Def {
	@(static) list: [len(ui.THEMES) + 1]ui.Theme_Def
	@(static) n: int
	if n == 0 {
		// (the toolkit's own Graphite gives way to classeur's: one name, one theme)
		list[0] = THEME_CLASSEUR
		n = 1
		for t in ui.THEMES {
			if t.name == THEME_CLASSEUR.name { continue }
			list[n] = t
			n += 1
		}
	}
	return list[:n]
}

// Text to show as it is: a "##" in it would end the shown part of a box's id string (ui's key rules), so a zero-width
// space goes between the two signs.
shown_text :: proc(text: string, allocator := context.temp_allocator) -> string {
	if !strings.contains(text, "##") { return text }
	out, _ := strings.replace_all(text, "##", "#​#", allocator)
	return out
}
