package classeur

// The window: the title bar (the program's own), the sidebar of places, the panels side by side (view_panel.odin), the
// status bar. The keys of the commands are read before anything is built (commands.odin).

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"
import "gt:host"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

// Heights in ems.
TITLE_EM  :: 2.5
STATUS_EM :: 1.8
// The sidebar's least and most width, logical pixels; what the panels keep at least.
SIDEBAR_MIN_PX :: 140
SIDEBAR_MAX_PX :: 420
PANELS_MIN_PX  :: 320

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	app.room = size.x / max(ui.scale(), 0.01)
	// a text field had the keyboard at the end of the last build: only the commands that work while typing run
	clear(&app.text_keys_before)
	append(&app.text_keys_before, ..app.text_keys[:])
	clear(&app.text_keys)
	typing := slice.contains(app.text_keys_before[:], ui.focus_key())
	if !app.palette.open && !app.confirm.open && !app.conflict.open {
		commands_keys(app, typing)
		if !typing { list_keys(app) }
	}

	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
	page := ui.build_box({.Draw_Background}, "###page")
	if ui.parent(page) {
		build_title(app, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() { build_body(app, em) }
		build_status(app, em)
	}
	entry_menu_build(app, em)
	palette_build(app)
	dialogs_build(app, em)
	jobs_tidy(app)
	watcher_update(app)
}

// A text field built this frame: while it has the keyboard, the keys of the list are its own.
note_text_field :: proc(app: ^App, key: ui.Key) { append(&app.text_keys, key) }

// An icon of Lucide, `width` wide.
glyph :: proc(app: ^App, g: string, width: f32, fg: Maybe(ui.Color) = nil) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = app.icons, text_align = .Center, fg = fg})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###g%d", g, ui.parent_box().child_count))
}

// A small button with a Lucide icon; its tooltip says what it does.
icon_action :: proc(app: ^App, id, g, tip: string, em: f32, enabled := true, raised := false) -> bool {
	side := raised ? em * 1.75 : em * 1.9
	ui.next({width = ui.px(side), height = ui.px(side), font = app.icons, radius = em * 0.3, text_pad = 0})
	sig: ui.Signal
	if ui.disabled(!enabled) {
		if raised {
			sig = ui.button(fmt.tprintf("%s###%s", g, id))
		} else if ui.tags("ghost_button") {
			sig = ui.button(fmt.tprintf("%s###%s", g, id))
		}
	}
	if ui.hovered_for(sig, 0.4) {
		if ui.tooltip() {
			ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 1.8))})
			ui.label(fmt.tprintf("%s###tip", tip))
		}
	}
	return enabled && sig.clicked
}

// The tooltip of a command: its title and its first key.
command_tip :: proc(id: string) -> string {
	c := command_find(id)
	if c == nil { return id }
	if c.keys[0].key == .None { return c.title }
	return fmt.tprintf("%s (%s)", c.title, shortcut_text(c.keys[0]))
}

@(private = "file")
build_title :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TITLE_EM))})
	ui.push_tags("bar")
	defer ui.pop_tags()
	if ui.title_bar("###titlebar", {.Draw_Background, .Draw_Side_Bottom}) {
		ui.spacer(ui.px(em * 0.5))
		glyph(app, lucide.FOLDER_OPEN, em * 1.8, ui.color("accent"))
		ui.next({width = ui.text_size(em * 0.3), height = ui.pct(1)})
		ui.label("Classeur###apptitle")
		if t := current_tab(app); t != nil {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.pct(1)})
				ui.label(fmt.tprintf("%s###titlepath", shown_text(home_path(app, t.path))))
			}
		} else {
			ui.spacer(ui.fill())
		}
		if icon_action(app, "sidebar", lucide.PANEL_LEFT, command_tip("sidebar"), em) { act_toggle_sidebar(app) }
		if icon_action(app, "split", lucide.COLUMNS_2, command_tip("panel_split"), em) { act_panel_split(app) }
		if icon_action(app, "hidden", app.show_hidden ? lucide.EYE : lucide.EYE_OFF, command_tip("hidden"), em) { act_toggle_hidden(app) }
		if icon_action(app, "palette", lucide.COMMAND, command_tip("palette"), em) { palette_open(app) }
		ui.spacer(ui.px(em * 0.4))
		ui.window_buttons()
	}
}

@(private = "file")
build_body :: proc(app: ^App, em: f32) {
	scale := ui.scale()
	if app.sidebar {
		app.sidebar_px = clamp(app.sidebar_px, SIDEBAR_MIN_PX, max(min(SIDEBAR_MAX_PX, app.room - PANELS_MIN_PX), SIDEBAR_MIN_PX))
		ui.next({width = ui.px(app.sidebar_px * scale), height = ui.fill()})
		build_sidebar(app, em)
		ui.splitter("###side_split", .X, &app.sidebar_px, SIDEBAR_MIN_PX, SIDEBAR_MAX_PX, {default_size = 210, total = app.room, min_other = PANELS_MIN_PX})
	}
	for p, i in app.panels {
		if i > 0 {
			// (two lines with the page between them: the panels read as two)
			ui.next({width = ui.px(max(1, scale)), height = ui.fill()})
			ui.next_merge({bg = ui.color("border")})
			ui.build_box({.Draw_Background}, fmt.tprintf("###panel_sep%d", i))
			ui.spacer(ui.px(max(3, 3 * scale)))
			ui.next({width = ui.px(max(1, scale)), height = ui.fill()})
			ui.next_merge({bg = ui.color("border")})
			ui.build_box({.Draw_Background}, fmt.tprintf("###panel_sep%db", i))
		}
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		panel_build(app, p, i, em)
	}
}

////////////////////////////////
// The sidebar

@(private = "file")
build_sidebar :: proc(app: ^App, em: f32) {
	t := current_tab(app)
	here := t != nil ? t.path : ""
	ui.push_tags("bar")
	box := ui.build_box({.Clip, .Draw_Background}, "###sidebar")
	ui.pop_tags()
	if ui.parent(box) {
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.scroll_y("###side_scroll") {
			ui.spacer(ui.px(em * 0.4))
			side_heading("Places", em)
			for p, i in app.places {
				if side_row(app, fmt.tprintf("###place%d", i), p.icon, p.name, p.path == here, em) && t != nil { tab_go(app, t, p.path) }
			}
			ui.spacer(ui.px(em * 0.6))
			side_heading("Volumes", em)
			for v, i in app.volumes {
				icon := v.removable ? lucide.USB : lucide.HARD_DRIVE
				if side_row(app, fmt.tprintf("###vol%d", i), icon, v.label, v.path == here, em) && t != nil { tab_go(app, t, v.path) }
			}
			ui.spacer(ui.px(em * 0.6))
		}
	}
}

@(private = "file")
side_heading :: proc(text: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7))})
	if ui.row(.Center) {
		ui.spacer(ui.px(em * 0.8))
		if ui.tags("weak") {
			ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1), font_size = em * 0.78})
			ui.label(fmt.tprintf("%s###h", strings.to_upper(text, context.temp_allocator)))
		}
		ui.next({width = ui.fill(), height = ui.px(1)})
		ui.next_merge({bg = ui.color("border")})
		ui.build_box({.Draw_Background}, "###rule")
		ui.spacer(ui.px(em * 0.6))
	}
}

@(private = "file")
side_row :: proc(app: ^App, id, icon, name: string, here: bool, em: f32) -> bool {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.75)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within}
	if here { flags += {.Draw_Background, .Draw_Side_Left} }
	sig: ui.Signal
	if here { ui.push_tags("selected") }
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 0.6))
		glyph(app, icon, em * 1.7, here ? ui.color("accent") : nil)
		ui.spacer(ui.px(em * 0.2))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", shown_text(name)))
	}
	if here { ui.pop_tags() }
	return sig.clicked
}

////////////////////////////////
// The status bar

@(private = "file")
build_status :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * STATUS_EM))})
	ui.push_tags("bar")
	defer ui.pop_tags()
	if ui.row(.Center, {.Draw_Background, .Draw_Side_Top}, "###statusbar") {
		ui.spacer(ui.px(em * 0.7))
		if ui.style({font_size = em * 0.86}) {
			job_status(app, em)
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.pct(1)})
				msg := app.status
				if msg == "" || ui.now_ms() > app.status_until { msg = status_text(app) }
				ui.label(fmt.tprintf("%s###status", shown_text(msg)))
				for id in ([]string{"palette", "goto", "filter"}) {
					c := command_find(id)
					ui.kbd(shortcut_text(c.keys[0]))
					ui.next({width = ui.text_size(em * 0.3), height = ui.pct(1)})
					ui.label(fmt.tprintf("%s###h%s", c.title, id))
					ui.spacer(ui.px(em * 0.4))
				}
			}
		}
	}
}

// What the status bar says of the current tab: its items, its selection, the free space.
@(private = "file")
status_text :: proc(app: ^App) -> string {
	t := current_tab(app)
	if t == nil { return "" }
	f := &t.folder
	if !f.loaded { return "Reading…" }
	if f.listing.error != .None { return fs.ERROR_TEXT[f.listing.error] }
	items := len(f.shown) == len(f.listing.entries) ? fmt.tprintf("%d items", len(f.shown)) : fmt.tprintf("%d of %d items", len(f.shown), len(f.listing.entries))
	if f.count > 0 {
		bytes, _ := folder_selection_size(f)
		items = fmt.tprintf("%s · %d selected, %s", items, f.count, size_text(bytes))
	}
	if t.has_space { items = fmt.tprintf("%s · %s free of %s", items, size_text(t.space.free), size_text(t.space.total)) }
	return fmt.tprintf("%s · read in %.0f ms", items, t.load_ms)
}

////////////////////////////////
// The keys of the list that change the selection (Shift ranges, Ctrl+Space); the moves are the list's own.

@(private = "file")
list_keys :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	f := &t.folder
	n := len(f.shown)
	if n == 0 { return }
	page := max(t.vl.page_rows - 1, 1)
	moves := [?]struct { key: Shortcut, to: int }{
		{{.Down, {.Shift}}, f.cursor + 1},
		{{.Up, {.Shift}}, f.cursor - 1},
		{{.Page_Down, {.Shift}}, f.cursor + page},
		{{.Page_Up, {.Shift}}, f.cursor - page},
		{{.Home, {.Shift}}, 0},
		{{.End, {.Shift}}, n - 1},
	}
	for m in moves {
		if ui.key_press(m.key.key, m.key.mods) {
			folder_pick(f, clamp(m.to, 0, n - 1), extend = true)
			ui.list_select(&t.vl, f.cursor)
		}
	}
	if ui.key_press(.Space, {.Ctrl}) { folder_pick(f, f.cursor, toggle = true) }
	if ui.key_press(.Escape) && f.count > 1 { folder_pick(f, f.cursor) }
	if ui.key_press(.Menu) || ui.key_press(.F10, {.Shift}) {
		if f.cursor >= 0 { entry_menu_open(app, t, {t.cursor_rect.min.x + 24, t.cursor_rect.max.y}, from_keyboard = true) }
	}
}

// The path with "~" for the home folder.
home_path :: proc(app: ^App, path: string) -> string {
	if path == app.home { return "~" }
	if strings.has_prefix(path, app.home) && fs.is_separator(path[len(app.home)]) { return fmt.tprintf("~%s", path[len(app.home):]) }
	return path
}

// The job that runs, in the status bar: what it does, how far, a cancel.
@(private = "file")
job_status :: proc(app: ^App, em: f32) {
	for job in app.jobs.list {
		st := sync.atomic_load(&job.state)
		if st != .Counting && st != .Running && st != .Asking { continue }
		glyph(app, lucide.LOADER, em * 1.5, ui.color("accent"))
		total, done := sync.atomic_load(&job.bytes_total), sync.atomic_load(&job.bytes_done)
		files, files_done := sync.atomic_load(&job.files_total), sync.atomic_load(&job.files_done)
		t := total > 0 ? f32(f64(done) / f64(total)) : files > 0 ? f32(files_done) / f32(files) : 0
		text := st == .Counting ? fmt.tprintf("%s: counting…", JOB_VERB[job.kind]) : fmt.tprintf("%s %d of %d · %s", JOB_VERB[job.kind], min(files_done + 1, files), files, shown_text(job_current(job)))
		ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###job%d", text, job.id))
		ui.next({width = ui.px(em * 8), height = ui.px(em * 0.5)})
		ui.progress(fmt.tprintf("###jobbar%d", job.id), clamp(t, 0, 1), st == .Counting)
		ui.spacer(ui.px(em * 0.3))
		if icon_action(app, fmt.tprintf("jobcancel%d", job.id), lucide.X, "Cancel", em) { job_cancel(job) }
		ui.spacer(ui.px(em * 0.6))
		return
	}
}
