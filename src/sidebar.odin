package classeur

// The sidebar, File Pilot's: a filter at the top, then sections that open and close: the recent folders, the
// bookmarks, the storage (each volume with a bar of how full it is), the network (the shares mounted, the devices
// found: network.odin), the places. A click goes there in the tab that has
// the keyboard; a middle click opens a new tab; a right click, the row's menu. A bookmark dragged up or down moves.

import "core:fmt"
import "core:strings"
import config "gt:config"
import "gt:draw"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

Side_Section :: enum u8 { Recents, Bookmarks, Storage, Network, Places }

// What a row of the sidebar is, for its menu: a recent and a bookmark have one more line.
Side_Row_Kind :: enum u8 { Place, Recent, Bookmark }

// (not rodata: i18n.later marks them for the catalogue; tr where they are shown)
@(private = "file")
SECTION_TITLES := [Side_Section]string{.Recents = i18n.later("Recents"), .Bookmarks = i18n.later("Bookmarks"), .Storage = i18n.later("Storage"), .Network = i18n.later("Network"), .Places = i18n.later("Places")}
@(private = "file", rodata)
SECTION_ICONS := [Side_Section]string{.Recents = lucide.HISTORY, .Bookmarks = lucide.BOOKMARK, .Storage = lucide.HARD_DRIVE, .Network = lucide.NETWORK, .Places = lucide.FOLDER}


// How full a volume is: its bar under its name.
VOLUME_FULL_AT  :: 0.9

// The sidebar with the keyboard (F6): a cursor over its rows, the headings left out.
Side_Keys :: struct {
	box:    ui.Key,     // the sidebar's box: the toolkit's focus while it has the keyboard
	cursor: int,        // the cursor's row, among the rows shown
	rows:   int,        // the rows shown at the last build: the cursor stops at the last
	moved:  bool,       // the cursor moved: its row comes into view
	seen:   int,        // (while built: the rows so far)
	path:   string,     // (while built: the cursor's place, the frame's)
	row:    ^ui.Box,    // (while built: the cursor's row)
}

sidebar_build :: proc(app: ^App, em: f32) {
	t := current_tab(app)
	here := t != nil ? t.path : ""
	k := &app.side_keys
	keys := app.keys_at == .Sidebar && app.no_dialog
	// (Up and Down by the rows of the last build; Left and Right taken: the toolkit's arrows would move the focus away)
	if keys {
		if ui.key_press(.Down) { k.cursor += 1; k.moved = true }
		if ui.key_press(.Up) { k.cursor -= 1; k.moved = true }
		_ = ui.key_press(.Left)
		_ = ui.key_press(.Right)
	}
	k.cursor = clamp(k.cursor, 0, max(k.rows - 1, 0))
	k.seen, k.path, k.row = 0, "", nil
	ui.next_merge({axis = .Y, bg = draw.hex(surfaces(app).side)})
	box := ui.build_box({.Clip, .Draw_Background}, "###sidebar")
	k.box = box.key
	if ui.parent(box) {
		side_filter(app, em)
		query := strings.to_lower(ui.field_string(&app.side_filter), context.temp_allocator)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.scroll_y("###side_scroll") {
			scroll := ui.parent_box()
			ui.spacer(ui.px(em * 0.3))
			// (the sections in the person's order: a heading dragged, or its menu's Move up and Move down)
			for sec in app.side_order {
				switch sec {
				case .Recents:
				if section(app, .Recents, em) {
						for p, i in app.recents {
							if !keeps(query, fs.base(p)) { continue }
							// (its name, then where it is in the weak colour: the name stays when the sidebar is narrow)
							name := fs.base(p)
							if name == "" { name = p }
							sig := side_folder(app, fmt.tprintf("###recent%d", i), p, name, p != name ? home_path(app, fs.parent(p)) : "", here, side_next(app, p), em)
							go_from(app, t, sig, p, .Recent)
						}
					}
				case .Bookmarks:
				if section(app, .Bookmarks, em) {
						side_bookmarks(app, t, query, here, em)
						if len(app.bookmarks) == 0 && query == "" {
							if ui.tags("weak") {
								ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8)), font_size = em * 0.85})
								if ui.row(.Center) {
									ui.spacer(ui.px(em * 2.6))
									ui.label(fmt.tprintf("%s###bm_hint", fmt.tprintf(i18n.tr("%s: bookmark a folder"), command_keys(app, command_find("bookmark")))))
								}
							}
						}
					}
				case .Storage:
				if section(app, .Storage, em) {
						for v, i in app.volumes {
							if !keeps(query, v.label) { continue }
							sp := i < len(app.volume_space) ? app.volume_space[i] : fs.Space{}
							go_from(app, t, side_volume(app, i, v, sp, v.path == here, side_next(app, v.path), em), v.path)
						}
					}
				case .Network:
				// (the shares of the network mounted now: gvfs's and the kernel's on Linux, the network's drives on Windows;
				// then the devices found on the network. Shown or opened again: a new search)
				open := section(app, .Network, em)
				if open && !app.devices_seen_open && !app.devices_searching { network_find(app) }
				app.devices_seen_open = open
				if open {
						for sh, i in app.shares {
							if !keeps(query, sh.label) { continue }
							sig := side_row(app, fmt.tprintf("###share%d", i), sh.path, sh.label, sh.path == here, side_next(app, sh.path), em)
							go_from(app, t, sig, sh.path)
						}
						side_devices(app, t, query, em)
					}
				case .Places:
				if section(app, .Places, em) {
						for p, i in app.places {
							if !keeps(query, p.name) { continue }
							sig := side_row(app, fmt.tprintf("###place%d", i), p.path, p.name, p.path == here, side_next(app, p.path), em)
							go_from(app, t, sig, p.path)
						}
					}
				}
			}
			app.side_end_y = ui.parent_box().rect.min.y - ui.parent_box().view_off.y + ui.parent_box().view_bounds.y
			ui.spacer(ui.px(em * 0.6))
			// (the cursor moved: its row in view, as the last layout placed it)
			if k.moved && k.row != nil {
				top := k.row.rect.min.y - scroll.rect.min.y + scroll.view_off.y
				ui.view_reveal(scroll, top, top + k.row.rect.max.y - k.row.rect.min.y, margin = em * 0.5)
				k.moved = false
			}
		}
		// (out of the scrolled list: the line and the tint are placed on the screen)
		side_drag_end(app, em)
		bookmark_line(app)
	}
	k.rows = k.seen
	// Enter goes to the cursor's place in the tab that has the keyboard, Ctrl+Enter in a new tab; either, or Escape, gives
	// the keyboard back to the list
	if keys {
		switch {
		case ui.key_press(.Return):
			if t != nil && k.path != "" { tab_go(app, t, k.path) }
			keys_to(app, .List)
		case ui.key_press(.Return, {.Ctrl}):
			if k.path != "" { tab_open(app, current_panel(app), k.path, current_panel(app).active + 1) }
			keys_to(app, .List)
		case ui.key_press(.Escape):
			keys_to(app, .List)
		}
	}
}

// One more row of the sidebar: whether the keyboard's cursor is on it (its place kept for Enter).
@(private = "file")
side_next :: proc(app: ^App, path: string) -> bool {
	k := &app.side_keys
	at := k.seen
	k.seen += 1
	if app.keys_at != .Sidebar || at != k.cursor { return false }
	k.path = strings.clone(path, context.temp_allocator)
	return true
}

@(private = "file")
Side_Ring :: struct { color: ui.Color, inset, radius: f32 }

// The keyboard's cursor on the row `b`: a ring of the accent, as the list's cursor.
@(private = "file")
side_cursor_mark :: proc(app: ^App, b: ^ui.Box, em: f32) {
	d := ui.frame_new(Side_Ring)
	d^ = {ui.color("accent"), em * ROW_INSET_EM, max(1, ui.scale()) * 2 * corner_k()}
	b.custom, b.custom_user = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		d := (^Side_Ring)(user)
		px := max(1, ui.scale())
		r := ui.Rect{{b.rect.min.x + d.inset, b.rect.min.y + px}, {b.rect.max.x - d.inset, b.rect.max.y - px}}
		draw.rect(dc, r, d.color, radius = d.radius, border = px)
	}, d
	app.side_keys.row = b
}

@(private = "file")
keeps :: proc(query, name: string) -> bool {
	return query == "" || strings.contains(strings.to_lower(name, context.temp_allocator), query)
}

@(private = "file")
go_from :: proc(app: ^App, t: ^Tab, sig: ui.Signal, path: string, kind := Side_Row_Kind.Place) {
	if sig.clicked && t != nil { tab_go(app, t, path) }
	if sig.middle_clicked { tab_open(app, current_panel(app), path, current_panel(app).active + 1) }
	if sig.right_clicked { side_row_menu_open(app, path, kind) }
}

// The bookmarks. One dragged past a few pixels lands where it is let go: before the first row whose middle is under
// the pointer (the line shows where while it is held). A filtered list has gaps: it does not reorder.
@(private = "file")
side_bookmarks :: proc(app: ^App, t: ^Tab, query, here: string, em: f32) {
	rects := make([dynamic]ui.Rect, context.temp_allocator)
	for p, i in app.bookmarks {
		if !keeps(query, fs.base(p)) { continue }
		sig := side_folder(app, fmt.tprintf("###bookmark%d", i), p, fs.base(p), "", here, side_next(app, p), em)
		append(&rects, sig.box.rect)
		// (the release of a drag is no click, nor that of a drag Escape cancelled)
		moved := app.bm_dragging && app.bm_drag == i
		cancelled := app.bm_cancelled && app.bm_drag == i
		if cancelled && !sig.dragging { app.bm_cancelled = false }
		if query == "" && !moved && !cancelled && !app.gesture_cancelled && sig.dragging && abs(sig.drag_delta.y) > em * 0.5 { app.bm_drag, app.bm_dragging, moved = i, true, true }
		if moved { app.bm_held = sig.dragging } else if !cancelled { go_from(app, t, sig, p, .Bookmark) }
	}
	app.bm_line = {}
	if !app.bm_dragging { return }
	if len(rects) != len(app.bookmarks) || app.bm_drag >= len(app.bookmarks) { app.bm_dragging = false; return }
	y := ui.mouse_pos().y
	slot := 0
	for r, i in rects { if y > (r.min.y + r.max.y) * 0.5 { slot = i + 1 } }
	if app.bm_held {
		line_y := slot < len(rects) ? rects[slot].min.y : rects[len(rects) - 1].max.y
		app.bm_line = {{rects[0].min.x, line_y}, {rects[0].max.x, line_y}}
		app_frames(app)
		return
	}
	app.bm_dragging = false
	to := slot > app.bm_drag ? slot - 1 : slot
	ui.list_move(app.bookmarks[:], app.bm_drag, to, 0)
}

// Where a dragged bookmark lands: a line of the accent, placed on the screen (out of the scrolled list).
@(private = "file")
bookmark_line :: proc(app: ^App) {
	if app.bm_line == {} { return }
	parent := ui.parent_box()
	w := max(2, ui.scale() * 2)
	ui.next({width = ui.px(app.bm_line.max.x - app.bm_line.min.x), height = ui.px(w), bg = ui.color("accent"), radius = 0})
	line := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background}, "###bookmark_line")
	line.fixed_pos = ui.Vec2{app.bm_line.min.x, app.bm_line.min.y - w * 0.5} - parent.rect.min
}

// A row's menu: its place opened, its path, a terminal there; for a bookmark its removal, for a recent the recents
// cleared.
@(private = "file")
side_row_menu_open :: proc(app: ^App, path: string, kind: Side_Row_Kind) {
	if app.side_row_key == 0 { app.side_row_key = ui.key_from_string(0, "classeur_side_row_menu") }
	delete(app.side_row_path)
	app.side_row_path, app.side_row_kind = strings.clone(path), kind
	ui.ctx_menu_open(app.side_row_key, ui.mouse_pos())
}

@(private = "file")
side_row_menu_build :: proc(app: ^App) {
	if app.side_row_key == 0 { return }
	if ui.ctx_menu(app.side_row_key) {
		path := app.side_row_path
		if side_item("open") {
			if t := current_tab(app); t != nil { tab_go(app, t, path) }
		}
		if side_item("open_new_tab") { tab_open(app, current_panel(app), path, current_panel(app).active + 1) }
		if side_item("open_other_panel") { open_other_panel_at(app, path) }
		ui.menu_separator()
		if side_item("copy_path") { path_to_clipboard(app, path) }
		if side_item("terminal") { terminal_at(app, path) }
		switch app.side_row_kind {
		case .Bookmark:
			ui.menu_separator()
			if ui.menu_item(fmt.tprintf("%s###bm_remove", i18n.tr("Remove the bookmark")), icon = lucide.BOOKMARK).clicked { bookmark_toggle(app, path) }
		case .Recent:
			ui.menu_separator()
			menu_command(app, "recents_clear")
		case .Place:
		}
	}
}

// An item with a command's title and icon that acts on the row's place, not on the list: no keys shown (they are the
// list's).
@(private = "file")
side_item :: proc(id: string) -> bool {
	c := command_find(id)
	return c != nil && ui.menu_item(fmt.tprintf("%s###%s", i18n.tr(c.title), c.id), icon = c.icon).clicked
}

@(private = "file")
side_filter :: proc(app: ^App, em: f32) {
	// (as tall as the panels' toolbars: their lines meet across the window)
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOOLBAR_EM))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###side_filter") {
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.6) }
		key := ui.key_from_string(ui.parent_box().key, "###sfilter")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###sfilter", &app.side_filter, "Filter...", clearable = true) }
		note_text_field(app, key)
		if res.cancelled { ui.field_clear(&app.side_filter) }
		ui.spacer(ui.px(em * 0.4))
	}
}

// A section's heading: its icon, its title, a chevron; a click opens or closes it. True: it is open.
@(private = "file")
section :: proc(app: ^App, s: Side_Section, em: f32) -> bool {
	open := app.side_open[s]
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects, .Hot_Within}, fmt.tprintf("###sec_%s", SECTION_TITLES[s])) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 0.6))
		if ui.tags("weak") { glyph(app, SECTION_ICONS[s], em * 1.6) }
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", i18n.tr(SECTION_TITLES[s])))
		if ui.tags("weak") { glyph(app, open ? lucide.CHEVRON_DOWN : lucide.CHEVRON_RIGHT, em * 1.6) }
		ui.spacer(ui.px(em * 0.5))
	}
	app.side_heads[s] = sig.box.rect
	// dragged past a few pixels: the section moves where it is let go (side_drag_end); a right click: its menu
	// (a drag cancelled by Escape stays so until its button comes up)
	if app.side_cancelled && s == app.side_drag && !sig.dragging { app.side_cancelled = false }
	if sig.dragging && abs(sig.drag_delta.y) > em * 0.5 && !app.side_cancelled { app.side_drag, app.side_dragging, app.side_menu_of, app.side_touched = s, true, s, true }
	if app.side_dragging && app.side_drag == s { app.side_held = sig.dragging }
	if sig.clicked && !(app.side_dragging && app.side_drag == s) { app.side_open[s] = !open }
	if sig.clicked || sig.right_clicked { app.side_menu_of, app.side_touched = s, true }   // (the section the commands move)
	if sig.right_clicked { side_menu_open(app, s) }
	hover_tip(sig, i18n.tr("Drag it, or right-click it, to move the section"))
	return app.side_open[s]
}

// The order of the sections as the preference says it ("recents,bookmarks,storage,network,places"); a name it does not know,
// or one missing, keeps the default's place.
side_order_read :: proc(app: ^App, text: string) {
	order: [dynamic]Side_Section
	order.allocator = context.temp_allocator
	for word in strings.split(text, ",", context.temp_allocator) {
		for title, sec in SECTION_TITLES {
			if strings.to_lower(title, context.temp_allocator) == strings.trim_space(word) && !slice_has(order[:], sec) { append(&order, sec) }
		}
	}
	for sec in Side_Section { if !slice_has(order[:], sec) { append(&order, sec) } }
	for sec, i in order[:len(Side_Section)] { app.side_order[i] = sec }
}

@(private = "file")
slice_has :: proc(list: []Side_Section, s: Side_Section) -> bool {
	for x in list { if x == s { return true } }
	return false
}

// The section `s` to place `to` (0: the top), the order kept in the preferences.
side_move :: proc(app: ^App, s: Side_Section, to: int) {
	from := 0
	for x, i in app.side_order { if x == s { from = i } }
	at := clamp(to, 0, len(Side_Section) - 1)
	if from == at { return }
	ui.list_move(app.side_order[:], from, at, 0)
	b := strings.builder_make(context.temp_allocator)
	for x, i in app.side_order {
		if i > 0 { strings.write_byte(&b, ',') }
		strings.write_string(&b, strings.to_lower(SECTION_TITLES[x], context.temp_allocator))
	}
	config.set_string(&app.prefs, config.ref_of(&app.prefs, "side.order"), strings.to_string(b))
}

// The place a dragged heading goes: before the first heading whose middle is under the pointer, else at the end. While
// it drags: the line where it lands, the pointer's; let go: the section moves there.
@(private = "file")
side_drag_end :: proc(app: ^App, em: f32) {
	if !app.side_dragging { return }
	y := ui.mouse_pos().y
	slot := 0
	for sec, i in app.side_order {
		r := app.side_heads[sec]
		if y > (r.min.y + r.max.y) * 0.5 { slot = i + 1 }
	}
	from := 0
	for x, i in app.side_order { if x == app.side_drag { from = i } }
	to := slot > from ? slot - 1 : slot
	if app.side_held {
		// the heading tinted, and the line where it lands: above the heading of its slot, or under the last section
		line_y: f32
		if slot < len(app.side_order) { line_y = app.side_heads[app.side_order[slot]].min.y } else { line_y = app.side_end_y }
		head := app.side_heads[app.side_drag]
		parent := ui.parent_box()
		accent := ui.color("accent")
		w := max(2, ui.scale() * 2)
		ui.next({width = ui.px(head.max.x - head.min.x), height = ui.px(head.max.y - head.min.y), bg = accent * {1, 1, 1, 0.18}, radius = 0})
		tint := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background}, "###side_drag_tint")
		tint.fixed_pos = head.min - parent.rect.min
		ui.next({width = ui.px(head.max.x - head.min.x), height = ui.px(w), bg = accent, radius = 0})
		line := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background}, "###side_drag_line")
		line.fixed_pos = ui.Vec2{head.min.x, line_y - w * 0.5} - parent.rect.min
		return
	}
	app.side_dragging = false
	side_move(app, app.side_drag, to)
}

// A section's menu: where it goes.
side_menu_open :: proc(app: ^App, s: Side_Section) {
	if app.side_menu_key == 0 { app.side_menu_key = ui.key_from_string(0, "classeur_side_menu") }
	app.side_menu_of, app.side_touched = s, true
	ui.ctx_menu_open(app.side_menu_key, ui.mouse_pos())
}

side_menu_build :: proc(app: ^App, em: f32) {
	side_row_menu_build(app)
	side_device_menu_build(app)
	if app.side_menu_key == 0 { return }
	if ui.ctx_menu(app.side_menu_key) {
		s := app.side_menu_of
		at := 0
		for x, i in app.side_order { if x == s { at = i } }
		last := len(Side_Section) - 1
		menu_command(app, "side_up", enabled = at > 0)
		menu_command(app, "side_down", enabled = at < last)
		ui.menu_separator()
		if ui.menu_item(i18n.tr("Move to the top"), enabled = at > 0).clicked { side_move(app, s, 0) }
		if ui.menu_item(i18n.tr("Move to the bottom"), enabled = at < last).clicked { side_move(app, s, last) }
		ui.menu_separator()
		if ui.menu_item(app.side_open[s] ? i18n.tr("Close the section") : i18n.tr("Open the section"), icon = app.side_open[s] ? lucide.CHEVRON_RIGHT : lucide.CHEVRON_DOWN).clicked { app.side_open[s] = !app.side_open[s] }
		if s == .Network { menu_command(app, "network_find") }
	}
}

// A folder's row: its name, and `under` (where it is) after it in the weak colour.
@(private = "file")
side_folder :: proc(app: ^App, id, path, name, under: string, here: string, cursor: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	on := path == here
	if on { flags += {.Draw_Background} }
	ui.next_merge({bg = on ? ui.color("border") : nil})
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		if cursor { side_cursor_mark(app, ui.parent_box(), em) }
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		if under == "" {
			ui.next({width = ui.fill(), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###n", ui.text_shown(name)))
		} else {
			ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###n", ui.text_shown(name)))
			ui.next({width = ui.fill(), height = ui.pct(1)})
			if ui.tags("weak") { ui.label(fmt.tprintf("%s###under", ui.text_shown(under))) }
		}
		drop_zone(app, ui.parent_box().rect, path)
		if app.drop_hover == path { drop_mark(ui.parent_box()) }
	}
	hover_tip(sig, home_path(app, path))
	return
}

@(private = "file")
side_row :: proc(app: ^App, id, path: string, name: string, here: bool, cursor: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0, bg = here ? ui.color("border") : nil})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	if here { flags += {.Draw_Background} }
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		if cursor { side_cursor_mark(app, ui.parent_box(), em) }
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", ui.text_shown(name)))
		drop_zone(app, ui.parent_box().rect, path)
		if app.drop_hover == path { drop_mark(ui.parent_box()) }
	}
	hover_tip(sig, home_path(app, path))
	return
}

@(private = "file")
Bar_Draw :: struct { used: f32, bar, track: ui.Color }

@(private = "file")
bar_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Bar_Draw)(user)
	r := b.rect
	// (square at every rounding: a bar three pixels thick has no corner to round, as the Size column's bar)
	draw.rect(dc, r, d.track)
	draw.rect(dc, {r.min, {r.min.x + (r.max.x - r.min.x) * d.used, r.max.y}}, d.bar)
}

// A volume: its icon, its name, and under the name a bar of how full it is.
@(private = "file")
side_volume :: proc(app: ^App, i: int, v: fs.Volume, sp: fs.Space, here: bool, cursor: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.5)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	if here { flags += {.Draw_Background} }
	ui.next_merge({bg = here ? ui.color("border") : nil})
	if ui.row(.Center, flags, fmt.tprintf("###vol%d", i)) {
		sig = ui.signal(ui.parent_box())
		if cursor { side_cursor_mark(app, ui.parent_box(), em) }
		drop_zone(app, ui.parent_box().rect, v.path)
		if app.drop_hover == v.path { drop_mark(ui.parent_box()) }
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, v.path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.45)})
			ui.label(fmt.tprintf("%s###n", ui.text_shown(v.label)))
			ui.spacer(ui.px(em * 0.1))
			if sp.total > 0 {
				used := 1 - f32(f64(sp.free) / f64(sp.total))
				d := ui.frame_new(Bar_Draw)
				d^ = {used, used > VOLUME_FULL_AT ? ui.color("bad text") : ui.color("accent"), ui.color("border")}
				ui.next({width = ui.fill(), height = ui.px(max(3, em * 0.25))})
				ui.custom("###bar", bar_draw, d)
			}
			ui.spacer(ui.fill())
		}
		ui.spacer(ui.px(em * 0.8))
	}
	hover_tip(sig, v.path, sp.total > 0 ? fmt.tprintf(i18n.tr("%s free of %s"), size_text(sp.free), size_text(sp.total)) : "")
	return
}

// The section last touched (a click or a right click on its heading) a place up or down (its keys, its menu's lines).
act_side_up :: proc(app: ^App) { side_step(app, -1) }
act_side_down :: proc(app: ^App) { side_step(app, 1) }

@(private = "file")
side_step :: proc(app: ^App, by: int) {
	// (no section touched yet: none to move)
	if !app.side_touched { say(app, i18n.tr("Click a section's heading first: its keys move that one.")); return }
	s := app.side_menu_of
	for x, i in app.side_order {
		if x != s { continue }
		side_move(app, s, i + by)
		return
	}
}

@(private = "file", rodata)
DEVICE_ICONS := [fs.Device_Kind]string{.File_Server = lucide.SERVER, .Computer = lucide.MONITOR, .Web = lucide.GLOBE}

// The devices found on the network: a click opens the first of their services in the tab, a right click lists them
// all. Under them a weak line while a search runs, or when it found none.
@(private = "file")
side_devices :: proc(app: ^App, t: ^Tab, query: string, em: f32) {
	for d, i in app.devices {
		if len(d.services) == 0 || !keeps(query, d.name) { continue }
		uri := d.services[0].uri
		sig := side_device(app, i, d, side_next(app, uri), em)
		if sig.clicked && t != nil { tab_go(app, t, uri) }
		if sig.middle_clicked { tab_open(app, current_panel(app), uri, current_panel(app).active + 1) }
		if sig.right_clicked { side_device_menu_open(app, d) }
	}
	note := ""
	if app.devices_searching {
		note = i18n.tr("Searching…")
	} else if len(app.devices) == 0 {
		note = i18n.tr("No device found")
	}
	if note == "" || query != "" { return }
	if ui.tags("weak") {
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8)), font_size = em * 0.85})
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 2.6))
			ui.label(fmt.tprintf("%s###net_note", note))
		}
	}
}

// A device: the icon of its kind, its name; its host and its first service's URI in its tip.
@(private = "file")
side_device :: proc(app: ^App, i: int, d: fs.Network_Device, cursor: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}, fmt.tprintf("###device%d", i)) {
		sig = ui.signal(ui.parent_box())
		if cursor { side_cursor_mark(app, ui.parent_box(), em) }
		ui.spacer(ui.px(em * 2.4))
		glyph(app, DEVICE_ICONS[fs.device_kind(d)], em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", ui.text_shown(d.name)))
	}
	// (the tip's text made only while it shows)
	if ui.hovered_for(sig) { hover_tip(sig, fs.device_where(d), d.services[0].uri) }
	return
}

// A device's menu: each of its services opened (the URIs kept: the list may be found again while it is open).
@(private = "file")
side_device_menu_open :: proc(app: ^App, d: fs.Network_Device) {
	if app.side_device_key == 0 { app.side_device_key = ui.key_from_string(0, "classeur_side_device_menu") }
	for u in app.side_device_uris { delete(u) }
	clear(&app.side_device_uris)
	for s in d.services { append(&app.side_device_uris, strings.clone(s.uri)) }
	ui.ctx_menu_open(app.side_device_key, ui.mouse_pos())
}

@(private = "file")
side_device_menu_build :: proc(app: ^App) {
	if app.side_device_key == 0 { return }
	if ui.ctx_menu(app.side_device_key) {
		for u, i in app.side_device_uris {
			if ui.menu_item(fmt.tprintf("%s###dev_open%d", fmt.tprintf(i18n.tr("Open %s"), ui.text_shown(u)), i), icon = lucide.FOLDER_OPEN).clicked {
				if t := current_tab(app); t != nil { tab_go(app, t, u) }
			}
		}
		ui.menu_separator()
		menu_command(app, "network_find")
	}
}
