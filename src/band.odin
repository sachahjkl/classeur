package classeur

// The rectangle selection (a rubber band) is the toolkit's ui.Item_Band (gui_toolkit's src/md/features/view-modes.md):
// a press on the empty part of a list, then a drag, selects every row the rectangle touches; with Ctrl the rows are
// added to the selection there was; Ctrl and a press on a row start it from there. A folded group's title row is not
// selectable (folder_rows): the band leaves it. Classeur adds what its folder has and the toolkit's band does not know:
// one band for the window (its tab), the folder's menu on the empty part, and the selection's bytes kept row by row
// (Item_Band.changed).

import "core:fmt"
import "gt:ui"

Band :: struct {
	using band: ui.Item_Band,
	tab:        u64,   // the tab whose list it runs in
	frame:      u64,   // the last build of that list
}

// Ctrl and a press on a row: a band from there, its rows taken out of the selection when that row was in it. Called
// before the press toggles the row: the base is the selection there was.
band_begin_on_row :: proc(app: ^App, t: ^Tab, removing: bool) {
	ui.item_band_begin(&app.band.band, band_box(t), &t.folder.selection, removing)
	if app.band.active { app.band.tab, app.band.frame = t.id, u64(app.frame) }
}

// The box the items of `t` are laid out in: the columns view's, or the virtual list's.
band_box :: proc(t: ^Tab) -> ^ui.Box {
	if ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)].mode == .Columns { return ui.box_from_key(t.cols_key) }
	return ui.box_from_key(t.vl.key)
}

band_free :: proc(b: ^Band) {
	ui.item_band_destroy(&b.band)
	b^ = {}
}

// After the items of `t`'s list: a band starts, follows the pointer, or ends; a right click on the empty part opens the
// folder's menu. `pressed_row`: an item took the press; `pressed_empty`, `right_empty`: a press, a right click on an
// empty part that is not the box itself (between the grid's cards); `layout`: where the items are (its list: the tab's,
// when nil; a list's rows when it is all zero); `row_press`: a press on the empty part of a row (ui.item_band_row_press).
band_update :: proc(app: ^App, t: ^Tab, pressed_row: bool, pressed_empty := false, right_empty := false, layout := ui.Item_Band_Layout{}, row_press := ui.Item_Band_Press{}) {
	f := &t.folder
	box := band_box(t)
	if box == nil { return }
	b := &app.band
	sig := ui.signal(box)
	// (a right click on the empty part: the folder's menu, what makes and pastes)
	if (sig.right_clicked || right_empty) && !pressed_row { entry_menu_open(app, t, ui.mouse_pos(), on_entry = false) }
	// (one band for the window: while it runs in another tab, this one's list starts none and is left as it is)
	if (b.active || b.pending) && b.tab != t.id {
		if b.frame + 1 >= u64(app.frame) { return }
		b.active, b.pending = false, false   // (its list is shown no more)
	}
	layout := layout
	if layout.vl == nil { layout.vl = &t.vl }
	// (a folded group's title row is not selectable in folder_rows: the band leaves it as it is)
	bytes: Band_Bytes
	band_bytes_begin(b, &bytes, f)
	running := ui.item_band_update(&b.band, &f.selection, folder_rows(f), box, layout, pressed_row, pressed_empty, fmt.tprintf("###band%d", t.id), row_press)
	band_bytes_end(b, &bytes)
	if running || b.pending { b.tab, b.frame = t.id, u64(app.frame) }
	if !running { return }
	t.cols_cursor = f.sel   // (the rectangle moves the cursor: the columns scroll by the pointer, not to the cursor)
	app_frames(app)
}

// Escape in a band: the selection there was before it.
band_cancel :: proc(app: ^App) {
	b := &app.band
	t := find_tab(app, b.tab)
	if t == nil {
		b.active, b.pending = false, false
		return
	}
	bytes: Band_Bytes
	band_bytes_begin(b, &bytes, &t.folder)
	_ = ui.item_band_cancel(&b.band, &t.folder.selection, folder_rows(&t.folder))
	band_bytes_end(b, &bytes)
}

// The selection's bytes follow each row the band changes (Item_Band.changed; folder_set_row's rule): a rectangle drawn
// over 100 000 rows costs the rows it changes, not a count of the whole selection at each frame. They are kept only
// when they held before the band's call; else folder_selection_size counts them again once.
@(private = "file")
Band_Bytes :: struct {
	f:     ^Folder,
	known: bool,
}

// (the band's `user` points to the caller's Band_Bytes for the one call: it is told nothing outside it)
@(private = "file")
band_bytes_begin :: proc(b: ^Band, bb: ^Band_Bytes, f: ^Folder) {
	bb^ = {f = f, known = f.bytes_known && f.bytes_of == f.version}
	b.changed, b.user = band_row_changed, bb
}

@(private = "file")
band_bytes_end :: proc(b: ^Band, bb: ^Band_Bytes) {
	b.user = nil
	// (the cursor moved by the band raised the version too: the bytes still hold, the rows' changes were counted)
	if bb.known { bb.f.bytes_of = bb.f.version }
}

@(private = "file")
band_row_changed :: proc(user: rawptr, row: int, now_selected: bool) {
	bb := (^Band_Bytes)(user)
	if bb == nil || !bb.known { return }
	f := bb.f
	b := file_bytes(f.listing.entries[f.shown[row]])
	f.sel_bytes += now_selected ? b : -b
}
