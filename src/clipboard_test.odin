package classeur

// What the clipboard gives without the window waiting for it: a paste asks for the files and its job starts when they
// come; the answer of another file manager's cut moves; an answer nothing asked for does nothing; the batch rename's
// names come the same way.

import "base:runtime"
import "core:strings"
import "core:testing"
import "gt:platform"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

// Ctrl+V's action asks and returns: no job, nothing copied. The files come with the window's next events, the copy then.
@(test)
test_paste_asks_and_does_not_wait :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Dest/", "a.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		point_at(t, tab, "a.txt")
		session.key(s, .C, {.Ctrl})
		point_at(t, tab, "Dest")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Dest")

		jobs := len(app.jobs.list)
		act_paste(app)
		testing.expect(t, app.paste.id != 0, "the files are asked for")
		testing.expect_value(t, len(app.jobs.list), jobs)
		testing.expect(t, !fs.exists(fs.join(dir, "Dest/a.txt", context.temp_allocator)), "nothing copied in the call")
		wait_jobs(s)
		testing.expect_value(t, app.paste.id, u64(0))
		testing.expect(t, fs.exists(fs.join(dir, "Dest/a.txt", context.temp_allocator)), "copied when the files came")
		testing.expect(t, fs.exists(fs.join(dir, "a.txt", context.temp_allocator)), "the original stays")
	})
}

// Another file manager's cut, as the clipboard's answer brings it: the files move. An answer that no paste waits for
// does nothing.
@(test)
test_paste_of_another_program_s_cut :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Dest/", "b.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		source := fs.join(dir, "b.txt", context.temp_allocator)
		dest := fs.join(dir, "Dest", context.temp_allocator)

		// (an id far from the window's own requests)
		LATE :: u64(1) << 40
		platform.inject_event(app.main.win, {kind = .Clipboard_Data, clipboard = {id = LATE, format = .Files, ok = true, cut = true, files = {source}}})
		session.frames(s, 3)
		testing.expect_value(t, len(app.jobs.list), 0)
		testing.expect(t, fs.exists(source), "an answer nothing asked for moves nothing")

		ASKED :: LATE + 1
		app.paste = {id = ASKED, dir = strings.clone(dest)}
		platform.inject_event(app.main.win, {kind = .Clipboard_Data, clipboard = {id = ASKED, format = .Files, ok = true, cut = true, files = {source}}})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dest, "b.txt", context.temp_allocator)), "moved into Dest")
		testing.expect(t, !fs.exists(source), "and gone from where it was")

		// an empty clipboard: said, nothing done
		app.paste = {id = ASKED + 1, dir = strings.clone(dest)}
		platform.inject_event(app.main.win, {kind = .Clipboard_Data, clipboard = {id = ASKED + 1, format = .Files}})
		session.frames(s, 3)
		testing.expect_value(t, app.paste.id, u64(0))
		testing.expect(t, strings.contains(app.status, "no files"), "the clipboard holds no files")
	})
}

// "Names from the clipboard" asks for the text; the names are a line each when it comes.
@(test)
test_batch_names_from_the_clipboard :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt", "b.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder
		testing.expect(t, folder_cursor_to_name(f, "a.txt"))
		folder_pick(f, f.cursor)
		testing.expect(t, folder_cursor_to_name(f, "b.txt"))
		folder_pick(f, f.cursor, toggle = true)
		batch_open(app, tab)
		session.frames(s, 2)
		testing.expect(t, app.batch.open, "the batch rename opens")

		platform.set_clipboard(app.main.win, "one\ntwo\n")
		session.click_text(s, "Names from the clipboard")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).batch.list) == 2 }, "the names")
		testing.expect_value(t, app.batch.list[0], "one")
		testing.expect_value(t, app.batch.list[1], "two")
		testing.expect_value(t, app.batch.list_asked, u64(0))
		session.key(s, .Escape)
	})
}
