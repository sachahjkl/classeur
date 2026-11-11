package classeur

// The grid view, File Pilot's: cards in rows, each with its thumbnail (a picture's, made on the workers: thumbs.odin)
// or its icon large, its name and its size. The rows are a virtual list: only those in view are built. The keys move
// the cursor card by card (view.odin's list_keys); a row of the list is a row of cards.

import "core:fmt"
import "core:slice"
import "gt:draw"
import "gt:render"
import "gt:ui"
import "fs"

// A card's height and its picture's, of its width; the room between cards, in ems; a line's width in the Columns view.
CARD_HEIGHT  :: 1.12
CARD_PICTURE :: 0.72
CARD_GAP_EM  :: 0.6
COLUMN_EM    :: 20

grid_list :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	if empty_state(app, t, em) { return }
	z := ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)]
	lines := z.mode == .Columns
	// an item's size: a line of a column, or a card of the zoom's size, which goes from step to step smoothly (File
	// Pilot's zoom: discrete steps, the cards growing between them)
	card_em := ui.anim(ui.key_from_string(0, fmt.tprintf("classeur_card%d", t.id)), z.card_em > 0 ? z.card_em : ZOOMS[ZOOM_GRID - 1].card_em, 22)
	item_w := lines ? em * COLUMN_EM : em * card_em
	item_h := lines ? em * ROW_EM : em * card_em * CARD_HEIGHT
	gap := lines ? em * ROW_INSET_EM : em * CARD_GAP_EM
	// as many items in a row as the width laid out last time holds (the lines share it all)
	width: f32 = item_w * 4
	if b := ui.prev_box("###grid"); b != nil && b.size.x > 0 { width = b.size.x }
	room := width - em * 1.2
	cols := max(1, int(room / (item_w + gap)))
	if lines { item_w = room / f32(cols) - gap }
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
	look := row_look(app, focused, em)
	pressed_item, pressed_empty, right_empty := false, false, false
	for r in rows.first ..< rows.last {
		ui.next({height = ui.px(item_h + (lines ? 0 : gap)), radius = 0, cross = .Center})
		row := ui.list_row(&t.vl, r, "", selectable = false)
		if row.pressed { pressed_empty = true }
		if row.right_clicked { right_empty = true }
		opened := false
		if ui.parent(row.box) {
			ui.spacer(ui.px(gap))
			for c in 0 ..< cols {
				at := r * cols + c
				if at >= n { break }
				open, pressed := item(app, t, at, look, lines, item_w, item_h, em)
				if pressed { pressed_item = true }
				if open { opened = true; break }
				ui.spacer(ui.px(gap))
			}
		}
		if opened { return }
	}
	// (a press on the empty part, between the cards or under them: the rectangle selection, as in the list)
	band_update(app, t, pressed_item, pressed_empty, right_empty, {kind = .Grid, count = cols, item_w = item_w, gap = gap})
}

// One item: a line (the icon, the name) or a card (the thumbnail or the icon large, the name, the size). True: it
// opened what it shows (the list is gone).
@(private = "file")
item :: proc(app: ^App, t: ^Tab, row: int, look: ^Row_Look, line: bool, width, height, em: f32) -> (opened, pressed: bool) {
	f := &t.folder
	e := &f.listing.entries[f.shown[row]]
	selected := f.selected[f.shown[row]]
	cursor := row == f.cursor && (!selected || f.count > 1)
	ui.next({width = ui.px(width), height = ui.px(height), axis = line ? .X : .Y, radius = 0, cross = line ? .Center : nil})
	// (the wheel's click on a folder opens it in a tab; on a file it scrolls, the toolkit's autoscroll)
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within}
	if e.kind == .Directory { flags += {.Middle_Click} }
	b := ui.build_box(flags, fmt.tprintf("###item%d", row))
	// (the pill and the ring of the rows; a card has no line under it)
	card_look := look
	if !line {
		l := ui.frame_new(Row_Look)
		l^ = look^
		l.inset, l.line = 0, {}
		l.card, l.card_edge = draw.hex(surfaces(app).head), draw.hex(surfaces(app).edge)
		card_look = l
	}
	row_paint(b, card_look, selected, cursor)
	sig := ui.signal(b)
	if selected && look.focused { ui.push_tags("selected") }
	if ui.parent(b) {
		if line {
			ui.spacer(ui.px(em * 0.4))
			tree_lead(app, t, e, em)
			entry_glyph(app, t.path, e^, em * 1.9)
			ui.spacer(ui.px(em * 0.5))
			entry_name(app, t, e, selected, em)
		} else {
			card_body(app, t, e, selected, width, height, em)
		}
	}
	if selected && look.focused { ui.pop_tags() }
	pressed = sig.pressed || sig.right_clicked
	if sig.pressed && selected && sig.mods == {} && f.count > 1 {
		f.cursor = row   // (a press on the selection may drag it: the item alone is picked at the click)
	} else if sig.pressed && .Ctrl in sig.mods && .Shift not_in sig.mods {
		// (Ctrl: the card toggled, and a drag from it does the same to the cards it passes, as the list's rows)
		base := slice.clone(f.selected[:], context.temp_allocator)
		folder_pick(f, row, toggle = true)
		band_begin_on_row(app, t, selected, base)
	} else if sig.pressed {
		folder_pick(f, row, extend = .Shift in sig.mods, toggle = .Ctrl in sig.mods)
	}
	if sig.clicked && selected && sig.mods == {} && f.count > 1 && !app.drag_started { folder_pick(f, row) }
	drag_maybe(app, t, sig)
	if e.kind == .Directory {
		dir := fs.join(t.path, e.name, context.temp_allocator)
		drop_zone(app, b.rect, dir)
		if app.drop_hover == dir { drop_mark(b) }
	}
	if !app.drag_started && !app.band.active { entry_tip(app, t, e, sig) }
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
		return true, pressed
	}
	return
}

@(private = "file")
card_body :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, selected: bool, width, height, em: f32) {
	pic := width * CARD_PICTURE
	ui.spacer(ui.px(em * 0.5))
	ui.next({width = ui.fill(), height = ui.px(pic)})
	if ui.row(.Center) {
		ui.spacer(ui.px(em * 0.5))
		path := fs.join(t.path, e.name, context.temp_allocator)
		if e.kind == .File && thumb_mime(e.name) != "" {
			if th, ready := thumb_get(app, path); ready {
				d := ui.frame_new(Picture_Draw)
				d^ = {th.tex, {f32(th.size.x), f32(th.size.y)}, corner_k()}
				ui.next({width = ui.fill(), height = ui.pct(1)})
				ui.custom("###thumb", picture_draw, d)
			} else {
				big_icon(app, t.path, e^, pic)
			}
		} else {
			big_icon(app, t.path, e^, pic)
		}
		ui.spacer(ui.px(em * 0.5))
	}
	ui.spacer(ui.fill())
	ui.next({width = ui.fill(), height = ui.px(em * 1.5), text_align = .Center})
	ui.label(fmt.tprintf("%s###n", shown_text(fs.base(shown_name(app, e^)))))
	size := ""
	if e.size >= 0 { size = size_text(e.size) } else if m, ok := measure_of(app, t, e^); ok { size = size_text(m.bytes) }
	if !selected { ui.push_tags("weak") }
	ui.next({width = ui.fill(), height = ui.px(em * 1.3), text_align = .Center, font_size = em * 0.88})
	ui.label(fmt.tprintf("%s###s", size))
	if !selected { ui.pop_tags() }
	ui.spacer(ui.px(em * 0.4))
}

// The icon of an entry, `size` large.
@(private = "file")
big_icon :: proc(app: ^App, dir: string, e: fs.Entry, size: f32) {
	ui.spacer(ui.fill())
	entry_glyph(app, dir, e, size)
	ui.spacer(ui.fill())
}

@(private = "file")
Picture_Draw :: struct {
	tex:  render.Texture,
	size: [2]f32,
	round: f32,   // corner_k(): the settings' rounding
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
	draw.image(dc, d.tex, {at, at + sz}, radius = 2 * d.round)
}

// The columns view (File Pilot's, Explorer's list): the names filled column by column, as many in a column as the height
// holds, the columns side by side scrolled sideways (the wheel too). Only the columns in view are built: a folder of
// 100 000 names costs what is shown.
columns_list :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	if empty_state(app, t, em) { return }
	row_h := ui.dense(em * ROW_EM)
	col_w := em * COLUMN_EM
	size := [2]f32{col_w * 3, row_h * 12}
	if b := ui.prev_box("###cols"); b != nil && b.size.y > 0 { size = b.size }
	per := max(1, int((size.y - em * 0.4) / row_h))
	t.grid_cols = per
	n := len(f.shown)
	ncols := (n + per - 1) / per
	ui.next({width = ui.fill(), height = ui.fill(), axis = .X})
	b := ui.build_box({.Clip, .View_Scroll_X, .Allow_Overflow_X, .Scroll_Self, .Clickable, .Focusable}, "###cols")
	t.cols_key = b.key
	sig := ui.signal(b)
	if t.focus_due == .List {
		ui.set_focus(b.key)
		t.focus_due = .None
	}
	// the wheel, either way, scrolls sideways; the cursor moved by the keys is brought into view
	limit := max(0, f32(ncols) * col_w - size.x)
	if d := sig.scrolled.x + sig.scrolled.y; d != 0 { b.view_target.x = clamp(b.view_target.x + d, 0, limit) }
	if f.cursor != t.cols_cursor && f.cursor >= 0 {
		c := f32(f.cursor / per)
		ui.view_reveal(b, c * col_w, (c + 1) * col_w, .X)
		b.view_target.x = clamp(b.view_target.x, 0, limit)
	}
	t.cols_cursor = f.cursor
	off := b.view_off.x
	first := clamp(int(off / col_w) - 1, 0, ncols)
	last := clamp(int((off + size.x) / col_w) + 2, first, ncols)
	look := row_look(app, focused, em)
	pressed_item := false
	if ui.parent(b) {
		ui.spacer(ui.px(f32(first) * col_w))
		for c in first ..< last {
			ui.next({width = ui.px(col_w), height = ui.fill(), axis = .Y})
			if ui.column(.Start, {}, fmt.tprintf("###col%d", c)) {
				for r in 0 ..< per {
					at := c * per + r
					if at >= n { break }
					open, pressed := item(app, t, at, look, true, col_w - em * ROW_INSET_EM, row_h, em)
					if pressed { pressed_item = true }
					if open { return }
				}
			}
		}
		ui.spacer(ui.px(f32(ncols - last) * col_w))
	}
	// (a press on the empty part: the rectangle selection; a right click: the folder's menu, by band_update)
	band_update(app, t, pressed_item, layout = {kind = .Columns, count = per, item_w = col_w - em * ROW_INSET_EM, step = col_w, row_h = row_h})
}
