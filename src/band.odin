package classeur

// The rectangle selection (a rubber band): a press on the empty part of a list, then a drag, selects every row the
// rectangle touches; with Ctrl the rows are added to the selection there was. Ctrl and a press on a row start it too
// (Explorer's): from a selected row it takes the rows it touches out of the selection, from another it adds them. The rectangle is kept in the list's
// content (it scrolls with the rows) and drawn over them in a floating box.

import "core:fmt"
import "gt:ui"

Band :: struct {
	active: bool,
	tab:    u64,
	start:  [2]f32,       // in the list's content
	base:   [dynamic]bool,   // the selection at the press (Ctrl: the rows are added to it), per entry
	removing: bool,          // the rows it touches leave the selection (Ctrl and a press on a selected row)
	keeping:  bool,          // the selection at the press stays (Ctrl); else the rows it touches alone are selected
	// the rows it could touch at the last frame (the rows outside are as the press left them): a frame visits the rows
	// of this one and of the last, not the whole folder
	lo, hi:   int,
}

// Ctrl and a press on a row: a band from there, its rows taken out of the selection when that row was in it (`base`: the
// selection before the press toggled the row).
band_begin_on_row :: proc(app: ^App, t: ^Tab, removing: bool, base: []bool) {
	lb := band_box(t)
	if lb == nil { return }
	b := &app.band
	b.active, b.tab, b.removing, b.keeping, b.lo, b.hi = true, t.id, removing, true, 0, 0
	b.start = ui.mouse_pos() - lb.rect.min + lb.view_off
	clear(&b.base)
	append(&b.base, ..base)
}

// Where the items are in the content of the box the band is drawn over:
//   .Rows: the list's rows, one a row of the virtual list (t.vl.offsets);
//   .Grid: `count` cards a row of the virtual list, each `item_w` wide, `gap` between them and before the first;
//   .Columns: `count` lines a column, columns `step` wide, each line `item_w` wide and `row_h` high.
Band_Layout :: struct {
	kind:   enum u8 { Rows, Grid, Columns },
	count:  int,
	item_w: f32,
	gap:    f32,
	step:   f32,
	row_h:  f32,
}

// The box the items of `t` are laid out in: the columns view's, or the virtual list's.
band_box :: proc(t: ^Tab) -> ^ui.Box {
	if ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)].mode == .Columns { return ui.box_from_key(t.cols_key) }
	return ui.box_from_key(t.vl.key)
}

band_free :: proc(b: ^Band) {
	delete(b.base)
	b^ = {}
}

// After the items of `t`'s list: a band starts, follows the pointer, or ends; a right click on the empty part opens the
// folder's menu. `pressed_row`: an item took the press; `pressed_empty`, `right_empty`: a press, a right click on an
// empty part that is not the box itself (between the grid's cards); `layout`: where the items are.
band_update :: proc(app: ^App, t: ^Tab, pressed_row: bool, pressed_empty := false, right_empty := false, layout := Band_Layout{}) {
	f := &t.folder
	lb := band_box(t)
	if lb == nil { return }
	b := &app.band
	sig := ui.signal(lb)
	m := ui.mouse_pos()
	content := m - lb.rect.min + lb.view_off
	// (a right click on the empty part: the folder's menu, what makes and pastes)
	if (sig.right_clicked || right_empty) && !pressed_row { entry_menu_open(app, t, m, on_entry = false) }
	if (sig.pressed || pressed_empty) && !pressed_row && !b.active {
		b.active, b.tab, b.start, b.removing, b.keeping, b.lo, b.hi = true, t.id, content, false, .Ctrl in sig.mods, 0, 0
		// (the selection at the press, kept for Escape, which gives it back)
		clear(&b.base)
		append(&b.base, ..f.selected[:])
		if !b.keeping { folder_select_none(f) }
	}

	if !b.active || b.tab != t.id { return }
	// (held: the list's press, or a row's for a band begun on it)
	if ui.active_key() == 0 {
		b.active = false
		return
	}
	y0, y1 := min(b.start.y, content.y), max(b.start.y, content.y)
	x0, x1 := min(b.start.x, content.x), max(b.start.x, content.x)
	offs := t.vl.offsets[:]
	// the rows the rectangle may touch now (by the offsets' order: a search, not a walk), and those it touched last
	lo, hi := band_rows(layout, offs, len(f.shown), x0, x1, y0, y1)
	from, to := min(lo, b.lo), max(hi, b.hi)
	if b.lo == b.hi { from, to = lo, hi }
	b.lo, b.hi = lo, hi
	grouped := f.group != .None && f.filter == ""
	for row in from ..< to {
		touched: bool
		g := layout
		switch g.kind {
		case .Rows:
			if row + 1 >= len(offs) { break }
			touched = offs[row + 1] > y0 && offs[row] < y1
		case .Grid:
			// (a card: its column's span, its row's less the gap around it)
			gr, c := row / g.count, row % g.count
			if gr + 1 >= len(offs) { break }
			ix0 := g.gap + f32(c) * (g.item_w + g.gap)
			iy0, iy1 := offs[gr] + g.gap * 0.5, offs[gr + 1] - g.gap * 0.5
			touched = ix0 + g.item_w > x0 && ix0 < x1 && iy1 > y0 && iy0 < y1
		case .Columns:
			c, r := row / g.count, row % g.count
			ix0, iy0 := f32(c) * g.step, f32(r) * g.row_h
			touched = ix0 + g.item_w > x0 && ix0 < x1 && iy0 + g.row_h > y0 && iy0 < y1
		}
		// (a row of a folded group is not shown: the rectangle does not take it)
		if touched && grouped {
			_, key := group_of(f, f.listing.entries[f.shown[row]])
			if key in f.folded { touched = false }
		}
		was := b.keeping && len(b.base) == len(f.selected) && b.base[f.shown[row]]
		on := b.removing ? was && !touched : was || touched
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

// Escape in a band: the selection there was before it.
band_cancel :: proc(app: ^App) {
	b := &app.band
	b.active = false
	t := find_tab(app, b.tab)
	if t == nil { return }
	f := &t.folder
	if len(b.base) == len(f.selected) {
		for row in 0 ..< len(f.shown) { folder_set_row(f, row, b.base[f.shown[row]]) }
	} else {
		folder_select_none(f)
	}
}

// The rows (their indices among those shown, [lo, hi)) a rectangle from y0 to y1 (and x0 to x1: the grid's and the
// columns' items) may touch, found in the list's offsets by halves.
@(private = "file")
band_rows :: proc(g: Band_Layout, offs: []f32, n: int, x0, x1, y0, y1: f32) -> (lo, hi: int) {
	// the first line whose bottom is under y0, the first whose top is past y1 (the lines of the virtual list)
	first_after :: proc(offs: []f32, lines: int, y: f32, top: bool) -> int {
		a, z := 0, lines
		for a < z {
			m := (a + z) / 2
			v := top ? offs[m] : offs[m + 1]
			if (top && v < y) || (!top && v <= y) { a = m + 1 } else { z = m }
		}
		return a
	}
	switch g.kind {
	case .Rows:
		lines := min(n, len(offs) - 1)
		if lines <= 0 { return }
		return first_after(offs, lines, y0, false), first_after(offs, lines, y1, true)
	case .Grid:
		lines := min((n + g.count - 1) / max(g.count, 1), len(offs) - 1)
		if lines <= 0 { return }
		a, z := first_after(offs, lines, y0, false), first_after(offs, lines, y1, true)
		return min(a * g.count, n), min(z * g.count, n)
	case .Columns:
		if g.step <= 0 { return 0, n }
		a := max(int(x0 / g.step), 0)
		z := int(x1 / g.step) + 1
		return min(a * g.count, n), min(z * g.count, n)
	}
	return 0, n
}
