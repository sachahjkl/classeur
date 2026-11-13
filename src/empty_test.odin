package classeur

// The views' empty states: what is wrong said, and a button for what can be done about it.

import "base:runtime"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// An empty folder: said, and its New folder makes one.
@(test)
test_empty_folder_state :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Empty/"})
		s, app := start(t, {fs.join(dir, "Empty", context.temp_allocator)})
		context.allocator = runtime.heap_allocator()
		testing.expect(t, session.find_text(s, "This folder is empty") != nil, "said")
		session.click(s, "empty_action0")
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "Empty/New folder", context.temp_allocator)), "New folder made one")
		_ = app
	})
}

// A filter that leaves no row: said with its letters, and its button clears it.
@(test)
test_filter_empty_state :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		session.type_text(s, "zzq")
		session.frames(s, 2)
		testing.expect_value(t, len(tab.folder.shown), 0)
		testing.expect(t, session.find_text(s, "No name matches") != nil, "said")
		session.click(s, "empty_action0")
		session.frames(s, 2)
		testing.expect_value(t, ui.line_edit_string(&tab.filter), "")
		testing.expect(t, len(tab.folder.shown) > 0, "every row again")
	})
}

// Only hidden files: said, and its button shows them.
@(test)
test_hidden_empty_state :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {".hidden"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		testing.expect(t, session.find_text(s, "Only hidden files are here") != nil, "said")
		session.click(s, "empty_action0")
		session.frames(s, 2)
		testing.expect_value(t, len(current_tab(app).folder.shown), 1)
	})
}

// Space in the empty filter opens the inspector, as in the list, and types nothing; in a filter with letters it is a space.
@(test)
test_space_in_empty_filter :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		session.key(s, .F, {.Ctrl})
		session.frames(s, 2)
		testing.expect(t, !app.inspector.open)
		session.type_text(s, " ")
		session.frames(s, 2)
		testing.expect_value(t, ui.line_edit_string(&tab.filter), "")
		testing.expect(t, app.inspector.open, "Space: the inspector")
		session.type_text(s, " ")
		session.frames(s, 2)
		testing.expect(t, !app.inspector.open, "Space again: closed")
		session.type_text(s, "re p")
		session.frames(s, 2)
		testing.expect_value(t, ui.line_edit_string(&tab.filter), "re p")
	})
}
