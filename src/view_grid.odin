package classeur

// The grid view, File Pilot's: cards in rows, each with its thumbnail (a picture's, made on the workers: thumbs.odin)
// or its icon large, its name and its size. The rows are a virtual list: only those in view are built. The keys move
// the cursor card by card (view.odin's list_keys); a row of the list is a row of cards.

import "core:fmt"
import "gt:draw"
import "gt:render"
import "gt:ui"
import "fs"

// A card's width and height, the picture's height, the room between cards, in ems.
CARD_EM       :: 11.5
CARD_HEIGHT_EM :: 12.5
CARD_THUMB_EM :: 8.4
CARD_GAP_EM   :: 0.6

grid_list :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	if empty_state(app, t, em) { return }
	// as many cards in a row as the width laid out last time holds
	width: f32 = em * CARD_EM * 4
	if b := ui.prev_box("###grid"); b != nil && b.size.x > 0 { width = b.size.x }
	card_w := em * CARD_EM
	cols := max(1, int((width - em * (1 + CARD_GAP_EM)) / card_w))
	t.grid_cols = cols
	n := len(f.shown)
	rows_n := (n + cols - 1) / cols
	ids := make([]u64, rows_n, context.temp_allocator)
	for r in 0 ..< rows_n { ids[r] = f.ids[r * cols] ~ u64(cols) }
	t.vl.sel = f.cursor >= 0 ? f.cursor / cols : -1
	rows, ok := ui.vlist("###grid", &t.vl, ids)
	if !ok { return }
	if t.focus_due == .List && t.vl.key != 0 {
		ui.set_focus(t.vl.key)
		t.focus_due = .None
	}
	selection := selection_color(app)
	for r in rows.first ..< rows.last {
		ui.next({height = ui.px(em * CARD_HEIGHT_EM), radius = 0})
		row := ui.list_row(&t.vl, r, "", selectable = false)
		opened := false
		if ui.parent(row.box) {
			ui.spacer(ui.px(em * CARD_GAP_EM))
			for c in 0 ..< cols {
				at := r * cols + c
				if at >= n { break }
				if card(app, t, at, focused, selection, card_w - em * CARD_GAP_EM, em) { opened = true; break }
				ui.spacer(ui.px(em * CARD_GAP_EM))
			}
		}
		if opened { return }
	}
}

// One card. True: it opened what it shows (the list is gone).
@(private = "file")
card :: proc(app: ^App, t: ^Tab, row: int, focused: bool, selection: ui.Color, width, em: f32) -> bool {
	f := &t.folder
	e := &f.listing.entries[f.shown[row]]
	selected := f.selected[f.shown[row]]
	cursor := row == f.cursor
	bg: Maybe(ui.Color)
	if selected { bg = focused ? selection : selection * {1, 1, 1, 0.55} }
	ui.next({width = ui.px(width), height = ui.px(em * (CARD_HEIGHT_EM - CARD_GAP_EM)), axis = .Y, radius = em * 0.15,
		bg = bg, border = cursor && focused ? ui.color("accent") : nil})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	if selected { flags += {.Draw_Background} }
	if cursor && focused { flags += {.Draw_Border} }
	b := ui.build_box(flags, fmt.tprintf("###card%d", row))
	sig := ui.signal(b)
	if ui.parent(b) {
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.fill(), height = ui.px(em * CARD_THUMB_EM)})
		if ui.row(.Center) {
			path := fs.join(t.path, e.name, context.temp_allocator)
			if e.kind == .File && thumb_mime(e.name) != "" {
				if th, ready := thumb_get(app, path); ready {
					d := ui.frame_new(Picture_Draw)
					d^ = {th.tex, {f32(th.size.x), f32(th.size.y)}}
					ui.next({width = ui.fill(), height = ui.pct(1)})
					ui.custom("###thumb", picture_draw, d)
				} else {
					big_icon(app, e^, em)
				}
			} else {
				big_icon(app, e^, em)
			}
		}
		ui.spacer(ui.px(em * 0.3))
		ui.next({width = ui.fill(), height = ui.px(em * 1.5), text_align = .Center})
		ui.label(fmt.tprintf("%s###n", shown_text(e.name)))
		size := ""
		if e.size >= 0 { size = size_text(e.size) } else if m, ok := measure_of(app, t, e^); ok { size = size_text(m.bytes) }
		if !selected { ui.push_tags("weak") }
		ui.next({width = ui.fill(), height = ui.px(em * 1.3), text_align = .Center, font_size = em * 0.88})
		ui.label(fmt.tprintf("%s###s", size))
		if !selected { ui.pop_tags() }
	}
	if sig.pressed { folder_pick(f, row, extend = .Shift in sig.mods, toggle = .Ctrl in sig.mods) }
	if sig.right_clicked {
		if !folder_row_selected(f, row) { folder_pick(f, row) }
		f.cursor = row
		entry_menu_open(app, t, ui.mouse_pos())
	}
	if sig.middle_clicked && e.kind == .Directory {
		tab_open(app, current_panel(app), fs.join(t.path, e.name, context.temp_allocator), current_panel(app).active + 1)
	}
	if sig.double_clicked {
		folder_pick(f, row)
		act_open(app)
		return true
	}
	return false
}

// The icon of an entry, as large as the card's picture.
@(private = "file")
big_icon :: proc(app: ^App, e: fs.Entry, em: f32) {
	ui.spacer(ui.fill())
	if ui.style({font_size = em * 3.6}) { entry_glyph(app, e, em * CARD_THUMB_EM) }
	ui.spacer(ui.fill())
}

@(private = "file")
Picture_Draw :: struct {
	tex:  render.Texture,
	size: [2]f32,
}

// The picture as large as it fits, centred, never larger than it is.
@(private = "file")
picture_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Picture_Draw)(user)
	r := b.rect
	room := r.max - r.min
	if d.size.x <= 0 || d.size.y <= 0 || room.x <= 0 || room.y <= 0 { return }
	scale := min(room.x / d.size.x, room.y / d.size.y, 1)
	sz := d.size * scale
	at := r.min + (room - sz) * 0.5
	draw.image(dc, d.tex, {at, at + sz}, radius = 2)
}
