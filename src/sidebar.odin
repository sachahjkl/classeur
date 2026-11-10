package classeur

// The sidebar, File Pilot's: a filter at the top, then sections that open and close: the recent folders, the
// bookmarks, the storage (each volume with a bar of how full it is), the places. A click goes there in the tab that has
// the keyboard; a middle click opens a new tab.

import "core:fmt"
import "core:strings"
import config "gt:config"
import "gt:draw"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

Side_Section :: enum u8 { Recents, Bookmarks, Storage, Places }

@(private = "file", rodata)
SECTION_TITLES := [Side_Section]string{.Recents = "Recents", .Bookmarks = "Bookmarks", .Storage = "Storage", .Places = "Places"}
@(private = "file", rodata)
SECTION_ICONS := [Side_Section]string{.Recents = lucide.HISTORY, .Bookmarks = lucide.BOOKMARK, .Storage = lucide.HARD_DRIVE, .Places = lucide.FOLDER}


// How full a volume is: its bar under its name.
VOLUME_BAR      :: 0x2f7fd0ff
VOLUME_BAR_FULL :: 0xe9605fff
VOLUME_FULL_AT  :: 0.9

sidebar_build :: proc(app: ^App, em: f32) {
	t := current_tab(app)
	here := t != nil ? t.path : ""
	ui.next_merge({axis = .Y, bg = draw.hex(surfaces(app).side)})
	box := ui.build_box({.Clip, .Draw_Background}, "###sidebar")
	if ui.parent(box) {
		side_filter(app, em)
		query := strings.to_lower(ui.field_string(&app.side_filter), context.temp_allocator)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.scroll_y("###side_scroll") {
			ui.spacer(ui.px(em * 0.3))
			// (the sections in the person's order: a heading dragged, or its menu's Move up and Move down)
			for sec in app.side_order {
				switch sec {
				case .Recents:
				if section(app, .Recents, em) {
						for p, i in app.recents {
							if !keeps(query, fs.base(p)) { continue }
							side_folder(app, t, fmt.tprintf("###recent%d", i), p, cut_text(home_path(app, p), 40), here, em)
						}
					}
				case .Bookmarks:
				if section(app, .Bookmarks, em) {
						for p, i in app.bookmarks {
							if !keeps(query, fs.base(p)) { continue }
							side_folder(app, t, fmt.tprintf("###bookmark%d", i), p, fs.base(p), here, em)
						}
						if len(app.bookmarks) == 0 && query == "" {
							if ui.tags("weak") {
								ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8)), font_size = em * 0.85})
								if ui.row(.Center) {
									ui.spacer(ui.px(em * 2.6))
									ui.label(fmt.tprintf("%s: bookmark a folder###bm_hint", shortcut_text(command_find("bookmark").keys[0])))
								}
							}
						}
					}
				case .Storage:
				if section(app, .Storage, em) {
						for v, i in app.volumes {
							if !keeps(query, v.label) { continue }
							sp := i < len(app.volume_space) ? app.volume_space[i] : fs.Space{}
							if side_volume(app, i, v, sp, v.path == here, em) && t != nil { tab_go(app, t, v.path) }
						}
					}
				case .Places:
				if section(app, .Places, em) {
						for p, i in app.places {
							if !keeps(query, p.name) { continue }
							sig := side_row(app, fmt.tprintf("###place%d", i), p.path, p.name, p.path == here, em)
							go_from(app, t, sig, p.path)
						}
					}
				}
			}
			app.side_end_y = ui.parent_box().rect.min.y - ui.parent_box().view_off.y + ui.parent_box().view_bounds.y
			ui.spacer(ui.px(em * 0.6))
		}
		// (out of the scrolled list: the line and the tint are placed on the screen)
		side_drag_end(app, em)
	}
}

@(private = "file")
keeps :: proc(query, name: string) -> bool {
	return query == "" || strings.contains(strings.to_lower(name, context.temp_allocator), query)
}

@(private = "file")
go_from :: proc(app: ^App, t: ^Tab, sig: ui.Signal, path: string) {
	if sig.clicked && t != nil { tab_go(app, t, path) }
	if sig.middle_clicked { tab_open(app, current_panel(app), path, current_panel(app).active + 1) }
}

@(private = "file")
side_filter :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.4))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###side_filter") {
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.6) }
		key := ui.key_from_string(ui.parent_box().key, "###sfilter")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###sfilter", &app.side_filter, "Filter...") }
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
		ui.label(fmt.tprintf("%s###t", SECTION_TITLES[s]))
		if ui.tags("weak") { glyph(app, open ? lucide.CHEVRON_DOWN : lucide.CHEVRON_RIGHT, em * 1.6) }
		ui.spacer(ui.px(em * 0.5))
	}
	app.side_heads[s] = sig.box.rect
	// dragged past a few pixels: the section moves where it is let go (side_drag_end); a right click: its menu
	if sig.dragging && abs(sig.drag_delta.y) > em * 0.5 { app.side_drag, app.side_dragging = s, true }
	if app.side_dragging && app.side_drag == s { app.side_held = sig.dragging }
	if sig.clicked && !(app.side_dragging && app.side_drag == s) { app.side_open[s] = !open }
	if sig.right_clicked { side_menu_open(app, s) }
	hover_tip(sig, "Drag it, or right-click it, to move the section")
	return app.side_open[s]
}

// The order of the sections as the preference says it ("recents,bookmarks,storage,places"); a name it does not know,
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
	prefs_save(app)
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
	app.side_menu_of = s
	ui.ctx_menu_open(app.side_menu_key, ui.mouse_pos())
}

side_menu_build :: proc(app: ^App, em: f32) {
	if app.side_menu_key == 0 { return }
	if ui.ctx_menu(app.side_menu_key) {
		s := app.side_menu_of
		at := 0
		for x, i in app.side_order { if x == s { at = i } }
		last := len(Side_Section) - 1
		if ui.menu_item("Move up", icon = lucide.ARROW_UP, enabled = at > 0).clicked { side_move(app, s, at - 1) }
		if ui.menu_item("Move down", icon = lucide.ARROW_DOWN, enabled = at < last).clicked { side_move(app, s, at + 1) }
		ui.menu_separator()
		if ui.menu_item("Move to the top", enabled = at > 0).clicked { side_move(app, s, 0) }
		if ui.menu_item("Move to the bottom", enabled = at < last).clicked { side_move(app, s, last) }
		ui.menu_separator()
		if ui.menu_item(app.side_open[s] ? "Close the section" : "Open the section", icon = app.side_open[s] ? lucide.CHEVRON_RIGHT : lucide.CHEVRON_DOWN).clicked { app.side_open[s] = !app.side_open[s] }
	}
}

@(private = "file")
side_folder :: proc(app: ^App, t: ^Tab, id, path, name: string, here: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	on := path == here
	if on { flags += {.Draw_Background} }
	ui.next_merge({bg = on ? ui.color("border") : nil})
	sig: ui.Signal
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", shown_text(name)))
		drop_zone(app, ui.parent_box().rect, path)
		if app.drop_hover == path { drop_mark(ui.parent_box()) }
	}
	go_from(app, t, sig, path)
	hover_tip(sig, home_path(app, path))
}

@(private = "file")
side_row :: proc(app: ^App, id, path: string, name: string, here: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0, bg = here ? ui.color("border") : nil})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	if here { flags += {.Draw_Background} }
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", shown_text(name)))
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
	draw.rect(dc, r, d.track)
	draw.rect(dc, {r.min, {r.min.x + (r.max.x - r.min.x) * d.used, r.max.y}}, d.bar)
}

// A volume: its icon, its name, and under the name a bar of how full it is.
@(private = "file")
side_volume :: proc(app: ^App, i: int, v: fs.Volume, sp: fs.Space, here: bool, em: f32) -> bool {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.5)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within}
	if here { flags += {.Draw_Background} }
	ui.next_merge({bg = here ? ui.color("border") : nil})
	sig: ui.Signal
	if ui.row(.Center, flags, fmt.tprintf("###vol%d", i)) {
		sig = ui.signal(ui.parent_box())
		drop_zone(app, ui.parent_box().rect, v.path)
		if app.drop_hover == v.path { drop_mark(ui.parent_box()) }
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, v.path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.45)})
			ui.label(fmt.tprintf("%s###n", shown_text(v.label)))
			ui.spacer(ui.px(em * 0.1))
			if sp.total > 0 {
				used := 1 - f32(f64(sp.free) / f64(sp.total))
				d := ui.frame_new(Bar_Draw)
				d^ = {used, draw.hex(used > VOLUME_FULL_AT ? VOLUME_BAR_FULL : VOLUME_BAR), ui.color("border")}
				ui.next({width = ui.fill(), height = ui.px(max(3, em * 0.25))})
				ui.custom("###bar", bar_draw, d)
			}
			ui.spacer(ui.fill())
		}
		ui.spacer(ui.px(em * 0.8))
	}
	hover_tip(sig, v.path, sp.total > 0 ? fmt.tprintf("%s free of %s", size_text(sp.free), size_text(sp.total)) : "")
	return sig.clicked
}
