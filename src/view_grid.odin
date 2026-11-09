package classeur

// The grid view, File Pilot's: cards in rows, each with its thumbnail (a picture's, made on the workers: thumbs.odin)
// or its icon large, its name and its size. The rows are a virtual list: only those in view are built. The keys move
// the cursor card by card (view.odin's list_keys); a row of the list is a row of cards.

import "core:fmt"
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
	// an item's size: a line of a column, or a card of the zoom's size
	item_w := lines ? em * COLUMN_EM : em * z.card_em
	item_h := lines ? em * ROW_EM : em * z.card_em * CARD_HEIGHT
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
	for r in rows.first ..< rows.last {
		ui.next({height = ui.px(item_h + (lines ? 0 : gap)), radius = 0, cross = .Center})
		row := ui.list_row(&t.vl, r, "", selectable = false)
		opened := false
		if ui.parent(row.box) {
			ui.spacer(ui.px(gap))
			for c in 0 ..< cols {
				at := r * cols + c
				if at >= n { break }
				if item(app, t, at, look, lines, item_w, item_h, em) { opened = true; break }
				ui.spacer(ui.px(gap))
			}
		}
		if opened { return }
	}
}

// One item: a line (the icon, the name) or a card (the thumbnail or the icon large, the name, the size). True: it
// opened what it shows (the list is gone).
@(private = "file")
item :: proc(app: ^App, t: ^Tab, row: int, look: ^Row_Look, line: bool, width, height, em: f32) -> bool {
	f := &t.folder
	e := &f.listing.entries[f.shown[row]]
	selected := f.selected[f.shown[row]]
	cursor := row == f.cursor && (!selected || f.count > 1)
	ui.next({width = ui.px(width), height = ui.px(height), axis = line ? .X : .Y, radius = 0, cross = line ? .Center : nil})
	b := ui.build_box({.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}, fmt.tprintf("###item%d", row))
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
			entry_glyph(app, t.path, e^, em * 1.9)
			ui.spacer(ui.px(em * 0.5))
			entry_name(app, t, e, selected, em)
		} else {
			card_body(app, t, e, selected, width, height, em)
		}
	}
	if selected && look.focused { ui.pop_tags() }
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
				d^ = {th.tex, {f32(th.size.x), f32(th.size.y)}}
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
