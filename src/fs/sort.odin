package fs

// The order of a listing's entries: an array of indices, sorted by a key, folders first or mixed. The comparison of
// names is natural ("file 2" before "file 10") and ignores the case.

import "core:unicode"
import "core:unicode/utf8"

Sort_Key :: enum u8 {
	Name,
	Size,
	Modified,
	Type,
}

Sort :: struct {
	key:           Sort_Key,
	descending:    bool,
	mixed:         bool,   // folders among files; false: folders first
}

// Natural order of two names: digits compare by their value, letters without their case; equal so far, the bytes
// decide (so that two names never compare equal unless they are).
name_compare :: proc(a, b: string) -> int {
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		ca, cb := a[i], b[j]
		if is_digit(ca) && is_digit(cb) {
			// digit runs: without their leading zeros, the longer is larger, then the first digit that differs
			ia, ib := i, j
			for ia < len(a) && a[ia] == '0' { ia += 1 }
			for ib < len(b) && b[ib] == '0' { ib += 1 }
			ea, eb := ia, ib
			for ea < len(a) && is_digit(a[ea]) { ea += 1 }
			for eb < len(b) && is_digit(b[eb]) { eb += 1 }
			if ea - ia != eb - ib { return ea - ia < eb - ib ? -1 : 1 }
			for k in 0 ..< ea - ia {
				if a[ia + k] != b[ib + k] { return a[ia + k] < b[ib + k] ? -1 : 1 }
			}
			i, j = ea, eb
			continue
		}
		ra, wa := rune(ca), 1
		rb, wb := rune(cb), 1
		if ca >= 0x80 { ra, wa = utf8.decode_rune_in_string(a[i:]) }
		if cb >= 0x80 { rb, wb = utf8.decode_rune_in_string(b[j:]) }
		la, lb := fold(ra), fold(rb)
		if la != lb { return la < lb ? -1 : 1 }
		i += wa
		j += wb
	}
	switch {
	case i < len(a):  return 1
	case j < len(b):  return -1
	case a < b:       return -1
	case a > b:       return 1
	}
	return 0
}

@(private = "file")
is_digit :: #force_inline proc(c: u8) -> bool { return c >= '0' && c <= '9' }

// The base letters of U+00C0 ..= U+00FF and of U+0100 ..= U+017F ('.': a sign that has none, kept as it is): "é" sorts
// with "e", as a person reading names expects.
@(private = "file")
LATIN_1_BASE :: "aaaaaaaceeeeiiiidnooooo.ouuuuy.saaaaaaaceeeeiiiidnooooo.ouuuuy.y"
@(private = "file")
LATIN_A_BASE :: "aaaaaaccccccccddddeeeeeeeeeegggggggghhhhiiiiiiiiiiiijjkkkllllllllllnnnnnnnnnoooooooorrrrrrssssssssttttttuuuuuuuuuuuuwwyyyzzzzzzs"
#assert(len(LATIN_1_BASE) == 0x40)
#assert(len(LATIN_A_BASE) == 0x80)

// The rune without its case, and without its accent for the Latin letters.
@(private = "file")
fold :: #force_inline proc(r: rune) -> rune {
	switch {
	case r < 0x80:
		return r >= 'A' && r <= 'Z' ? r + 32 : r
	case r >= 0xC0 && r < 0x100:
		bases := LATIN_1_BASE
		if c := bases[r - 0xC0]; c != '.' { return rune(c) }
	case r >= 0x100 && r < 0x180:
		bases := LATIN_A_BASE
		return rune(bases[r - 0x100])
	}
	return unicode.to_lower(r)
}

@(private = "file")
is_folder :: #force_inline proc(e: Entry) -> bool { return e.kind == .Directory }

// a before b in the order `s`.
entry_less :: proc(a, b: Entry, s: Sort) -> bool {
	if !s.mixed && is_folder(a) != is_folder(b) { return is_folder(a) }
	c := 0
	switch s.key {
	case .Name:
	case .Size:     c = a.size < b.size ? -1 : a.size > b.size ? 1 : 0
	case .Modified: c = a.mtime < b.mtime ? -1 : a.mtime > b.mtime ? 1 : 0
	case .Type:     c = name_compare(extension(a.name), extension(b.name))
	}
	if c == 0 { c = name_compare(a.name, b.name) }
	return s.descending ? c > 0 : c < 0
}

// Sorts `order` (indices into `entries`) by `s`: a merge sort, stable, n log n comparisons whatever the order it starts in.
sort_order :: proc(entries: []Entry, order: []u32, s: Sort) {
	if len(order) < 2 { return }
	tmp := make([]u32, len(order), context.temp_allocator)
	merge_sort(entries, order, tmp, s)
}

@(private = "file")
INSERTION_RUN :: 16

@(private = "file")
merge_sort :: proc(entries: []Entry, a, tmp: []u32, s: Sort) {
	n := len(a)
	if n <= INSERTION_RUN {
		for i in 1 ..< n {
			v := a[i]
			j := i
			for j > 0 && entry_less(entries[v], entries[a[j - 1]], s) {
				a[j] = a[j - 1]
				j -= 1
			}
			a[j] = v
		}
		return
	}
	mid := n / 2
	merge_sort(entries, a[:mid], tmp[:mid], s)
	merge_sort(entries, a[mid:], tmp[mid:], s)
	if !entry_less(entries[a[mid]], entries[a[mid - 1]], s) { return }   // (already in order)
	copy(tmp, a)
	i, j, k := 0, mid, 0
	for i < mid && j < n {
		if entry_less(entries[tmp[j]], entries[tmp[i]], s) {
			a[k] = tmp[j]; j += 1
		} else {
			a[k] = tmp[i]; i += 1
		}
		k += 1
	}
	for i < mid { a[k] = tmp[i]; i += 1; k += 1 }
	for j < n { a[k] = tmp[j]; j += 1; k += 1 }
}
