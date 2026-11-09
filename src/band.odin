package classeur

// The rectangle selection (a rubber band): a press on the empty part of a list, then a drag, selects every row the
// rectangle touches; with Ctrl the rows are added to the selection there was. The rectangle is kept in the list's
// content (it scrolls with the rows) and drawn over them in a floating box.

import "core:fmt"
import "gt:ui"

Band :: struct {
	active: bool,
	tab:    u64,
	start:  [2]f32,       // in the list's content
	base:   [dynamic]bool,   // the selection at the press (Ctrl: the rows are added to it), per entry
}

band_free :: proc(b: ^Band) {
	delete(b.base)
	b^ = {}
}

// After the rows of `t`'s list: a band starts, follows the pointer, or ends. `pressed_row`: a row took the press.
band_update :: proc(app: ^App, t: ^Tab, pressed_row: bool) {
	f := &t.folder
	lb := ui.box_from_key(t.vl.key)
	if lb == nil { return }
	b := &app.band
	sig := ui.signal(lb)
	m := ui.mouse_pos()
	content := m - lb.rect.min + lb.view_off
	if sig.pressed && !pressed_row && !b.active {
		b.active, b.tab, b.start = true, t.id, content
		clear(&b.base)
		if .Ctrl in sig.mods {
			append(&b.base, ..f.selected[:])
		} else {
			folder_select_none(f)
		}
	}
	if !b.active || b.tab != t.id { return }
	if !sig.dragging {
		b.active = false
		return
	}
	y0, y1 := min(b.start.y, content.y), max(b.start.y, content.y)
	offs := t.vl.offsets[:]
	for row in 0 ..< len(f.shown) {
		if row + 1 >= len(offs) { break }
		touched := offs[row + 1] > y0 && offs[row] < y1
		on := touched || (len(b.base) == len(f.selected) && b.base[f.shown[row]])
		folder_set_row(f, row, on)
		if touched { f.cursor = row }
	}
	// the rectangle, on screen
	a := b.start - lb.view_off + lb.rect.min
	r := ui.Rect{{min(a.x, m.x), min(a.y, m.y)}, {max(a.x, m.x), max(a.y, m.y)}}
	r.min = {max(r.min.x, lb.rect.min.x), max(r.min.y, lb.rect.min.y)}
	r.max = {min(r.max.x, lb.rect.max.x), min(r.max.y, lb.rect.max.y)}
	parent := ui.parent_box()
	accent := ui.color("accent")
	ui.next({width = ui.px(max(r.max.x - r.min.x, 1)), height = ui.px(max(r.max.y - r.min.y, 1)),
		bg = accent * {1, 1, 1, 0.18}, border = accent, radius = 0})
	box := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background, .Draw_Border}, fmt.tprintf("###band%d", t.id))
	box.fixed_pos = r.min - parent.rect.min
	app_frames(app)
}
