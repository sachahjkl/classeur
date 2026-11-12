package classeur

// The inspector's cases besides one item read: several selected, a picture's pixels and place, a text cut, a folder's
// rows opened, nothing under the cursor.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "gt:png"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "fs"

@(private = "file")
polish_ready :: proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }

// The cursor on `name`, it alone selected, and the inspector open on it.
@(private = "file")
polish_inspect :: proc(t: ^testing.T, s: ^session.Session, tab: ^Tab, name: string, loc := #caller_location) {
	testing.expect(t, folder_cursor_to_name(&tab.folder, name), loc = loc)
	folder_pick(&tab.folder, tab.folder.cursor)
	session.key(s, .Space)
	testing.expect(t, (^App)(s.user).inspector.open, loc = loc)
	session.wait_until(s, polish_ready, "the inspector", loc = loc)
	session.frames(s, 2)
}

@(test)
test_inspector_summary :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"one/", "two/", "three.txt"})
		s, app := start(t, {dir})
		tab := current_tab(app)
		polish_inspect(t, s, tab, "three.txt")
		folder_select_all(&tab.folder)
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "3 items") != nil, "how many are selected")
		testing.expect(t, session.find_text(s, "2 folders · 1 file") != nil, "of which kinds")
		testing.expect(t, session.find(s, "insp_s2") != nil, "their list")
		testing.expect(t, session.find(s, "insp_close") != nil, "the close button")
	})
}

@(test)
test_inspector_picture :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"notes.txt"})
		// (wider than INSPECTOR_PICTURE_PX: what is shown is shrunk, the head says the file's own pixels)
		w, h := 2000, 120
		rgba := make([]u8, w * h * 4, context.temp_allocator)
		for i in 0 ..< w * h { rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], rgba[i * 4 + 3] = 40, 120, 200, 255 }
		_ = os.write_entire_file(fs.join(dir, "wide.png", context.temp_allocator), png.encode(rgba, w, h, .Fast, context.temp_allocator))
		s, app := start(t, {dir})
		tab := current_tab(app)
		polish_inspect(t, s, tab, "wide.png")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Picture)
		testing.expect_value(t, app.inspector.pixels, [2]int{2000, 120})
		testing.expect(t, app.inspector.size.x <= INSPECTOR_PICTURE_PX, "shrunk")
		testing.expect(t, session.find_text(s, "2000 × 120") != nil, "its pixels in the head")
		// (at the top of its room, as tall as it is fitted: no tall box that centres it)
		pic := session.get(s, "insp_pic")
		pane := session.get(s, "inspector")
		pic_h := pic.rect.max.y - pic.rect.min.y
		pane_h := pane.rect.max.y - pane.rect.min.y
		testing.expectf(t, pic_h < pane_h * 0.3, "the picture's box is as tall as it: %v of %v", pic_h, pane_h)
	})
}

@(test)
test_inspector_text_cut :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"short.txt"})
		long := strings.repeat("a line of the long text\n", 4000, context.temp_allocator)   // (96 000 bytes)
		_ = os.write_entire_file(fs.join(dir, "long.txt", context.temp_allocator), transmute([]u8)long)
		s, app := start(t, {dir})
		tab := current_tab(app)
		polish_inspect(t, s, tab, "long.txt")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Text)
		testing.expect(t, app.inspector.cut, "cut")
		testing.expect_value(t, len(app.inspector.text), INSPECTOR_TEXT_BYTES)
		testing.expect(t, session.find_text(s, "The first 64 KB are shown.") != nil, "the note")
		// a short text: no note
		context.allocator = runtime.heap_allocator()
		folder_cursor_to_name(&tab.folder, "short.txt")
		folder_pick(&tab.folder, tab.folder.cursor)
		session.frames(s, 1)
		session.wait_until(s, polish_ready, "the inspector")
		session.frames(s, 2)
		testing.expect(t, !app.inspector.cut, "whole")
		testing.expect(t, session.find(s, "insp_cut") == nil, "no note")
	})
}

@(test)
test_inspector_folder_rows :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"outer/", "outer/inner/", "notes.txt"})
		s, app := start(t, {dir})
		tab := current_tab(app)
		polish_inspect(t, s, tab, "outer")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Folder)
		// a double click on its row: the tab goes there
		session.click(s, "insp_e0", count = 2)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(fs.join(dir, "outer", context.temp_allocator), "inner", context.temp_allocator))
	})
}

@(test)
test_inspector_nothing :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"empty/"})
		s, app := start(t, {fs.join(dir, "empty", context.temp_allocator)})
		session.key(s, .Space)
		testing.expect(t, app.inspector.open)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "insp_close") != nil, "the close button")
		testing.expect(t, session.find_text(s, "This folder is empty.") != nil, "said")
		session.click(s, "insp_close")
		testing.expect(t, !app.inspector.open, "closed")
	})
}
