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
import "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import crash_bar "gt:crash_bar"
import "gt:ui"
import "fs"

// Heights in ems.
TOP_EM :: 2.6
// A tab's width, at most and at least, in ems.
TAB_EM     :: 14
TAB_MIN_EM :: 5
// What a row of tabs holds after them: the new tab's button, the gap before it and the room around it, in ems.
TAB_ROW_END_EM :: 2 + ui.TOOL_GAP + 0.5
// Room reserved for ui.tab_strip_start() and the chosen tab's trailing fillet before computing fixed tab widths, in ems.
TAB_STRIP_LEAD_EM :: 0.8
// The button of the list of the tabs, before the new tab's (a row with more tabs than it holds), in ems.
TAB_LIST_EM :: 2

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	app.room = size.x / max(ui.scale(), 0.01)
	app.window_px_last, app.window_px = app.window_px, size
	app.frame += 1
	updates_follow(app)
	// (the person's themes file read again when it changed: theme_show, in the next frame's params, shows the new one)
	if prefs_page.themes_file_poll(&app.themes_file, &h.state) { app_frames(app) }
	dnd_frame(app)
	app.tab_rects, app.tab_rects_last = app.tab_rects_last, app.tab_rects
	clear(&app.tab_rects)
	tab_drag_apply(app)
	tab_drag_land(app)
	measures_resort(app)
	tab_drag_poll(app)
	// (a band whose tab went, or whose press ended out of its list: over)
	if app.band.active && (find_tab(app, app.band.tab) == nil || ui.active_key() == 0) { app.band.active = false }
	// (a gesture Escape ended: its press is over once nothing is held)
	if ui.active_key() == 0 { app.gesture_cancelled = false }
	// a text field had the keyboard at the end of the last build: only the commands that work while typing run
	clear(&app.text_keys_before)
	append(&app.text_keys_before, ..app.text_keys[:])
	clear(&app.text_keys)
	typing := slice.contains(app.text_keys_before[:], ui.focus_key())
	// (a view shown as a dialog, or About, holds the keys; one that floats or is docked keeps those it is given)
	app.no_dialog = !ui.views_hold_keys(&app.views) && !app.about_open
	keys_follow(app)
	// the palette's choice, before anything is built: a value its run mode writes shows on the settings' view in the
	// same frame (the views are built first, in views_frame)
	palette_choose(app)

	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y, bg = draw.hex(surfaces(app).list)})
	page := ui.build_box({.Draw_Background}, "###page")
	if ui.parent(page) {
		// (the top row the whole width, over the sidebar too: the views' frame is the room under it)
		build_top(app, em)
		crash_bar.bar(&app.crash_bar, {name = APP_TITLE, version = APP_VERSION, repository = "sachahjkl/classeur"})
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.views_frame(&app.views) {
			app.content_rect = ui.parent_box().rect
			// the program's keys, after the views' (built first in the frame: a view with the focus reads its keys
			// first; the toolkit's F6 comes last, only when nothing took it). The window's commands first, over a
			// dialog too (the settings are one); the toolkit's recorder claims every chord while it records
			// (the palette's keys first: they are the toolkit's)
			palette_keys_read(app)
			window_keys(app)
			if app.no_dialog {
				gesture_escape(app)
				// (the sidebar, the inspector or another view has the keyboard: its moves are its own, the commands
				// that act on the list's rows (Enter, Delete, Space...) wait; those that work while typing still run)
				elsewhere := app.keys_at != .List || focus_in_view(app)
				commands_keys(app, typing || elsewhere)
				if !typing && !elsewhere { list_keys(app) }
			}
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.row() { build_body(app, em) }
		}
	}
	tab_drag_overlay(app, em)
	file_drag_frame(app, em)
	entry_menu_build(app, em)
	side_menu_build(app, em)
	panel_menus_build(app, em)
	layouts_build(app, em)
	// (the installed copy starts once this one has ended: app_run)
	if prefs_page.install_frame(&app.install) == .Launched { platform.request_close(app.main.win) }
	zoom_slider_build(app, em)
	columns_menu_build(app, em)
	jobs_view_build(app, em)
	options_follow(app)
	inspector_follow(app)
	dialogs_build(app)
	jobs_tidy(app)
	watcher_update(app)
	measure_update(app)
	thumbs_frame(app)
	icons_tidy(app)
}

// A text field built this frame: while it has the keyboard, the keys of the list are its own.
note_text_field :: proc(app: ^App, key: ui.Key) { append(&app.text_keys, key) }

// An icon of Lucide, `width` wide.
glyph :: proc(app: ^App, g: string, width: f32, fg: Maybe(ui.Color) = nil) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = app.icons, text_align = .Center, fg = fg})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###g%d", g, ui.parent_box().child_count))
}

// The corners of the small controls in the bars and the rows (the icon buttons, the crumbs, the address and rename
// fields): CONTROL_RADIUS_EM at appearance.rounding's default, as the rows' pill, square at 0. Fixed_Radius: the toolkit
// would scale it by the rounding a second time, and square a corner this small at the default.
CONTROL_RADIUS_EM :: 0.15
control_look :: proc(em: f32) -> ui.Style_Mod { return {radius = em * CONTROL_RADIUS_EM * corner_k(), flags = {.Fixed_Radius}} }

// A small flat button with a Lucide icon; its tooltip says what it does. `on`: lit in the accent (a toggle that is on).
// `command`: the id of the command its click runs, and acts on what that command acts on (the palette's Shift+Enter on
// the command comes to this button); "": it runs none.
icon_action :: proc(app: ^App, id, g, tip: string, em: f32, enabled := true, on := false, command := "") -> bool {
	side := em * 2.0
	ui.next({width = ui.px(side), height = ui.px(side), text_pad = 0, fg = on ? ui.color("accent") : nil})
	ui.next_merge(control_look(em))
	sig := ui.button(id, icon = g, o = {tip = tip, icon_font = app.icons, disabled = !enabled})
	if command != "" { ui.act_command(sig.box, command) }
	return enabled && sig.clicked
}

// A tooltip after the pointer rests on `sig`'s box: its lines, one under the other.
hover_tip :: proc(sig: ui.Signal, lines: ..string) {
	if !ui.hovered_for(sig) || len(lines) == 0 { return }
	if ui.tooltip() {
		for l, i in lines {
			if l == "" { continue }
			if i > 0 { ui.push_tags("weak") }
			ui.tooltip_text(fmt.tprintf("%s###tip%d", ui.text_shown(l), i))
			if i > 0 { ui.pop_tags() }
		}
	}
}

// A thin vertical line between groups of buttons.
vrule :: proc(em: f32, height: f32 = 1.3) {
	ui.space(ui.TOOL_GAP)
	ui.next({width = ui.px(max(1, ui.scale())), height = ui.px(em * height), bg = ui.color("border")})
	ui.build_box({.Draw_Background}, fmt.tprintf("###rule%d", ui.parent_box().child_count))
	ui.space(ui.TOOL_GAP)
}

// The tooltip of a command: its title and its keys in effect, the person's own when they set some.
command_tip :: proc(app: ^App, id: string) -> string {
	c := command_find(id)
	if c == nil { return id }
	return ui.command_tip(app.commands[command_index(c)])
}

// A command's first keys in effect as text ("Ctrl+M, T"), the person's own binding when there is one; "" none.
command_keys :: proc(app: ^App, c: ^Command) -> string {
	return ui.command_shortcut(app.commands[command_index(c)])
}

////////////////////////////////
// The row at the top

@(private = "file")
build_top :: proc(app: ^App, em: f32) {
	if ui.tabs_over(.Folder, {ground = draw.hex(surfaces(app).list), edge = draw.hex(surfaces(app).edge)}) {
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOP_EM)), bg = draw.hex(surfaces(app).top)})
		ui.push_tags("bar")
		defer ui.pop_tags()
		if ui.title_bar("###titlebar", {.Draw_Background}) {
			// its bottom line, the whole width: ui.tab_face rises out of it as one shape with the panel below
			bar := ui.parent_box()
			bar.custom, bar.custom_user = ui.tab_line_draw, ui.tab_strip_look({})
			// each part as wide as what is under it: over the views docked at the left (the sidebar, its handle) the head,
			// then the columns sharing the panels' room, a line between two. The panels' room is the views' frame's content
			// as the last build laid it out; what is docked at each side keeps its width when the window is resized, so the
			// tabs move with their panels in the same frame (only a handle dragged is a frame behind). (each region starts on
			// the column of the line at the left of its panel: the shown tab's left line is that line going up, not a second
			// one beside it)
			line := max(1, ui.scale())
			cols := 0
			for p in app.panels { if !p.below { cols += 1 } }
			c := app.content_rect
			left, right: f32
			if c.max.x > c.min.x {
				left, right = max(c.min.x, 0), max(app.window_px_last.x - c.max.x, 0)
			}
			// (the head holds the logo and the sidebar's button while the sidebar is wide enough; over its folded rail only
			// the button, which unfolds it: both drawn in the rail's width ran over each other and over the first tab)
			toggle_w := em * (2.0 + ui.SPACE_1 + ui.SPACE_2)
			with_logo := left - line >= toggle_w + em * (1.8 + ui.SPACE_2)
			head := max(left - line, toggle_w)
			col_w := (app.window_px.x - left - right - f32(max(cols - 1, 0)) * line) / f32(max(cols, 1))
			ui.next({width = ui.px(head), height = ui.pct(1)})
			if ui.row(.Center, {}, "###head") {
				ui.space(ui.SPACE_2)
				if with_logo { logo_icon(em * 1.8) }
				ui.spacer(ui.fill())
				if icon_action(app, "sidebar", sidebar_shown(app) ? lucide.PANEL_LEFT : lucide.PANEL_RIGHT, command_tip(app, "sidebar"), em, command = "sidebar") { act_toggle_sidebar(app) }
				ui.space(ui.SPACE_1)
			}
			// (a column's top panel has its tabs here; a panel below another has them at its own top: panel_build)
			for p, i in app.panels {
				if p.below { continue }
				last := true
				for q in app.panels[i + 1:] { if !q.below { last = false; break } }
				// (the last region ends at the window's buttons: what is left of the bar)
				w: ui.Size = last ? ui.fill() : ui.px(col_w + line)
				tab_region(app, p, i, w, col_w, em)
			}
			// (an update to install, coming, or in place: a button before the window's own; nothing otherwise)
			if app.updates.updater != nil {
				ui.next({height = ui.px(ui.dense(em * 1.9))})
				if prefs_page.update_badge(app.updates.updater, proc(user: rawptr) { updates_restart((^App)(user)) }, app) != nil { ui.space(ui.CONTROL_GAP) }
			}
			ui.window_buttons()
		}
	}
}

// A tab's floating drag ghost corner radius: TAB_RADIUS_EM at a rounding of 1 (appearance.rounding), square at 0.
TAB_RADIUS_EM :: 0.6
tab_radius :: proc(em: f32) -> f32 { return em * TAB_RADIUS_EM * ui.rounding(ui.current_state()) }

// A panel's tabs, at the top of the window over it: as wide as TAB_EM, narrower when they do not fit; drawn with the
// toolkit's Folder tab face (ui.tab_face, ui.tab_body, ui.tab_strip_start), with an accent mark along the top when
// its panel has the keyboard. More tabs than the row holds at TAB_MIN_EM: they scroll on the toolkit's strip (its
// arrows, the wheel), the shown one brought into view, and a chevron lists them.
tab_region :: proc(app: ^App, p: ^Panel, index: int, width: ui.Size, room: f32, em: f32) {
	if ui.tabs_over(.Folder, {ground = draw.hex(surfaces(app).list), edge = draw.hex(surfaces(app).edge)}) {
		focused := index == app.focus
		id := fmt.tprintf("###tabs%d", index)
		// the tabs' room: the row's as laid out last time, less the new tab's button and the Folder strip lead
		// (the last panel's row ends at the window's buttons, short of the panel's width)
		avail := room - em * (4.5 + TAB_STRIP_LEAD_EM)
		if pb := ui.prev_box(id); pb != nil && pb.size.x > 0 { avail = pb.size.x - em * (TAB_ROW_END_EM + TAB_STRIP_LEAD_EM) }
		ui.next({width = width, height = ui.pct(1)})
		if ui.row(.Center, {.Clip}, id) {
			// (where a dragged tab lands in this row: a ghost of it there, the tabs after it moved along; the row's room
			// shared with it, or it would run past the row's end, cut)
			ghost_at := tab_ghost_slot(app, index)
			n := len(p.tabs) + (ghost_at >= 0 ? 1 : 0)
			// (too many even at their least width: the list's button takes its room from theirs)
			over := room > 0 && n > 0 && avail < f32(n) * em * TAB_MIN_EM
			if over { avail -= em * TAB_LIST_EM }
			tab_w := em * TAB_EM
			if room > 0 && n > 0 { tab_w = clamp(avail / f32(n), em * TAB_MIN_EM, em * TAB_EM) }
			// the tabs on the toolkit's strip: hugs its tabs (children_sum(0)) and gives way first when the row is short,
			// scrolling with arrows and leaving the Folder bottom line showing under the arrows (Strip_Options.edge)
			ui.next({height = ui.pct(1), axis = .X, cross = .End})
			close := -1
			if ui.strip("###tab_view", {edge = max(1, ui.scale())}) {
				view := ui.parent_box()
				ui.tab_strip_start()
				for t, i in p.tabs {
					if i == ghost_at { tab_ghost(app, tab_w, em) }
					on := i == p.active
					ui.next({width = ui.px(tab_w), height = ui.pct(1)})
					tab := ui.build_box({.Clickable, .Hot_Within, .Middle_Click}, fmt.tprintf("###tab%d", t.id))
					// (the mark along the top says, with several panels, which one has the keyboard)
					line := on && focused && len(app.panels) > 1 ? ui.color("accent") : ui.Color{}
					ui.tab_face(tab, on, line)
					if on { ui.strip_reveal(tab) }
					// (a tab scrolled out of the row takes no drop where it lies, over what is beside the row)
					part := ui.Rect{{max(tab.rect.min.x, view.rect.min.x), tab.rect.min.y}, {min(tab.rect.max.x, view.rect.max.x), tab.rect.max.y}}
					if part.max.x > part.min.x { drop_zone(app, part, t.path) }
					if app.drop_hover == t.path && !on { drop_mark(tab) }
					sig := ui.signal(tab)
					if ui.parent(tab) {
						if ui.tab_body() {
							// (fixed-width tabs: let tab_body span the tab so the title fills and Close stays at the right)
							ui.parent_box().pref[.X] = ui.pct(1)
							ui.space(ui.SPACE_3)
							path_icon(app, t.path, true, em * 1.6)
							ui.space(ui.ICON_GAP)
							ui.next({width = ui.fill(), height = ui.pct(1)})
							if !on { ui.push_tags("weak") }
							ui.label(fmt.tprintf("%s###title", ui.text_shown(tab_title(app, t))))
							if !on { ui.pop_tags() }
							if on || ui.hot_within(tab.key) {
								ui.next({width = ui.px(em * 1.6), height = ui.px(em * 1.6), font = app.icons, font_size = em * 0.85, text_pad = 0})
								ui.next_merge(control_look(em))
								if ui.button("close", icon = lucide.X, o = {icon_font = app.icons}).clicked { close = i }
							} else {
								ui.spacer(ui.px(em * 1.6))
							}
							ui.space(ui.SPACE_2)
						}
					}
					if sig.pressed { p.active = i; app.focus = index }
					if !app.tab_drag.active { hover_tip(sig, home_path(app, t.path), t.locked ? i18n.tr("Locked: folders open in a new tab") : "") }
					append(&app.tab_rects, Tab_Rect{index, i, tab.rect})
					tab_drag_signal(app, index, i, sig)
					// (the tab dragged, dimmed where it was: its ghost follows the pointer; not while its picture is read)
					if app.tab_drag.active && app.tab_drag.tab == t.id && app.tab_drag.alone == 0 { tab.transparency = 0.5 }
					if sig.middle_clicked { close = i }
					if sig.right_clicked {
						p.active, app.focus = i, index
						tab_menu_open(app)
					}
				}
				if ghost_at == len(p.tabs) { tab_ghost(app, tab_w, em) }
			}
			if over && icon_action(app, fmt.tprintf("tablist%d", index), lucide.CHEVRON_DOWN, i18n.tr("Every tab of the panel"), em) {
				app.focus = index
				tabs_menu_open(app, p)
			}
			ui.space(ui.TOOL_GAP)
			// (New tab acts on the panel with the keyboard: its button is that panel's)
			if icon_action(app, fmt.tprintf("newtab%d", index), lucide.PLUS, command_tip(app, "tab_new"), em, command = focused ? "tab_new" : "") {
				app.focus = index
				act_tab_new(app)
			}
			if close >= 0 { tab_close(app, p, close) }
		}
	}
}

////////////////////////////////
// The body

@(private = "file")
build_body :: proc(app: ^App, em: f32) {
	scale := ui.scale()
	// the panels in columns: a column a panel and the ones below it; a line between two columns, and between two panels
	// of a column
	resize(&app.panel_rects, len(app.panels))
	for i := 0; i < len(app.panels); {
		end := i + 1
		for end < len(app.panels) && app.panels[end].below { end += 1 }
		if i > 0 {
			ui.next({width = ui.px(max(1, scale)), height = ui.fill(), bg = ui.color("border")})
			ui.build_box({.Draw_Background}, fmt.tprintf("###panel_sep%d", i))
		}
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		if ui.column(.Start, {}, fmt.tprintf("###panel_col%d", i)) {
			for k in i ..< end {
				if k > i {
					ui.next({width = ui.fill(), height = ui.px(max(1, scale)), bg = ui.color("border")})
					ui.build_box({.Draw_Background}, fmt.tprintf("###panel_hsep%d", k))
				}
				ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
				app.panel_rects[k] = panel_build(app, app.panels[k], k, em)
			}
		}
		i = end
	}
}

////////////////////////////////
// The keys of the list that change the selection (the moves with Shift, Ctrl and Ctrl+Shift, Ctrl+Space, Escape); the
// plain moves of the details are the list's own, the grid's and the columns view's are here.

@(private = "file")
list_keys :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	f := &t.folder
	n := len(f.shown)
	if n == 0 { return }
	grid := tab_mode(t) >= .Columns
	// the item each key takes the cursor to is the toolkit's (item_move_target): by rows of the list (one item a line),
	// by rows of cards (the grid's cards a line), down a column of the columns view (its names a column)
	flow := tab_mode(t) == .Columns ? ui.Item_Flow.Columns : ui.Item_Flow.Lines
	per := tab_row_items(t)
	page := max(t.vl.page_rows - 1, 1)
	keys := [?]platform.Key{.Down, .Up, .Right, .Left, .Page_Down, .Page_Up, .Home, .End}
	// what the move does to the selection is the toolkit's (item_selection_move): alone, the row alone; Shift, the range;
	// Ctrl+Shift, the range added; Ctrl, the cursor alone. The details' list makes its own moves alone (t.vl.changed).
	for mods in ([4]platform.Modifiers{{}, {.Shift}, {.Ctrl}, {.Ctrl, .Shift}}) {
		if mods == {} && !grid { continue }
		for key in keys {
			// (Ctrl+Page Up and Page Down go to the tabs)
			if .Ctrl in mods && (key == .Page_Up || key == .Page_Down) { continue }
			// (a key that is no move here, Left and Right in the details, stays for the tree below)
			to, ok := ui.item_move_target(key, f.sel, n, per, flow, page)
			if !ok || !ui.key_press(key, mods) { continue }
			ui.item_selection_move(&f.selection, folder_rows(f), to, mods)
			ui.list_select(&t.vl, grid ? f.sel / per : f.sel)
		}
	}
	if ui.key_press(.Space, {.Ctrl}) { ui.item_selection_toggle(&f.selection, folder_rows(f), f.sel) }
	// the tree: Right opens the folder at the cursor in place, Left closes it (or goes to the folder that holds it)
	if f.tree && !grid {
		if e := folder_cursor_entry(f); e != nil {
			name := strings.clone(e.name, context.temp_allocator)
			if ui.key_press(.Right) && e.kind == .Directory && !tab_tree_is_open(t, name) { tab_tree_toggle(app, t, name) }
			if ui.key_press(.Left) {
				if e.kind == .Directory && tab_tree_is_open(t, name) {
					tab_tree_toggle(app, t, name)
				} else if parent := fs.parent(name); parent != "" {
					folder_cursor_to_name(f, parent)
					folder_pick(f, f.sel)
					ui.list_select(&t.vl, f.sel)
				}
			}
		}
	}
	// (Escape ends a gesture first: a drag, a rectangle, the jobs' view; then, on several rows, the toolkit's rule: the
	// cursor's row alone. On one row, Escape goes on to the rest of the window.)
	if !gesture_running(app) && ui.key_pressed_peek(.Escape) && ui.item_selection_escape(&f.selection, folder_rows(f)) { _ = ui.key_press(.Escape) }
	if ui.key_press(.Menu) || ui.key_press(.F10, {.Shift}) {
		if f.sel >= 0 { entry_menu_open(app, t, {t.cursor_rect.min.x + 24, t.cursor_rect.max.y}, from_keyboard = true) }
	}
}

// A gesture that Escape ends is running: files or a tab dragged, a rectangle drawn, a section of the sidebar or a
// bookmark dragged, the jobs' view open.
gesture_running :: proc(app: ^App) -> bool {
	return app.file_drag || app.tab_drag.active || app.band.active || app.band.pending || app.side_dragging || app.bm_dragging || app.jobs_view.open
}

// Escape ends the gesture running, before anything built takes it (a focused list takes Escape for itself): the files'
// or the tab's drag given up, the rectangle's selection undone, the jobs' view closed. A press still held starts nothing
// more till its release (gesture_cancelled).
gesture_escape :: proc(app: ^App) {
	if !gesture_running(app) || !ui.key_press(.Escape) { return }
	switch {
	case app.file_drag:
		file_drag_end(app)
		app.gesture_cancelled = true
	case app.tab_drag.active:
		app.tab_drag.active = false
		tab_image_free(app)
		app.gesture_cancelled = true
	case app.band.active || app.band.pending:
		band_cancel(app)
		app.gesture_cancelled = true
	case app.side_dragging:
		app.side_dragging, app.side_held, app.side_cancelled = false, false, true
	case app.bm_dragging:
		// (the bookmarks keep their order)
		app.bm_dragging, app.bm_held, app.bm_cancelled, app.bm_line = false, false, true, {}
		app.gesture_cancelled = true
	case app.jobs_view.open:
		app.jobs_view.open = false
	}
	app_frames(app)
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
		ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###job%d", job_status_text(job, ui.now_ms()), job.id))
		ui.next({width = ui.px(em * 7), height = ui.px(em * 0.45)})
		ui.progress(fmt.tprintf("###jobbar%d", job.id), clamp(t, 0, 1), st == .Counting)
		ui.space(ui.SPACE_1)
		if icon_action(app, fmt.tprintf("jobcancel%d", job.id), lucide.X, i18n.tr("Cancel"), em) { job_cancel(job) }
		vrule(em)
		return
	}
}
