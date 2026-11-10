package classeur

// A folder as a panel shows it: the listing read by the loader, its order (the sort), the rows shown (the filter, the
// hidden files) and the selection. No interface here: the view reads `shown` and changes the selection through these
// procedures (tests: folder_test.odin).
//
// Rows are indices into `listing.entries`. The selection is a flag per entry, so that it survives a new sort or filter;
// `cursor` is the active row (in `shown`), `anchor` the row a Shift range starts from.

import "core:hash"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import "gt:ui"
import "fs"

Folder :: struct {
	listing:     fs.Listing,
	loaded:      bool,              // a listing came (it may be an error)
	flat:        bool,              // the listing is a flat read: its names are paths from the folder
	tree:        bool,              // the tree view: its names are paths too, the rows in the tree's order
	sort:        fs.Sort,
	show_hidden: bool,
	filter:      string,            // owned; lower case; "" shows every row
	kinds:       Kind_Filter,       // files and folders, or one of them (the types' popup)
	types_off:   map[string]bool,   // the extensions left out, lower case, keys owned ("" the files with none)
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
	for k in f.types_off { delete(k) }
	delete(f.types_off)
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
	if f.tree { tree_order(f) }
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
	if f.tree { tree_order(f) }
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
	// typing: the best match has the cursor (Enter opens it); the filter cleared: the cursor goes back to its row
	if f.filter != "" {
		f.cursor = len(f.shown) > 0 ? 0 : -1
		f.anchor = f.cursor
	} else if name != "" {
		folder_cursor_to_name(f, name)
	}
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// Which entries the types' popup keeps (File Pilot's): both, the files alone, the folders alone.
Kind_Filter :: enum u8 { All, Files, Folders }

// The type of a file as the popup counts it: its extension in lower case ("" none).
type_key :: proc(e: fs.Entry) -> string {
	return strings.to_lower(fs.extension(fs.base(e.name)), context.temp_allocator)
}

folder_set_kinds :: proc(f: ^Folder, k: Kind_Filter) {
	if f.kinds == k { return }
	f.kinds = k
	folder_refilter(f)
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// A type in or out of the rows.
folder_toggle_type :: proc(f: ^Folder, ext: string) {
	if ext in f.types_off {
		key, _ := delete_key(&f.types_off, ext)
		delete(key)
	} else {
		f.types_off[strings.clone(ext)] = true
	}
	folder_refilter(f)
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// Every type in or out at once (out: each type of the listing).
folder_all_types :: proc(f: ^Folder, on: bool) {
	for k in f.types_off { delete(k) }
	clear(&f.types_off)
	if !on {
		for e in f.listing.entries {
			if e.kind == .Directory { continue }
			k := type_key(e)
			if k not_in f.types_off { f.types_off[strings.clone(k)] = true }
		}
	}
	folder_refilter(f)
}

Type_Count :: struct { ext: string, count: int }

// The types of the files of the listing (the hidden ones as shown), the most common first.
folder_types :: proc(f: ^Folder, allocator := context.temp_allocator) -> []Type_Count {
	counts := make(map[string]int, allocator = context.temp_allocator)
	for e in f.listing.entries {
		if e.kind == .Directory { continue }
		if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { continue }
		counts[type_key(e)] += 1
	}
	out := make([dynamic]Type_Count, allocator)
	for k, n in counts { append(&out, Type_Count{k, n}) }
	slice.sort_by(out[:], proc(a, b: Type_Count) -> bool { return a.count != b.count ? a.count > b.count : a.ext < b.ext })
	return out[:]
}

// Whether the types' popup leaves anything out.
folder_types_filtered :: proc(f: ^Folder) -> bool { return f.kinds != .All || len(f.types_off) > 0 }

folder_set_show_hidden :: proc(f: ^Folder, show: bool) {
	if f.show_hidden == show { return }
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	f.show_hidden = show
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// The rows again from `order`: the letters of the filter must be in the name in their order (fuzzy, File Pilot's: "rp10"
// keeps "report 10.pdf"; a space is no letter). A row that leaves the view leaves the
// selection too (what is selected is what the person sees).
folder_refilter :: proc(f: ^Folder) {
	entries := f.listing.entries[:]
	if f.filter != "" && len(f.lowered) != len(entries) {
		for s in f.lowered { delete(s) }
		clear(&f.lowered)
		for e in entries { append(&f.lowered, strings.to_lower(e.name)) }
	}
	clear(&f.shown)
	clear(&f.ids)
	// with a filter, the rows best matched first (letters side by side, at the start of a word: ui.fuzzy_score); the
	// order of the sort between equals
	scores := make([dynamic]int, context.temp_allocator)
	for i in f.order {
		e := entries[i]
		if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { continue }
		folder := e.kind == .Directory
		if (f.kinds == .Files && folder) || (f.kinds == .Folders && !folder) { continue }
		if !folder && len(f.types_off) > 0 && type_key(e) in f.types_off { continue }
		if f.filter != "" {
			if !fuzzy_holds(f.lowered[i], f.filter) { continue }
			score, _, _ := ui.fuzzy_score(f.filter, fs.base(e.name))
			append(&scores, score)
		}
		append(&f.shown, i)
		append(&f.ids, hash.fnv64a(transmute([]u8)e.name))
	}
	if f.filter != "" {
		Ranked :: struct { i: u32, score: int }
		ranked := make([]Ranked, len(f.shown), context.temp_allocator)
		for i, k in f.shown { ranked[k] = {i, scores[k]} }
		slice.stable_sort_by(ranked, proc(a, b: Ranked) -> bool { return a.score > b.score })
		for r, k in ranked {
			f.shown[k] = r.i
			f.ids[k] = hash.fnv64a(transmute([]u8)entries[r.i].name)
		}
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

// Whether the letters of `needle` are in `hay` in that order (both in lower case; spaces in the needle ignored).
fuzzy_holds :: proc(hay, needle: string) -> bool {
	at := 0
	for r in needle {
		if r == ' ' { continue }
		found := false
		for at < len(hay) {
			c, w := utf8.decode_rune_in_string(hay[at:])
			at += w
			if c == r { found = true; break }
		}
		if !found { return false }
	}
	return true
}

// The sorted order made the tree's: each entry, then the entries of the folder it is (when they were read), in the
// sort's order at each level.
tree_order :: proc(f: ^Folder) {
	entries := f.listing.entries[:]
	children := make(map[string][dynamic]u32, allocator = context.temp_allocator)
	for i in f.order {
		name := entries[i].name
		cut := len(name) - 1
		for cut >= 0 && !fs.is_separator(name[cut]) { cut -= 1 }
		parent := cut > 0 ? name[:cut] : ""
		if parent not_in children { children[parent] = make([dynamic]u32, context.temp_allocator) }
		append(&children[parent], i)
	}
	out := make([dynamic]u32, 0, len(f.order), context.temp_allocator)
	walk :: proc(entries: []fs.Entry, children: ^map[string][dynamic]u32, parent: string, out: ^[dynamic]u32, depth: int) {
		list, ok := children[parent]
		if !ok || depth > 64 { return }
		for i in list {
			append(out, i)
			if entries[i].kind == .Directory { walk(entries, children, entries[i].name, out, depth + 1) }
		}
	}
	walk(entries, &children, "", &out, 0)
	copy(f.order[:], out[:])
}

// How deep an entry of the tree is (0: the folder's own).
tree_depth :: proc(name: string) -> int {
	n := 0
	for i in 0 ..< len(name) { if fs.is_separator(name[i]) { n += 1 } }
	return n
}
