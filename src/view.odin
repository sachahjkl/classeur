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
// What a row of tabs holds after them: the new tab's button and the room around it, in ems.
TAB_ROW_END_EM :: 2.8
// The button of the list of the tabs, before the new tab's (a row with more tabs than it holds), in ems.
TAB_LIST_EM :: 2

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	app.room = size.x / max(ui.scale(), 0.01)
	app.window_px = size
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
	app.no_dialog = !app.palette.open && app.palette.recording < 0 && !app.goto.open && !app.batch.open && !app.layouts.naming && !app.setup.open && !app.confirm.open && !app.conflict.open && !app.options.open && !app.shortcuts_open
	keys_follow(app)
	if app.no_dialog {
		gesture_escape(app)
		// (the sidebar or the inspector has the keyboard: its moves are its own, the commands that act on the list's
		// rows (Enter, Delete, Space...) wait; those that work while typing still run)
		elsewhere := app.keys_at != .List
		commands_keys(app, typing || elsewhere)
		if !typing && !elsewhere { list_keys(app) }
	}

	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y, bg = draw.hex(surfaces(app).list)})
	page := ui.build_box({.Draw_Background}, "###page")
	if ui.parent(page) {
		// (the sidebar's width held in the window's room first: the title bar's parts are worked out from it)
		app.sidebar_px = clamp(app.sidebar_px, SIDEBAR_MIN_PX, max(min(SIDEBAR_MAX_PX, app.room - PANELS_MIN_PX), SIDEBAR_MIN_PX))
		build_top(app, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() { build_body(app, em) }
	}
	tab_drag_overlay(app, em)
	file_drag_frame(app, em)
	entry_menu_build(app, em)
	side_menu_build(app, em)
	panel_menus_build(app, em)
	palette_build(app)
	goto_build(app)
	batch_build(app, em)
	layouts_build(app, em)
	setup_build(app, em)
	zoom_slider_build(app, em)
	columns_menu_build(app, em)
	jobs_view_build(app, em)
	options_build(app)
	dialogs_build(app, em)
	jobs_tidy(app)
	watcher_update(app)
	measure_update(app)
	thumbs_tidy(app)
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
icon_action :: proc(app: ^App, id, g, tip: string, em: f32, enabled := true, on := false) -> bool {
	side := em * 2.0
	ui.next({width = ui.px(side), height = ui.px(side), text_pad = 0, fg = on ? ui.color("accent") : nil})
	ui.next_merge(control_look(em))
	sig := ui.button(id, icon = g, o = {tip = tip, icon_font = app.icons, disabled = !enabled})
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
	ui.spacer(ui.px(em * 0.35))
	ui.next({width = ui.px(max(1, ui.scale())), height = ui.px(em * height), bg = ui.color("border")})
	ui.build_box({.Draw_Background}, fmt.tprintf("###rule%d", ui.parent_box().child_count))
	ui.spacer(ui.px(em * 0.35))
}

// The tooltip of a command: its title and its keys, the person's own when they set some.
command_tip :: proc(app: ^App, id: string) -> string {
	c := command_find(id)
	if c == nil { return id }
	keys := command_keys(app, c)
	if keys == "" { return i18n.tr(c.title) }
	return fmt.tprintf("%s (%s)", i18n.tr(c.title), keys)
}

// A command's first keys as text ("Ctrl+M, T"), the person's own binding when there is one; "" none.
command_keys :: proc(app: ^App, c: ^Command) -> string {
	b := command_bindings(app, c)
	return len(b) > 0 ? binding_text(b[0]) : ""
}

////////////////////////////////
// The row at the top

@(private = "file")
build_top :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOP_EM)), bg = draw.hex(surfaces(app).top)})
	ui.push_tags("bar")
	defer ui.pop_tags()
	if ui.title_bar("###titlebar", {.Draw_Background}) {
		// its bottom line, the whole width: the shown tab paints over it (its own lines going up), one line with them
		edge := ui.frame_new(ui.Color)
		edge^ = draw.hex(surfaces(app).edge)
		bar := ui.parent_box()
		bar.custom, bar.custom_user = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
			w := max(1, ui.scale())
			draw.rect(dc, {{b.rect.min.x, b.rect.max.y - w}, b.rect.max}, (^ui.Color)(user)^)
		}, edge
		// each part as wide as what is under it, worked out as the body lays it out in this very frame (the sidebar, its
		// line, the columns sharing the rest, a line between two): a window resized moves the tabs with their panels,
		// not a frame after them. (each region starts on the column of the line at the left of its panel: the shown
		// tab's left line is that line going up, not a second one beside it)
		line := max(1, ui.scale())
		cols := 0
		for p in app.panels { if !p.below { cols += 1 } }
		side := app.sidebar ? app.sidebar_px * ui.scale() + line : 0
		col_w := (app.window_px.x - side - f32(max(cols - 1, 0)) * line) / f32(max(cols, 1))
		head := app.sidebar ? app.sidebar_px * ui.scale() : 0
		ui.next({width = ui.px(head), height = ui.pct(1)})
		if ui.row(.Center, {}, "###head") {
			ui.spacer(ui.px(em * 0.6))
			logo_icon(em * 1.8)
			ui.spacer(ui.fill())
			if icon_action(app, "sidebar", app.sidebar ? lucide.PANEL_LEFT : lucide.PANEL_RIGHT, command_tip(app, "sidebar"), em) { act_toggle_sidebar(app) }
			ui.spacer(ui.px(em * 0.3))
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
		if app.updater != nil {
			ui.next({height = ui.px(ui.dense(em * 1.9))})
			if prefs_page.update_badge(app.updater, proc(user: rawptr) { updates_restart((^App)(user)) }, app) { ui.spacer(ui.px(em * 0.5)) }
		}
		ui.window_buttons()
	}
}

Tab_Paint :: struct { base, edge, line: ui.Color, radius: f32 }

// The shown tab: its surface, a line at its left, top and right; none at its bottom, where the toolbar goes on. With a
// `line` (the panel that has the keyboard, among several), its top edge is that colour, tab_line_px() thick: in place
// of the edge there, one line and not two side by side.
tab_paint :: proc(b: ^ui.Box, base, edge, line: ui.Color, radius: f32) {
	d := ui.frame_new(Tab_Paint)
	d^ = {base, edge, line, radius}
	b.custom = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		d := (^Tab_Paint)(user)
		r := b.rect
		w := max(1, ui.scale())
		// (its top corners: its foot is the toolbar's top, one surface)
		corners :: proc(radius: f32) -> [4]f32 { return {max(radius, 0), 0, max(radius, 0), 0} }
		lw := w
		if d.line.a > 0 {
			// the accent over the whole shape, then the edge below it: the accent shows along its top and caps its
			// corners
			lw = tab_line_px()
			draw.rect_corners(dc, r, {d.line, d.line, d.line, d.line}, corners(d.radius))
			below := ui.Rect{{r.min.x, r.min.y + lw}, r.max}
			draw.rect_corners(dc, below, {d.edge, d.edge, d.edge, d.edge}, corners(d.radius - lw))
		} else {
			draw.rect_corners(dc, r, {d.edge, d.edge, d.edge, d.edge}, corners(d.radius))
		}
		inner := ui.Rect{{r.min.x + w, r.min.y + lw}, {r.max.x - w, r.max.y}}
		draw.rect_corners(dc, inner, {d.base, d.base, d.base, d.base}, corners(d.radius - lw))
	}
	b.custom_user = d
}

// The thickness of the accent along the top of the focused panel's shown tab: two lines' worth, so that it reads at a
// glance which panel has the keyboard.
tab_line_px :: proc() -> f32 { return max(1, ui.scale()) * 2 }

// A tab's top corners: TAB_RADIUS_EM at a rounding of 1 (appearance.rounding), square at 0.
TAB_RADIUS_EM :: 0.6
tab_radius :: proc(em: f32) -> f32 { return em * TAB_RADIUS_EM * ui.rounding(ui.current_state()) }

// A panel's tabs, at the top of the window over it: as wide as TAB_EM, narrower when they do not fit; the shown one
// in the list's colour, with a line of the accent along its top when its panel has the keyboard. More tabs than the row
// holds at TAB_MIN_EM: they scroll sideways (the wheel), the shown one is brought into view, and a chevron lists them.
tab_region :: proc(app: ^App, p: ^Panel, index: int, width: ui.Size, room: f32, em: f32) {
	focused := index == app.focus
	id := fmt.tprintf("###tabs%d", index)
	// the tabs' room: the row's as laid out last time, less the new tab's button (the last panel's row ends at the
	// window's buttons, short of the panel's width); before that, the panel's width less a margin
	avail := room - em * 4.5
	if pb := ui.prev_box(id); pb != nil && pb.size.x > 0 { avail = pb.size.x - em * TAB_ROW_END_EM }
	ui.next({width = width, height = ui.pct(1)})
	if ui.row(.End, {.Clip}, id) {
		// (where a dragged tab lands in this row: a ghost of it there, the tabs after it moved along; the row's room
		// shared with it, or it would run past the row's end, cut)
		ghost_at := tab_ghost_slot(app, index)
		n := len(p.tabs) + (ghost_at >= 0 ? 1 : 0)
		// (too many even at their least width: the list's button takes its room from theirs)
		over := room > 0 && n > 0 && avail < f32(n) * em * TAB_MIN_EM
		if over { avail -= em * TAB_LIST_EM }
		tab_w := em * TAB_EM
		if room > 0 && n > 0 { tab_w = clamp(avail / f32(n), em * TAB_MIN_EM, em * TAB_EM) }
		// the tabs in a view that scrolls sideways, as wide as they are up to their room: the buttons after it stay
		view_w := f32(n) * tab_w
		if avail > 0 { view_w = min(view_w, avail) }
		view_flags := ui.Box_Flags{.Clip, .View_Scroll_X, .View_Clamp_X, .Allow_Overflow_X, .Scrollbar_None}
		if over { view_flags += {.Scroll_Self} }   // (a mouse's wheel turns one way only: over the tabs, it scrolls them)
		ui.next({width = ui.px(view_w), height = ui.pct(1), axis = .X, cross = .End})
		view := ui.build_box(view_flags, "###tab_view")
		if sig := ui.signal(view); over && sig.scrolled.y != 0 && sig.scrolled.x == 0 {
			view.view_target.x = clamp(view.view_target.x + sig.scrolled.y * ui.wheel_step(view, .X), 0, ui.view_limit(view, .X))
		}
		// a tab shown anew (opened, picked) comes into view, once the view has its width
		if shown := panel_tab(p); shown != nil && shown.id != p.tab_seen && view.size.x > 0 {
			slot := p.active + (ghost_at >= 0 && ghost_at <= p.active ? 1 : 0)
			ui.view_reveal(view, f32(slot) * tab_w, f32(slot + 1) * tab_w, .X)
			p.tab_seen = shown.id
		}
		close := -1
		if ui.parent(view) {
			for t, i in p.tabs {
				if i == ghost_at { tab_ghost(app, tab_w, em) }
				on := i == p.active
				// (square, from the panel's left edge: the shown tab is the top of the toolbar under it, one surface)
				// (a hidden tab's hover in the same shape: the rounding of the settings; the box's radius is scaled by it)
				ui.next({width = ui.px(tab_w), height = ui.px(ui.dense(em * (TOP_EM - 0.45))), axis = .Y, radius = em * TAB_RADIUS_EM})
				flags := ui.Box_Flags{.Clickable, .Hot_Within, .Middle_Click}
				if !on { flags += {.Draw_Hot_Effects} }
				tab := ui.build_box(flags, fmt.tprintf("###tab%d", t.id))
				// (the line of the accent along the top says, with several panels, which one has the keyboard)
				line := on && focused && len(app.panels) > 1 ? ui.color("accent") : ui.Color{}
				if on { tab_paint(tab, draw.hex(surfaces(app).list), draw.hex(surfaces(app).edge), line, tab_radius(em)) }
				// (a tab scrolled out of the row takes no drop where it lies, over what is beside the row)
				part := ui.Rect{{max(tab.rect.min.x, view.rect.min.x), tab.rect.min.y}, {min(tab.rect.max.x, view.rect.max.x), tab.rect.max.y}}
				if part.max.x > part.min.x { drop_zone(app, part, t.path) }
				if app.drop_hover == t.path && !on { drop_mark(tab) }
				sig := ui.signal(tab)
				if ui.parent(tab) {
					ui.spacer(ui.px(max(2, ui.scale() * 2)))
					ui.next({width = ui.fill(), height = ui.fill()})
					if ui.row(.Center) {
						ui.spacer(ui.px(em * 0.7))
						path_icon(app, t.path, true, em * 1.6)
						ui.spacer(ui.px(em * 0.4))
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
						ui.spacer(ui.px(em * 0.4))
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
		ui.spacer(ui.px(em * 0.3))
		if icon_action(app, fmt.tprintf("newtab%d", index), lucide.PLUS, command_tip(app, "tab_new"), em) {
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
		ui.next({width = ui.px(app.sidebar_px * scale), height = ui.fill()})
		sidebar_build(app, em)
		ui.splitter("###side_split", .X, &app.sidebar_px, SIDEBAR_MIN_PX, SIDEBAR_MAX_PX, {default_size = 240, total = app.room, min_other = PANELS_MIN_PX, flush = true})
	}
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
	if tab_mode(t) == .Columns {
		// (the columns view: down a column, across to the next one)
		clear(&moves)
		per := max(t.grid_cols, 1)
		for shift in ([]bool{false, true}) {
			mods := shift ? platform.Modifiers{.Shift} : platform.Modifiers{}
			append(&moves, Move{{.Down, mods}, f.cursor + 1, shift}, Move{{.Up, mods}, f.cursor - 1, shift},
				Move{{.Right, mods}, f.cursor + per, shift}, Move{{.Left, mods}, f.cursor - per, shift},
				Move{{.Page_Down, mods}, f.cursor + per, shift}, Move{{.Page_Up, mods}, f.cursor - per, shift},
				Move{{.Home, mods}, 0, shift}, Move{{.End, mods}, n - 1, shift})
		}
	} else if grid {
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
					folder_pick(f, f.cursor)
					ui.list_select(&t.vl, f.cursor)
				}
			}
		}
	}
	// (Escape ends a gesture first: a drag, a rectangle, the jobs' view; then the selection becomes the cursor's row)
	if f.count > 1 && !gesture_running(app) && ui.key_press(.Escape) { folder_pick(f, f.cursor) }
	if ui.key_press(.Menu) || ui.key_press(.F10, {.Shift}) {
		if f.cursor >= 0 { entry_menu_open(app, t, {t.cursor_rect.min.x + 24, t.cursor_rect.max.y}, from_keyboard = true) }
	}
}

// A gesture that Escape ends is running: files or a tab dragged, a rectangle drawn, a section of the sidebar or a
// bookmark dragged, the jobs' view open.
gesture_running :: proc(app: ^App) -> bool {
	return app.file_drag || app.tab_drag.active || app.band.active || app.side_dragging || app.bm_dragging || app.jobs_view.open
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
	case app.band.active:
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
		ui.spacer(ui.px(em * 0.2))
		if icon_action(app, fmt.tprintf("jobcancel%d", job.id), lucide.X, i18n.tr("Cancel"), em) { job_cancel(job) }
		vrule(em)
		return
	}
}
