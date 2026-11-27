package classeur

// The selection of several rows: the toolkit's model (gt src/md/features/selection.md) fed by the folder's rows, its
// bytes kept, its ids held through a sort and a new listing; the keys of the list; an action on all the rows selected.

import "base:runtime"
import "core:fmt"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

@(private = "file")
sized_listing :: proc(sizes: []i64) -> (l: fs.Listing) {
	l.path = fs.keep_name(&l, "/x")
	for size, i in sizes {
		append(&l.entries, fs.Entry{name = fs.keep_name(&l, fmt.tprintf("%c.txt", 'a' + rune(i))), kind = .File, size = size})
	}
	return
}

@(private = "file")
selected_names :: proc(f: ^Folder) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for e in folder_targets(f) { append(&names, e.name) }
	return fmt.tprint(names)
}

// Ctrl toggles, Shift a range from the anchor (a second one nearer makes it smaller), Ctrl+Shift adds the range; the
// bytes follow; a sort keeps the names selected; a filter drops those it hides.
@(test)
test_folder_selection_gestures :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		f: Folder
		defer folder_destroy(&f)
		l := sized_listing({1, 2, 4, 8, 16, 32})
		folder_set_listing(&f, &l)
		testing.expect_value(t, len(f.selected), 0)

		folder_pick(&f, 1)
		folder_pick(&f, 3, {.Ctrl})
		testing.expect_value(t, selected_names(&f), `["b.txt", "d.txt"]`)
		bytes, n := folder_selection_size(&f)
		testing.expect_value(t, n, 2)
		testing.expect_value(t, bytes, i64(10))

		// (the anchor is d.txt, the Ctrl+click's row)
		folder_pick(&f, 5, {.Shift})
		testing.expect_value(t, selected_names(&f), `["d.txt", "e.txt", "f.txt"]`)
		folder_pick(&f, 4, {.Shift})
		testing.expect_value(t, selected_names(&f), `["d.txt", "e.txt"]`)

		// Ctrl+Shift: the range over what there was when the anchor was set (b.txt and d.txt)
		folder_pick(&f, 5, {.Ctrl, .Shift})
		testing.expect_value(t, selected_names(&f), `["b.txt", "d.txt", "e.txt", "f.txt"]`)
		bytes, n = folder_selection_size(&f)
		testing.expect_value(t, n, 4)
		testing.expect_value(t, bytes, i64(2 + 8 + 16 + 32))

		// a row the rectangle takes out, one by one: the bytes kept row by row
		folder_set_row(&f, 4, false)
		bytes, n = folder_selection_size(&f)
		testing.expect_value(t, bytes, i64(2 + 8 + 32))
		testing.expect_value(t, n, 3)

		// the largest first: the same names selected, in the new order
		folder_sort_by(&f, .Size)
		testing.expect_value(t, selected_names(&f), `["f.txt", "d.txt", "b.txt"]`)

		// a filter that hides b.txt: it leaves the selection
		folder_set_filter(&f, "d")
		testing.expect_value(t, selected_names(&f), `["d.txt"]`)
		folder_set_filter(&f, "")
		testing.expect_value(t, selected_names(&f), `["d.txt"]`)

		// a new listing of the same names: the selection holds, the sizes are the new ones
		again := sized_listing({1, 2, 4, 100, 16, 32})
		folder_set_listing(&f, &again)
		bytes, n = folder_selection_size(&f)
		testing.expect_value(t, n, 1)
		testing.expect_value(t, bytes, i64(100))

		folder_select_all(&f)
		testing.expect_value(t, len(f.selected), 6)
		folder_select_none(&f)
		testing.expect_value(t, len(f.selected), 0)
	})
}

// The keys of the list: Shift+Down a range, Ctrl+Down the cursor alone, Ctrl+Space toggles, Escape keeps the cursor's
// row; a cut acts on
// every row selected, not on the cursor's.
@(test)
test_list_selection_keys :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt", "b.txt", "c.txt", "d.txt", "e.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder

		session.key(s, .Home)
		session.key(s, .Down, {.Shift})
		testing.expect_value(t, selected_names(f), `["a.txt", "b.txt"]`)
		// Ctrl: the cursor moves, the selection stays
		session.key(s, .Down, {.Ctrl}, repeat = 2)
		testing.expect_value(t, folder_cursor_entry(f).name, "d.txt")
		testing.expect_value(t, selected_names(f), `["a.txt", "b.txt"]`)
		// Ctrl+Space: d.txt added
		session.key(s, .Space, {.Ctrl})
		testing.expect_value(t, selected_names(f), `["a.txt", "b.txt", "d.txt"]`)

		// the cut takes the three, c.txt at their middle not
		session.key(s, .X, {.Ctrl})
		session.frames(s, 2)
		for name in ([]string{"a.txt", "b.txt", "d.txt"}) {
			testing.expectf(t, row_is_cut(app, fs.join(dir, name, context.temp_allocator)), "%s cut", name)
		}
		testing.expect(t, !row_is_cut(app, fs.join(dir, "c.txt", context.temp_allocator)), "c.txt not cut")

		// Escape on several: the cursor's row alone; on one, the selection stays (the Escape is the window's)
		session.key(s, .Escape)
		testing.expect_value(t, selected_names(f), `["d.txt"]`)
		session.key(s, .Escape)
		testing.expect_value(t, selected_names(f), `["d.txt"]`)
	})
}

// Reloading the same folder keeps the Shift anchor while its row exists, so extending a range with Shift+Down across a
// background refresh does not restart from the cursor.
@(test)
test_selection_anchor_kept_on_reload :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt", "b.txt", "c.txt", "d.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder

		session.key(s, .Home)
		session.key(s, .Down, {.Shift})
		testing.expect_value(t, selected_names(f), `["a.txt", "b.txt"]`)
		tab_load(app, tab)
		wait_read(s)
		session.key(s, .Down, {.Shift})
		testing.expect_value(t, selected_names(f), `["a.txt", "b.txt", "c.txt"]`)
	})
}
