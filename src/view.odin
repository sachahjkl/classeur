package classeur

// The window, File Pilot's: one row at the top (over the sidebar its head, over each panel its tabs, then the window's
// buttons), the sidebar, the panels side by side (view_panel.odin). No status bar: each panel has its footer. The keys
// of the commands are read before anything is built (commands.odin).

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"
import "gt:draw"
import "gt:host"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

// Heights in ems.
TOP_EM :: 2.6
// The sidebar's least and most width, logical pixels; what the panels keep at least.
SIDEBAR_MIN_PX :: 160
SIDEBAR_MAX_PX :: 420
PANELS_MIN_PX  :: 320
// A tab's width, at most and at least, in ems.
TAB_EM     :: 14
TAB_MIN_EM :: 5

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	app.room = size.x / max(ui.scale(), 0.01)
	app.frame += 1
	// a text field had the keyboard at the end of the last build: only the commands that work while typing run
	clear(&app.text_keys_before)
	append(&app.text_keys_before, ..app.text_keys[:])
	clear(&app.text_keys)
	typing := slice.contains(app.text_keys_before[:], ui.focus_key())
	if !app.palette.open && !app.confirm.open && !app.conflict.open && !app.options.open {
		commands_keys(app, typing)
		if !typing { list_keys(app) }
	}

	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y, bg = draw.hex(surfaces(app).list)})
	page := ui.build_box({.Draw_Background}, "###page")
	if ui.parent(page) {
		build_top(app, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() { build_body(app, em) }
	}
	entry_menu_build(app, em)
	panel_menus_build(app, em)
	palette_build(app)
	options_build(app)
	dialogs_build(app, em)
	jobs_tidy(app)
	watcher_update(app)
	measure_update(app)
	thumbs_tidy(app)
}

// A text field built this frame: while it has the keyboard, the keys of the list are its own.
note_text_field :: proc(app: ^App, key: ui.Key) { append(&app.text_keys, key) }

// An icon of Lucide, `width` wide.
glyph :: proc(app: ^App, g: string, width: f32, fg: Maybe(ui.Color) = nil) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = app.icons, text_align = .Center, fg = fg})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###g%d", g, ui.parent_box().child_count))
}

// A small flat button with a Lucide icon; its tooltip says what it does. `on`: lit in the accent (a toggle that is on).
icon_action :: proc(app: ^App, id, g, tip: string, em: f32, enabled := true, on := false) -> bool {
	side := em * 2.0
	ui.next({width = ui.px(side), height = ui.px(side), font = app.icons, radius = em * 0.15, text_pad = 0, fg = on ? ui.color("accent") : nil})
	sig: ui.Signal
	if ui.disabled(!enabled) {
		if ui.tags("ghost_button") { sig = ui.button(fmt.tprintf("%s###%s", g, id)) }
	}
	if ui.hovered_for(sig, 0.4) {
		if ui.tooltip() {
			ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 1.8))})
			ui.label(fmt.tprintf("%s###tip", tip))
		}
	}
	return enabled && sig.clicked
}

// A thin vertical line between groups of buttons.
vrule :: proc(em: f32, height: f32 = 1.3) {
	ui.spacer(ui.px(em * 0.35))
	ui.next({width = ui.px(max(1, ui.scale())), height = ui.px(em * height), bg = ui.color("border")})
	ui.build_box({.Draw_Background}, fmt.tprintf("###rule%d", ui.parent_box().child_count))
	ui.spacer(ui.px(em * 0.35))
}

// The tooltip of a command: its title and its first key.
command_tip :: proc(id: string) -> string {
	c := command_find(id)
	if c == nil { return id }
	if c.keys[0].key == .None { return c.title }
	return fmt.tprintf("%s (%s)", c.title, shortcut_text(c.keys[0]))
}

////////////////////////////////
// The row at the top

@(private = "file")
build_top :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOP_EM)), bg = draw.hex(surfaces(app).top)})
	ui.push_tags("bar")
	defer ui.pop_tags()
	if ui.title_bar("###titlebar", {.Draw_Background}) {
		// each part as wide as what is under it (the boxes of the last frame: the first has no width yet)
		have := len(app.panel_rects) == len(app.panels) && app.panel_rects[0].max.x > 0
		head := have ? app.panel_rects[0].min.x : app.sidebar ? app.sidebar_px * ui.scale() : em * 5
		ui.next({width = ui.px(head), height = ui.pct(1)})
		if ui.row(.Center, {}, "###head") {
			ui.spacer(ui.px(em * 0.6))
			drawn_icon(.Folder, em * 1.8, ui.color("accent"))
			ui.spacer(ui.fill())
			if icon_action(app, "sidebar", app.sidebar ? lucide.PANEL_LEFT : lucide.PANEL_RIGHT, command_tip("sidebar"), em) { act_toggle_sidebar(app) }
			ui.spacer(ui.px(em * 0.3))
		}
		for p, i in app.panels {
			last := i == len(app.panels) - 1
			w: ui.Size = ui.fill()
			if have && !last { w = ui.px(app.panel_rects[i].max.x - app.panel_rects[i].min.x) }
			if have && i > 0 { ui.spacer(ui.px(app.panel_rects[i].min.x - app.panel_rects[i - 1].max.x)) }
			tab_region(app, p, i, w, have ? app.panel_rects[i].max.x - app.panel_rects[i].min.x : 0, em)
		}
		ui.window_buttons()
	}
}

// A panel's tabs, at the top of the window over it: as wide as TAB_EM, narrower when they do not fit; the shown one
// in the list's colour, with a line of the accent along its top when its panel has the keyboard.
@(private = "file")
tab_region :: proc(app: ^App, p: ^Panel, index: int, width: ui.Size, room: f32, em: f32) {
	focused := index == app.focus
	ui.next({width = width, height = ui.pct(1)})
	if ui.row(.End, {.Clip}, fmt.tprintf("###tabs%d", index)) {
		n := len(p.tabs)
		tab_w := em * TAB_EM
		if room > 0 && n > 0 { tab_w = clamp((room - em * 4.5) / f32(n), em * TAB_MIN_EM, em * TAB_EM) }
		close := -1
		for t, i in p.tabs {
			on := i == p.active
			ui.spacer(ui.px(em * 0.15))
			ui.next({width = ui.px(tab_w), height = ui.px(ui.dense(em * (TOP_EM - 0.45))), axis = .Y, radius = em * 0.45})
			flags := ui.Box_Flags{.Clickable, .Hot_Within, .Middle_Click}
			if !on { flags += {.Draw_Hot_Effects} }
			tab := ui.build_box(flags, fmt.tprintf("###tab%d", t.id))
			tab.square_corners = {.Bottom_Left, .Bottom_Right}
			if on {
				r := em * 0.45 * ui.rounding(&app.main.state)
				raise(tab, {base = draw.hex(surfaces(app).list), edge = draw.hex(surfaces(app).edge), radii = {r, 0, r, 0}})
			}
			sig := ui.signal(tab)
			if ui.parent(tab) {
				// (with several panels, the line of the accent says which one has the keyboard)
				line := on && focused && len(app.panels) > 1 ? ui.color("accent") : ui.Color{}
				ui.next({width = ui.fill(), height = ui.px(max(2, ui.scale() * 2)), bg = line, radius = 0})
				ui.build_box({.Draw_Background}, "###top")
				ui.next({width = ui.fill(), height = ui.fill()})
				if ui.row(.Center) {
					ui.spacer(ui.px(em * 0.7))
					drawn_icon(.Folder, em * 1.6)
					ui.spacer(ui.px(em * 0.4))
					ui.next({width = ui.fill(), height = ui.pct(1)})
					if !on { ui.push_tags("weak") }
					ui.label(fmt.tprintf("%s###title", shown_text(tab_title(app, t))))
					if !on { ui.pop_tags() }
					if on || ui.hot_within(tab.key) {
						ui.next({width = ui.px(em * 1.6), height = ui.px(em * 1.6), font = app.icons, radius = em * 0.15, font_size = em * 0.85, text_pad = 0})
						if ui.tags("ghost_button") {
							if ui.button(fmt.tprintf("%s###close", lucide.X)).clicked { close = i }
						}
					} else {
						ui.spacer(ui.px(em * 1.6))
					}
					ui.spacer(ui.px(em * 0.4))
				}
			}
			if sig.pressed { p.active = i; app.focus = index }
			if sig.middle_clicked { close = i }
		}
		ui.spacer(ui.px(em * 0.3))
		if icon_action(app, fmt.tprintf("newtab%d", index), lucide.PLUS, command_tip("tab_new"), em) {
			app.focus = index
			act_tab_new(app)
		}
		if close >= 0 { tab_close(app, p, close) }
	}
}

////////////////////////////////
// The body

@(private = "file")
build_body :: proc(app: ^App, em: f32) {
	scale := ui.scale()
	if app.sidebar {
		app.sidebar_px = clamp(app.sidebar_px, SIDEBAR_MIN_PX, max(min(SIDEBAR_MAX_PX, app.room - PANELS_MIN_PX), SIDEBAR_MIN_PX))
		ui.next({width = ui.px(app.sidebar_px * scale), height = ui.fill()})
		sidebar_build(app, em)
		ui.splitter("###side_split", .X, &app.sidebar_px, SIDEBAR_MIN_PX, SIDEBAR_MAX_PX, {default_size = 240, total = app.room, min_other = PANELS_MIN_PX, thickness = 3})
	}
	resize(&app.panel_rects, len(app.panels))
	for p, i in app.panels {
		if i > 0 {
			ui.next({width = ui.px(max(1, scale)), height = ui.fill(), bg = ui.color("border")})
			ui.build_box({.Draw_Background}, fmt.tprintf("###panel_sep%d", i))
		}
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		app.panel_rects[i] = panel_build(app, p, i, em)
	}
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
	grid := tab_mode(t) >= .Columns
	row := tab_row_items(t)
	page := max(t.vl.page_rows - 1, 1) * row
	Move :: struct { key: Shortcut, to: int, extend: bool }
	moves := make([dynamic]Move, context.temp_allocator)
	append(&moves, Move{{.Down, {.Shift}}, f.cursor + row, true}, Move{{.Up, {.Shift}}, f.cursor - row, true},
		Move{{.Page_Down, {.Shift}}, f.cursor + page, true}, Move{{.Page_Up, {.Shift}}, f.cursor - page, true},
		Move{{.Home, {.Shift}}, 0, true}, Move{{.End, {.Shift}}, n - 1, true})
	if grid {
		// (the grid's moves are its own: the list under it moves by rows of cards)
		append(&moves, Move{{.Right, {}}, f.cursor + 1, false}, Move{{.Left, {}}, f.cursor - 1, false},
			Move{{.Down, {}}, f.cursor + row, false}, Move{{.Up, {}}, f.cursor - row, false},
			Move{{.Page_Down, {}}, f.cursor + page, false}, Move{{.Page_Up, {}}, f.cursor - page, false},
			Move{{.Home, {}}, 0, false}, Move{{.End, {}}, n - 1, false},
			Move{{.Right, {.Shift}}, f.cursor + 1, true}, Move{{.Left, {.Shift}}, f.cursor - 1, true})
	}
	for m in moves {
		if ui.key_press(m.key.key, m.key.mods) {
			folder_pick(f, clamp(m.to, 0, n - 1), extend = m.extend)
			ui.list_select(&t.vl, grid ? f.cursor / row : f.cursor)
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

// The job that runs: what it does, how far, a cancel (in the footer of the panel that has the keyboard).
job_status :: proc(app: ^App, em: f32) {
	for job in app.jobs.list {
		st := sync.atomic_load(&job.state)
		if st != .Counting && st != .Running && st != .Asking { continue }
		total, done := sync.atomic_load(&job.bytes_total), sync.atomic_load(&job.bytes_done)
		files, files_done := sync.atomic_load(&job.files_total), sync.atomic_load(&job.files_done)
		t := total > 0 ? f32(f64(done) / f64(total)) : files > 0 ? f32(files_done) / f32(files) : 0
		text := st == .Counting ? fmt.tprintf("%s: counting…", JOB_VERB[job.kind]) : fmt.tprintf("%s %d of %d · %s", JOB_VERB[job.kind], min(files_done + 1, files), files, shown_text(job_current(job)))
		ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###job%d", text, job.id))
		ui.next({width = ui.px(em * 7), height = ui.px(em * 0.45)})
		ui.progress(fmt.tprintf("###jobbar%d", job.id), clamp(t, 0, 1), st == .Counting)
		ui.spacer(ui.px(em * 0.2))
		if icon_action(app, fmt.tprintf("jobcancel%d", job.id), lucide.X, "Cancel", em) { job_cancel(job) }
		vrule(em)
		return
	}
}
