package classeur

// The keyboard beyond the list: F6 and Ctrl+Shift+F6 through the sidebar, the panels' lists and the inspector; the
// sidebar's cursor and the inspector's scroll; the list's cursor left alone meanwhile.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "fs"

@(test)
test_keys_stops :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		testing.expect_value(t, app.keys_at, Keys_At.List)
		// (the sidebar, the list: F6 goes round them)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Sidebar)
		session.key(s, .F6, {.Ctrl, .Shift})
		testing.expect_value(t, app.keys_at, Keys_At.List)
		// with the inspector open: the list, the inspector, the sidebar
		session.key(s, .Space)
		testing.expect(t, app.inspector.open)
		session.frames(s, 2)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Inspector)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Sidebar)
		session.key(s, .F6, {.Ctrl, .Shift})
		testing.expect_value(t, app.keys_at, Keys_At.Inspector)
		// Escape gives it back to the list
		session.key(s, .Escape)
		testing.expect_value(t, app.keys_at, Keys_At.List)
	})
}

@(test)
test_keys_sidebar :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		// (the bookmarks alone: rows in the test's folder, in a known order)
		app.side_open = {.Recents = false, .Bookmarks = true, .Storage = false, .Network = false, .Places = false}
		append(&app.bookmarks, strings.clone(fs.join(dir, "Documents", context.temp_allocator)))
		append(&app.bookmarks, strings.clone(fs.join(dir, "Photos", context.temp_allocator)))
		session.frames(s, 2)
		point_at(t, tab, "notes.txt")
		session.frames(s, 1)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Sidebar)
		testing.expect_value(t, app.side_keys.cursor, 0)
		// the list's cursor stays while the sidebar has the keys
		session.key(s, .Down)
		session.key(s, .End)
		session.key(s, .Page_Down)
		testing.expect_value(t, app.side_keys.cursor, 1)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "notes.txt")
		// Enter: the place in the tab, the keyboard back to the list
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "Photos", context.temp_allocator))
		testing.expect_value(t, app.keys_at, Keys_At.List)
		// Ctrl+Enter: in a new tab
		p := current_panel(app)
		n := len(p.tabs)
		session.key(s, .F6)
		session.key(s, .Up)
		session.key(s, .Return, {.Ctrl})
		wait_read(s)
		testing.expect_value(t, len(p.tabs), n + 1)
		testing.expect_value(t, panel_tab(p).path, fs.join(dir, "Documents", context.temp_allocator))
	})
}

@(test)
test_keys_inspector_scroll :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"short.txt"})
		long := strings.repeat("a line of the long text\n", 400, context.temp_allocator)
		_ = os.write_entire_file(fs.join(dir, "long.txt", context.temp_allocator), transmute([]u8)long)
		s, app := start(t, {dir})
		tab := current_tab(app)
		point_at(t, tab, "long.txt")
		session.key(s, .Space)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 2)
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Text)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Inspector)
		before := session.get(s, "insp_text").view_off.y
		session.key(s, .Page_Down)
		session.advance(s, 500)
		after := session.get(s, "insp_text").view_off.y
		testing.expectf(t, after > before + 50, "scrolled a page: %v from %v", after, before)
		// (the list's cursor where it was)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "long.txt")
		// Home: back to the top
		session.key(s, .Home)
		session.advance(s, 500)
		testing.expectf(t, session.get(s, "insp_text").view_off.y < 1, "at the top: %v", session.get(s, "insp_text").view_off.y)
	})
}
