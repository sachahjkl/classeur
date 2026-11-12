package classeur

// A large folder: read and sorted on a worker, the rows and their counts ready when it comes; a frame that changes
// nothing does no pass over the rows; a filter typed, a type left out, a paste of many names selected.
// Run with -define:ODIN_TEST_THREADS=1 (one interface at a time).

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "gt:testkit"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "fs"

@(private = "file") LARGE_FOLDER :: 20_000
@(private = "file") LARGE_EVERY_MD :: 4        // one name in 4 is a .md
@(private = "file") LARGE_EVERY_BYTE :: 1000   // one file in 1000 holds a byte
@(private = "file") LARGE_FILTER :: "n1999"

// The name of the large folder's file `i`.
@(private = "file")
large_name :: proc(i: int) -> string {
	return fmt.tprintf("n%d.%s", i, i % LARGE_EVERY_MD == 0 ? "md" : "txt")
}

@(private = "file")
make_large :: proc(t: ^testing.T) -> string {
	dir := fs.clean(testkit.temp_folder(t, "classeur"), context.temp_allocator)
	one := []u8{'x'}
	for i in 0 ..< LARGE_FOLDER {
		_ = os.write_entire_file(fs.join(dir, large_name(i), context.temp_allocator), i % LARGE_EVERY_BYTE == 0 ? one : nil)
	}
	return dir
}

@(test)
test_large_folder :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_large(t)
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder

		// every file, in the natural order of their names, with what the frames read counted already
		testing.expect_value(t, len(f.listing.entries), LARGE_FOLDER)
		testing.expect_value(t, len(f.shown), LARGE_FOLDER)
		for k in 1 ..< len(f.shown) {
			if fs.entry_less(f.listing.entries[f.shown[k]], f.listing.entries[f.shown[k - 1]], f.sort) {
				testing.expectf(t, false, "row %d out of order", k)
				break
			}
		}
		testing.expect_value(t, f.listing.entries[f.shown[0]].name, "n0.md")
		testing.expect_value(t, f.listing.entries[f.shown[LARGE_FOLDER - 1]].name, large_name(LARGE_FOLDER - 1))
		testing.expect_value(t, f.files, LARGE_FOLDER)
		testing.expect_value(t, f.files_shown, LARGE_FOLDER)
		testing.expect_value(t, f.folders + f.folders_shown, 0)
		for row in ([]int{0, 1, LARGE_FOLDER / 2, LARGE_FOLDER - 1}) {
			i := f.shown[row]
			testing.expect_value(t, f.ids[row], hash.fnv64a(transmute([]u8)f.listing.entries[i].name))
			testing.expect_value(t, int(f.row_of[i]), row)
		}

		// a frame that changes nothing: the list's offsets are not made again (no pass over the rows)
		session.frames(s, 3)
		made := tab.vl.offsets_made
		session.frames(s, 5)
		testing.expect_value(t, tab.vl.offsets_made, made)

		// the selection's size, counted as it changes: every row, the bytes of the files that hold one
		folder_select_all(f)
		bytes, n := folder_selection_size(f)
		testing.expect_value(t, n, LARGE_FOLDER)
		testing.expect_value(t, bytes, i64(LARGE_FOLDER / LARGE_EVERY_BYTE))
		folder_pick(f, 0)
		bytes, n = folder_selection_size(f)
		testing.expect_value(t, n, 1)
		testing.expect_value(t, bytes, i64(1))   // ("n0.md" holds a byte)

		// typed in the filter: the rows that hold its letters in their order, the best matched first
		session.key(s, .F, {.Ctrl})
		session.type_text(s, LARGE_FILTER)
		want := 0
		for e in f.listing.entries { if fuzzy_holds(e.name, LARGE_FILTER) { want += 1 } }
		testing.expect_value(t, len(f.shown), want)
		testing.expect_value(t, f.files_shown, want)
		testing.expect_value(t, f.listing.entries[f.shown[0]].name, "n1999.txt")
		for i in f.shown {
			if !fuzzy_holds(f.listing.entries[i].name, LARGE_FILTER) {
				testing.expectf(t, false, "%s kept", f.listing.entries[i].name)
				break
			}
		}
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect_value(t, len(f.shown), LARGE_FOLDER)

		// a type left out (by the types kept with the listing), then back
		folder_toggle_type(f, "md")
		testing.expect_value(t, len(f.shown), LARGE_FOLDER - LARGE_FOLDER / LARGE_EVERY_MD)
		testing.expect_value(t, f.files, LARGE_FOLDER)
		folder_toggle_type(f, "md")
		testing.expect_value(t, len(f.shown), LARGE_FOLDER)

		// a paste of many names: they are selected when the folder is read again, the cursor on the first
		// (owned: the tab deletes them)
		for i := LARGE_FOLDER - 1; i >= 0; i -= 2 { append(&tab.select_names, strings.clone(large_name(i))) }
		append(&tab.select_names, strings.clone("gone.txt"))
		tab_load(app, tab)
		wait_read(s)
		testing.expect_value(t, f.count, LARGE_FOLDER / 2)
		testing.expect_value(t, len(tab.select_names), 0)
		e := folder_cursor_entry(f)
		testing.expect(t, e != nil && e.name == large_name(LARGE_FOLDER - 1), "the cursor on the first name pasted")
		testing.expect(t, f.selected[f.shown[f.cursor]], "it is selected")
		testing.expect(t, !folder_row_selected(f, 0), "n0.md was not pasted")
	})
}

// A listing prepared with the settings the tab had when it asked, while the person sorted and filtered again: what
// it shows is made with the new ones (sorted, hidden files shown, a type left out); the names selected and the cursor stay on their entries.
@(test)
test_folder_take_settings_changed :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		f: Folder
		defer folder_destroy(&f)
		listing :: proc(sizes: []i64) -> (l: fs.Listing) {
			l.path = fs.keep_name(&l, "/x")
			for size, i in sizes {
				append(&l.entries, fs.Entry{name = fs.keep_name(&l, fmt.tprintf("%c.txt", 'a' + rune(i))), kind = .File, size = size})
			}
			return
		}
		first := listing({1, 2, 3, 4})
		folder_set_listing(&f, &first)
		folder_cursor_to_name(&f, "c.txt")
		folder_pick(&f, f.cursor, toggle = true)
		folder_pick(&f, 1, toggle = true)   // (b.txt)
		testing.expect_value(t, f.count, 2)

		p: Folder
		folder_view_copy(&p, &f)
		folder_sort_by(&f, .Size)   // (the largest first)
		folder_set_show_hidden(&f, true)
		folder_toggle_type(&f, "md")   // (nothing of the kind: every row stays)
		again := listing({1, 2, 3, 4, 5})
		folder_prepare(&p, &again)
		folder_take(&f, &p)
		names := make([dynamic]string, context.temp_allocator)
		for i in f.shown { append(&names, f.listing.entries[i].name) }
		testing.expect_value(t, fmt.tprint(names), `["e.txt", "d.txt", "c.txt", "b.txt", "a.txt"]`)
		testing.expect_value(t, f.count, 2)
		testing.expect(t, f.selected[folder_find_name(&f, "b.txt")] && f.selected[folder_find_name(&f, "c.txt")], "the names selected")
		testing.expect_value(t, folder_cursor_entry(&f).name, "b.txt")   // (the last picked)
		bytes, _ := folder_selection_size(&f)
		testing.expect_value(t, bytes, i64(5))
		testing.expect_value(t, f.files, 5)
	})
}

// The date filter by the days kept with the listing: today's entry left out, the others kept.
@(test)
test_folder_date_filter_days :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		f: Folder
		defer folder_destroy(&f)
		now := time.now()._nsec
		DAY :: i64(24 * time.Hour)
		l: fs.Listing
		l.path = fs.keep_name(&l, "/x")
		append(&l.entries, fs.Entry{name = fs.keep_name(&l, "today.txt"), kind = .File, mtime = now})
		append(&l.entries, fs.Entry{name = fs.keep_name(&l, "older.txt"), kind = .File, mtime = now - 400 * DAY})
		append(&l.entries, fs.Entry{name = fs.keep_name(&l, "none.txt"), kind = .File})
		folder_set_listing(&f, &l)
		testing.expect_value(t, len(f.days), 3)
		today, _ := group_rank(&f, f.listing.entries[folder_find_name(&f, "today.txt")], .Date, now)
		folder_toggle_rank(&f, .Date, today, now, nil)
		names := make([dynamic]string, context.temp_allocator)
		for i in f.shown { append(&names, f.listing.entries[i].name) }
		testing.expect_value(t, fmt.tprint(names), `["none.txt", "older.txt"]`)
	})
}
