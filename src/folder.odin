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
import "core:time/timezone"
import "core:time/datetime"
import "core:time"
import "core:unicode/utf8"
import "gt:ui"
import "fs"

Folder :: struct {
	listing:     fs.Listing,
	loaded:      bool,              // a listing came (it may be an error)
	flat:        bool,              // the listing is a flat read: its names are paths from the folder
	tree:        bool,              // the tree view: its names are paths too, the rows in the tree's order
	group:       Group_By,          // the rows grouped (by date, type or size), the sort's order in each group
	group_now:   i64,               // the date groups' "now" (ns), set when grouped by date
	group_tz:    ^datetime.TZ_Region,
	folded:      map[string]bool,   // the groups folded (keys owned): their first row alone, as their title
	sort:        fs.Sort,
	show_hidden: bool,
	filter:      string,            // owned; lower case; "" shows every row
	kinds:       Kind_Filter,       // files and folders, or one of them (the types' popup)
	types_off:   map[string]bool,   // the extensions left out, lower case, keys owned ("" the files with none)
	dates_off:   Ranks,             // the date groups left out (the Modified column's filter: group_rank .Date)
	sizes_off:   Ranks,             // the size groups left out (the Size column's filter: group_rank .Size)
	filter_now:  i64,               // the date filter's "now" (ns), set with it
	today_of:    i64,               // the "now" whose local day is `today` (one conversion per refilter, not per row)
	today:       i64,
	order:       [dynamic]u32,      // every entry, sorted
	shown:       [dynamic]u32,      // the rows: `order` without what the filter and the hidden setting leave out
	size_max:    i64,               // the largest size among the rows (the Size column's bars are its share)
	name_index:  map[string]int,    // each entry's index by its name (folder_find_name), its keys the listing's
	name_index_n: int,              // the entries it was made for (another count, or -1: made again)
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
	delete(f.name_index)
	for k in f.types_off { delete(k) }
	delete(f.types_off)
	for k in f.folded { delete(k) }
	delete(f.folded)
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
	f.name_index_n = -1
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

// Entries added (a walk's batch): their names kept in the listing, sorted with the others, the rows of those kept put
// among the rows shown; the cursor and the selection stay on their entries. A batch costs its own sort and a merge:
// the entries already there are not filtered again (a search of a large tree gets hundreds of batches).
folder_add_entries :: proc(f: ^Folder, batch: ^fs.Listing) {
	n := len(f.listing.entries)
	lowered := len(f.lowered) == n   // (the filter's lower-case names: extended, not made again)
	for e in batch.entries {
		x := e
		x.name = fs.keep_name(&f.listing, e.name)
		append(&f.listing.entries, x)
		append(&f.selected, false)
		if lowered { append(&f.lowered, strings.to_lower(x.name)) }
	}
	if len(f.listing.entries) == n { return }
	f.name_index_n = -1   // (the names' index is made again when asked)
	// the new ones sorted alone
	added := make([]u32, len(f.listing.entries) - n, context.temp_allocator)
	for &a, k in added { a = u32(n + k) }
	fs.sort_order(f.listing.entries[:], added, f.sort)
	if f.tree {
		for i in n ..< len(f.listing.entries) { append(&f.order, u32(i)) }
		fs.sort_order(f.listing.entries[:], f.order[:], f.sort)
		tree_order(f)
	} else {
		// then merged with the order (the order of all is not sorted again); equal: the old one first
		old := slice.clone(f.order[:], context.temp_allocator)
		clear(&f.order)
		i, j := 0, 0
		for i < len(old) || j < len(added) {
			if j >= len(added) || i < len(old) && !fs.entry_less(f.listing.entries[added[j]], f.listing.entries[old[i]], f.sort) {
				append(&f.order, old[i]); i += 1
			} else {
				append(&f.order, added[j]); j += 1
			}
		}
	}
	// (the tree's order, a folded group's title row, the names not in lower case yet: the rows made again)
	if f.tree || len(f.folded) > 0 || (f.filter != "" && !lowered) {
		name := ""
		if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
		folder_refilter(f)
		if name != "" { folder_cursor_to_name(f, name) }
		return
	}
	folder_merge_shown(f, added)
}

// Where a row goes among the rows shown (folder_refilter's order): the filter's score, else its group, then the sort's.
@(private = "file")
Shown_Key :: struct {
	i:     u32,
	score: int,      // the filter's (none: 0)
	rank:  int,      // the group's (not grouped, or a filter: 0, "")
	group: string,
}

@(private = "file")
shown_key :: proc(f: ^Folder, i: u32) -> Shown_Key {
	k := Shown_Key{i = i}
	e := f.listing.entries[i]
	if f.filter != "" {
		k.score, _, _ = ui.fuzzy_score(f.filter, fs.base(e.name))
	} else if f.group != .None {
		k.rank, k.group = group_of(f, e)
	}
	return k
}

// Whether a new row `a` comes before the row `b` already shown. Equal: `b` first (the order's merge puts the old first).
@(private = "file")
shown_before :: proc(f: ^Folder, a, b: Shown_Key) -> bool {
	if a.score != b.score { return a.score > b.score }
	if a.rank != b.rank { return a.rank < b.rank }
	if a.group != b.group { return a.group < b.group }
	return fs.entry_less(f.listing.entries[a.i], f.listing.entries[b.i], f.sort)
}

// The rows of `added` (sorted) that the filters keep, put where folder_refilter would put them: each found by a search
// among the rows shown, the rows after it moved once. The cursor and the anchor stay on their rows.
@(private = "file")
folder_merge_shown :: proc(f: ^Folder, added: []u32) {
	entries := f.listing.entries[:]
	kept := make([dynamic]Shown_Key, 0, len(added), context.temp_allocator)
	for i in added { if folder_keeps(f, i) { append(&kept, shown_key(f, i)) } }
	if len(kept) == 0 { return }
	// (stable: equal keys keep the sort's order)
	slice.stable_sort_by(kept[:], proc(a, b: Shown_Key) -> bool {
		if a.score != b.score { return a.score > b.score }
		if a.rank != b.rank { return a.rank < b.rank }
		return a.group < b.group
	})
	// where each goes: before the first row shown it comes before (sorted, each search starts at the last one's place)
	old_n := len(f.shown)
	at := make([]int, len(kept), context.temp_allocator)
	lo := 0
	for k, j in kept {
		hi := old_n
		for lo < hi {
			mid := (lo + hi) / 2
			if shown_before(f, k, shown_key(f, f.shown[mid])) { hi = mid } else { lo = mid + 1 }
		}
		at[j] = lo
	}
	// from the end: each old row moved once, by the number of new rows before it
	resize(&f.shown, old_n + len(kept))
	resize(&f.ids, old_n + len(kept))
	src, dst := old_n - 1, len(f.shown) - 1
	for j := len(kept) - 1; j >= 0; j -= 1 {
		for src >= at[j] {
			f.shown[dst], f.ids[dst] = f.shown[src], f.ids[src]
			src -= 1
			dst -= 1
		}
		i := kept[j].i
		f.shown[dst] = i
		f.ids[dst] = hash.fnv64a(transmute([]u8)entries[i].name)
		f.size_max = max(f.size_max, entries[i].size)
		dst -= 1
	}
	moved :: proc(row: int, places: []int) -> int {
		if row < 0 { return row }
		before := 0
		for p in places { if p <= row { before += 1 } }
		return row + before
	}
	f.cursor = moved(f.cursor, at)
	f.anchor = moved(f.anchor, at)
}

// The entry of a name in the listing (-1: none), by an index of the names made at the first ask after the listing changed.
folder_find_name :: proc(f: ^Folder, name: string) -> int {
	if f.name_index_n != len(f.listing.entries) {
		clear(&f.name_index)
		for e, i in f.listing.entries { f.name_index[e.name] = i }
		f.name_index_n = len(f.listing.entries)
	}
	return f.name_index[name] or_else -1
}

// The order again, the same sort (folders' sizes measured since): the cursor stays on its entry.
folder_resort :: proc(f: ^Folder) {
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	fs.sort_order(f.listing.entries[:], f.order[:], f.sort)
	if f.tree { tree_order(f) }
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
}

// Sorts by `key`; the same key again turns the order around. Dates and sizes start with the largest.
// A column's sort, a click after another: its first way (dates and sizes the largest first), the other way, then the
// order there was before any (the names going up); the name's has two, the second being that order.
folder_sort_by :: proc(f: ^Folder, key: fs.Sort_Key) {
	s := f.sort
	first_down := sort_first_down(key)
	switch {
	case s.key != key:
		s.key, s.descending = key, first_down
	case key != .Name && s.descending != first_down:
		s.key, s.descending = .Name, false
	case:
		s.descending = !s.descending
	}
	folder_set_sort(f, s)
}

// Whether a column sorts the largest first at its first click (dates, sizes).
sort_first_down :: proc(key: fs.Sort_Key) -> bool { return key == .Modified || key == .Size }

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
folder_types_filtered :: proc(f: ^Folder) -> bool { return f.kinds != .All || len(f.types_off) > 0 || f.dates_off != {} || f.sizes_off != {} }

// The groups of a column's filter (group_rank's ranks).
Ranks :: bit_set[0 ..< 8; u8]

// A date or size group shown or left out (the Modified and the Size columns' filters); `now` and `tz` place the days.
folder_toggle_rank :: proc(f: ^Folder, by: Group_By, rank: int, now: i64, tz: ^datetime.TZ_Region) {
	#partial switch by {
	case .Date: f.dates_off ~= {rank}
	case .Size: f.sizes_off ~= {rank}
	}
	f.filter_now, f.group_tz = now, tz
	folder_refilter(f)
	if f.cursor < 0 && len(f.shown) > 0 { f.cursor = 0 }
}

// Every date (or size) shown again.
folder_all_ranks :: proc(f: ^Folder, by: Group_By) {
	#partial switch by {
	case .Date: f.dates_off = {}
	case .Size: f.sizes_off = {}
	}
	folder_refilter(f)
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
	f.size_max = 0
	// with a filter, the rows best matched first (letters side by side, at the start of a word: ui.fuzzy_score); the
	// order of the sort between equals
	scores := make([dynamic]int, context.temp_allocator)
	for i in f.order {
		if !folder_keeps(f, i) { continue }
		e := entries[i]
		if f.filter != "" {
			score, _, _ := ui.fuzzy_score(f.filter, fs.base(e.name))
			append(&scores, score)
		}
		append(&f.shown, i)
		append(&f.ids, hash.fnv64a(transmute([]u8)e.name))
		f.size_max = max(f.size_max, e.size)
	}
	if f.group != .None && f.filter == "" {
		// (grouped: by the group's rank, stable: the sort's order in each group)
		Grouped :: struct { i: u32, rank: int, key: string }
		g := make([]Grouped, len(f.shown), context.temp_allocator)
		for i, k in f.shown { rank, key := group_of(f, entries[i]); g[k] = {i, rank, key} }
		slice.stable_sort_by(g, proc(a, b: Grouped) -> bool { return a.rank != b.rank ? a.rank < b.rank : a.key < b.key })
		// (a folded group keeps its first row: its title is drawn on it)
		clear(&f.shown)
		clear(&f.ids)
		for x, k in g {
			if k > 0 && g[k - 1].key == x.key && x.key in f.folded { continue }
			append(&f.shown, x.i)
			append(&f.ids, hash.fnv64a(transmute([]u8)entries[x.i].name))
		}
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

// Whether entry `i` is a row: the hidden setting, the types' popup, the columns' filters and the filter keep it (the
// filter's lower-case names made).
folder_keeps :: proc(f: ^Folder, i: u32) -> bool {
	e := f.listing.entries[i]
	if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { return false }
	folder := e.kind == .Directory
	if (f.kinds == .Files && folder) || (f.kinds == .Folders && !folder) { return false }
	if !folder && len(f.types_off) > 0 && type_key(e) in f.types_off { return false }
	if f.dates_off != {} { if r, _ := group_rank(f, e, .Date, f.filter_now); r in f.dates_off { return false } }
	if f.sizes_off != {} { if r, _ := group_rank(f, e, .Size, 0); r in f.sizes_off { return false } }
	return f.filter == "" || fuzzy_holds(f.lowered[i], f.filter)
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
		if e.size > 0 && e.kind != .Directory { bytes += e.size }   // (a folder's measured size in its entry: not a file's)
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

// How the rows are grouped (File Pilot's Group By).
Group_By :: enum u8 { None, Date, Type, Size }

folder_set_group :: proc(f: ^Folder, g: Group_By, now: i64, tz: ^datetime.TZ_Region) {
	f.group, f.group_now, f.group_tz = g, now, tz
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
}

// The group of an entry: its rank (the groups' order) and its key (its title, the order of equal ranks).
group_of :: proc(f: ^Folder, e: fs.Entry) -> (rank: int, key: string) { return group_rank(f, e, f.group, f.group_now) }

// An entry's group `by` dates (days from `now`) or sizes, or types: what the groups and the columns' filters share.
group_rank :: proc(f: ^Folder, e: fs.Entry, by: Group_By, now: i64) -> (rank: int, key: string) {
	switch by {
	case .None:
	case .Type:
		if e.kind == .Directory { return 0, "Folders" }
		ext := strings.to_upper(fs.extension(fs.base(e.name)), context.temp_allocator)
		return 1, ext == "" ? "No extension" : ext
	case .Size:
		if e.kind == .Directory { return 0, "Folders" }
		switch {
		case e.size < 16 * 1024:           return 1, "Tiny (under 16 KB)"
		case e.size < 1024 * 1024:         return 2, "Small (under 1 MB)"
		case e.size < 128 * 1024 * 1024:   return 3, "Medium (under 128 MB)"
		case e.size < 1024 * 1024 * 1024:  return 4, "Large (under 1 GB)"
		}
		return 5, "Huge (1 GB and more)"
	case .Date:
		day := day_number(e.mtime, f.group_tz)
		if f.today_of != now || now == 0 { f.today_of, f.today = now, day_number(now, f.group_tz) }
		today := f.today
		switch {
		case e.mtime == 0:         return 7, "No date"
		case day >= today:         return 0, "Today"
		case day == today - 1:     return 1, "Yesterday"
		case day > today - 7:      return 2, "This week"
		case day > today - 31:     return 3, "This month"
		case day > today - 365:    return 4, "This year"
		}
		return 5, "Older"
	}
	return 0, ""
}

// The local day of a time (days since 1970), for the date groups.
@(private = "file")
day_number :: proc(ns: i64, tz: ^datetime.TZ_Region) -> i64 {
	dt, ok := time.time_to_datetime(time.Time{_nsec = ns})
	if !ok { return 0 }
	if tz != nil { if local, lok := timezone.datetime_to_tz(dt, tz); lok { dt = local } }
	ord, _ := datetime.date_to_ordinal(dt.date)
	return i64(ord)
}

// A group folded, or unfolded again.
folder_fold :: proc(f: ^Folder, key: string) {
	if key in f.folded {
		k, _ := delete_key(&f.folded, key)
		delete(k)
	} else {
		f.folded[strings.clone(key)] = true
	}
	name := ""
	if e := folder_cursor_entry(f); e != nil { name = strings.clone(e.name, context.temp_allocator) }
	folder_refilter(f)
	if name != "" { folder_cursor_to_name(f, name) }
}
