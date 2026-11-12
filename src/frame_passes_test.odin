package classeur

// A frame does no work in proportion to the number of entries: in a folder of a few thousand, the frames with nothing
// changed make the inspector's summary, the types' counts and the grid's row ids again none of the times; a change makes
// them once.

import "base:runtime"
import "core:fmt"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "gt:ui"

@(private = "file")
PASSES_ENTRIES :: 3000

// A folder of PASSES_ENTRIES files, of two types.
@(private = "file")
passes_folder :: proc(t: ^testing.T) -> string {
	names := make([]string, PASSES_ENTRIES, context.temp_allocator)
	for &n, i in names { n = fmt.tprintf("file %04d.%s", i, i % 3 == 0 ? "md" : "txt") }
	return make_fixture(t, names)
}

@(test)
test_frame_passes_summary :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		s, app := start(t, {passes_folder(t)})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder
		testing.expect_value(t, len(f.shown), PASSES_ENTRIES)
		point_at(t, tab, "file 0000.md")
		session.key(s, .Space)
		testing.expect(t, app.inspector.open, "the inspector")
		folder_select_all(f)
		session.wait_idle(s)
		testing.expect(t, session.find_text(s, fmt.tprintf("%d items", PASSES_ENTRIES)) != nil, "the summary")
		made := app.inspector.summary.made
		session.frames(s, 5)
		testing.expect_value(t, app.inspector.summary.made, made)
		// a row left out of the selection: made once again
		folder_set_row(f, 0, false)
		session.frames(s, 1)
		testing.expect_value(t, app.inspector.summary.made, made + 1)
		testing.expect(t, session.find_text(s, fmt.tprintf("%d items", PASSES_ENTRIES - 1)) != nil, "the summary made again")
		session.frames(s, 5)
		testing.expect_value(t, app.inspector.summary.made, made + 1)
	})
}

@(test)
test_frame_passes_types :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		s, app := start(t, {passes_folder(t)})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder
		types_menu_open(app, tab)
		session.wait_idle(s)
		testing.expect(t, ui.ctx_menu_is_open(app.panel_menus.types_key), "the types' popup")
		testing.expect(t, len(f.types) == 2 && f.types[0].ext == "txt" && f.types[0].count == 2000, "the types counted")
		made := f.types_made
		session.frames(s, 5)
		testing.expect_value(t, f.types_made, made)
		// a type left out: the rows change, counted once again
		folder_toggle_type(f, "md")
		session.frames(s, 1)
		testing.expect_value(t, f.types_made, made + 1)
		session.frames(s, 5)
		testing.expect_value(t, f.types_made, made + 1)
	})
}

// The inspector on a large folder: its first rows built, the others counted (a frame built them all).
@(test)
test_frame_passes_inspector_folder :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		names := make([dynamic]string, context.temp_allocator)
		append(&names, "big/")
		for i in 0 ..< INSPECTOR_SUMMARY_ROWS + 100 { append(&names, fmt.tprintf("big/file %03d.txt", i)) }
		s, app := start(t, {make_fixture(t, names[:])})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		point_at(t, tab, "big")
		session.key(s, .Space)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 2)
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Folder)
		testing.expect(t, session.find(s, fmt.tprintf("insp_e%d", INSPECTOR_SUMMARY_ROWS - 1)) != nil, "its first rows")
		testing.expect(t, session.find(s, fmt.tprintf("insp_e%d", INSPECTOR_SUMMARY_ROWS)) == nil, "no more rows")
		testing.expect(t, session.find_text(s, "and 100 more") != nil, "the others counted")
	})
}

@(test)
test_frame_passes_grid :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		s, app := start(t, {passes_folder(t)}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder
		tab_set_zoom(app, tab, ZOOM_GRID)
		// (the cards grow to their size: the cards per row settle with them)
		session.wait_idle(s)
		testing.expect_value(t, tab_mode(tab), View_Mode.Grid)
		cols := max(tab.grid_cols, 1)
		testing.expect_value(t, len(tab.grid_ids), (PASSES_ENTRIES + cols - 1) / cols)
		made := tab.grid_ids_made
		session.frames(s, 5)
		testing.expect_value(t, tab.grid_ids_made, made)
		// a filter: the rows change, the ids made once again (the field's text goes to the folder in a build: the
		// grid's may come before it, then in the next one)
		ui.field_set(&tab.filter, "0001")
		session.frames(s, 2)
		testing.expect(t, f.filter == "0001" && len(f.shown) < PASSES_ENTRIES, "filtered")
		testing.expect_value(t, tab.grid_ids_made, made + 1)
		testing.expect_value(t, len(tab.grid_ids), (len(f.shown) + cols - 1) / cols)
		session.frames(s, 5)
		testing.expect_value(t, tab.grid_ids_made, made + 1)
	})
}
