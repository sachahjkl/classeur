package classeur

// A folder as a panel shows it: the listing read by the loader, its order (the sort), the rows shown (the filter, the
// hidden files) and the selection. No interface here: the view reads `shown` and changes the selection through these
// procedures (tests: folder_test.odin).
//
// Rows are indices into `listing.entries`. The selection is a flag per entry, so that it survives a new sort or filter;
// `cursor` is the active row (in `shown`), `anchor` the row a Shift range starts from.

import "core:hash"
import "core:strings"
import "fs"

Folder :: struct {
	listing:     fs.Listing,
	loaded:      bool,              // a listing came (it may be an error)
	sort:        fs.Sort,
	show_hidden: bool,
	filter:      string,            // owned; lower case; "" shows every row
	order:       [dynamic]u32,      // every entry, sorted
	shown:       [dynamic]u32,      // the rows: `order` without what the filter and the hidden setting leave out
	ids:         [dynamic]u64,      // a stable identity per row (the hash of its name): the virtual list's
	lowered:     [dynamic]string,   // each entry's name in lower case (made at the first filter), in `lowered_arena`
	selected:    [dynamic]bool,     // per entry
	count:       int,               // entries selected
	cursor:      int,               // the active row, -1: none
	anchor:      int,               // where a Shift range starts
}

folder_destroy :: proc(f: ^Folder) {
	fs.listing_destroy(&f.listing)
	delete(f.filter)
	delete(f.order)
	delete(f.shown)
	delete(f.ids)
	for s in f.lowered { delete(s) }
	delete(f.lowered)
	delete(f.selected)
	f^ = {}
}

// Takes a new listing (the old one is freed). The names that were selected stay selected, the cursor stays on its
// name when it is still there: a refresh keeps the person's place.
folder_set_listing :: proc(f: ^Folder, l: ^fs.Listing) {
	keep := make(map[string]struct{}, 16, context.temp_allocator)
	for sel, i in f.selected { if sel && i < len(f.listing.entries) { keep[strings.clone(f.listing.entries[i].name, context.temp_allocator)] = {} } }
	cursor_name := ""
	if e := folder_cursor_entry(f); e != nil { cursor_name = strings.clone(e.name, context.temp_allocator) }

	fs.listing_destroy(&f.listing)
	f.listing = l^
	l^ = {}
	f.loaded = true
	for s in f.lowered { delete(s) }
	clear(&f.lowered)
	n := len(f.listing.entries)
	resize(&f.order, n)
	for i in 0 ..< n { f.order[i] = u32(i) }
	resize(&f.selected, n)
	f.count = 0
	for e, i in f.listing.entries {
		f.selected[i] = e.name in keep
		if f.selected[i] { f.count += 1 }
	}
	fs.sort_order(f.listing.entries[:], f.order[:], f.sort)
	f.cursor = -1
	folder_refilter(f)
	if cursor_name != "" { folder_cursor_to_name(f, cursor_name) }
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
	f.anchor = f.cursor
}

folder_set_sort :: proc(f: ^Folder, s: fs.Sort) {
	if f.sort == s { return }
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = e.name }
	f.sort = s
	fs.sort_order(f.listing.entries[:], f.order[:], f.sort)
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
}

// Sorts by `key`; the same key again turns the order around. Dates and sizes start with the largest.
folder_sort_by :: proc(f: ^Folder, key: fs.Sort_Key) {
	s := f.sort
	if s.key == key {
		s.descending = !s.descending
	} else {
		s.key = key
		s.descending = key == .Modified || key == .Size
	}
	folder_set_sort(f, s)
}

folder_set_filter :: proc(f: ^Folder, text: string) {
	lower := strings.to_lower(text, context.temp_allocator)
	if lower == f.filter { return }
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	delete(f.filter)
	f.filter = strings.clone(lower)
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

folder_set_show_hidden :: proc(f: ^Folder, show: bool) {
	if f.show_hidden == show { return }
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	f.show_hidden = show
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// The rows again from `order`: every word of the filter must be in the name. A row that leaves the view leaves the
// selection too (what is selected is what the person sees).
folder_refilter :: proc(f: ^Folder) {
	entries := f.listing.entries[:]
	if f.filter != "" && len(f.lowered) != len(entries) {
		for s in f.lowered { delete(s) }
		clear(&f.lowered)
		for e in entries { append(&f.lowered, strings.to_lower(e.name)) }
	}
	words := strings.fields(f.filter, context.temp_allocator)
	clear(&f.shown)
	clear(&f.ids)
	outer: for i in f.order {
		e := entries[i]
		if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { continue }
		for w in words { if !strings.contains(f.lowered[i], w) { continue outer } }
		append(&f.shown, i)
		append(&f.ids, hash.fnv64a(transmute([]u8)e.name))
	}
	visible := make([]bool, len(entries), context.temp_allocator)
	for i in f.shown { visible[i] = true }
	f.count = 0
	for &sel, i in f.selected {
		if sel && !visible[i] { sel = false }
		if sel { f.count += 1 }
	}
	f.cursor = min(f.cursor, len(f.shown) - 1)
	f.anchor = min(f.anchor, len(f.shown) - 1)
}

folder_cursor_entry :: proc(f: ^Folder) -> ^fs.Entry {
	if f.cursor < 0 || f.cursor >= len(f.shown) { return nil }
	return &f.listing.entries[f.shown[f.cursor]]
}

folder_row_entry :: proc(f: ^Folder, row: int) -> ^fs.Entry {
	if row < 0 || row >= len(f.shown) { return nil }
	return &f.listing.entries[f.shown[row]]
}

folder_cursor_to_name :: proc(f: ^Folder, name: string) -> bool {
	for i, row in f.shown {
		if f.listing.entries[i].name == name {
			f.cursor = row
			f.anchor = row
			return true
		}
	}
	return false
}

folder_row_selected :: proc(f: ^Folder, row: int) -> bool {
	return row >= 0 && row < len(f.shown) && f.selected[f.shown[row]]
}

folder_select_none :: proc(f: ^Folder) {
	for &s in f.selected { s = false }
	f.count = 0
}

folder_select_all :: proc(f: ^Folder) {
	folder_select_none(f)
	for i in f.shown { f.selected[i] = true }
	f.count = len(f.shown)
}

folder_set_row :: proc(f: ^Folder, row: int, on: bool) {
	if row < 0 || row >= len(f.shown) { return }
	i := f.shown[row]
	if f.selected[i] == on { return }
	f.selected[i] = on
	f.count += on ? 1 : -1
}

// What a click or a move does to the selection: the row alone; with Ctrl the row toggled; with Shift the range from the
// anchor (the anchor stays). `toggle` and `extend` say which.
folder_pick :: proc(f: ^Folder, row: int, extend := false, toggle := false) {
	if row < 0 || row >= len(f.shown) { return }
	switch {
	case extend:
		if f.anchor < 0 { f.anchor = row }
		if !toggle { folder_select_none(f) }
		lo, hi := min(f.anchor, row), max(f.anchor, row)
		for r in lo ..= hi { folder_set_row(f, r, true) }
	case toggle:
		folder_set_row(f, row, !folder_row_selected(f, row))
		f.anchor = row
	case:
		folder_select_none(f)
		folder_set_row(f, row, true)
		f.anchor = row
	}
	f.cursor = row
}

folder_invert_selection :: proc(f: ^Folder) {
	for row in 0 ..< len(f.shown) { folder_set_row(f, row, !folder_row_selected(f, row)) }
}

// The entries an action applies to: the selection, else the entry at the cursor.
folder_targets :: proc(f: ^Folder, allocator := context.temp_allocator) -> []^fs.Entry {
	out := make([dynamic]^fs.Entry, allocator)
	for i in f.shown { if f.selected[i] { append(&out, &f.listing.entries[i]) } }
	if len(out) == 0 {
		if e := folder_cursor_entry(f); e != nil { append(&out, e) }
	}
	return out[:]
}

// The total size of the selected files (folders count none), and how many there are.
folder_selection_size :: proc(f: ^Folder) -> (bytes: i64, files: int) {
	for i in f.shown {
		if !f.selected[i] { continue }
		e := f.listing.entries[i]
		if e.size > 0 { bytes += e.size }
		files += 1
	}
	return
}
