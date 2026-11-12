package classeur

// The dialogs' look: the batch rename's case as a segmented control, the name-taken question with both files' size and
// date.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// The case is the toolkit's segmented control (its pills): UPPER clicked, the new names read in upper case.
@(test)
test_batch_case_segmented :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		for name in ([]string{"notes.txt", "report 2.pdf"}) {
			testing.expect(t, folder_cursor_to_name(&tab.folder, name))
			folder_pick(&tab.folder, tab.folder.cursor, toggle = true)
		}
		session.key(s, .F2)
		session.frames(s, 2)
		testing.expect(t, app.batch.open)
		session.wait_box(s, "seg2")
		// (pills: the segments sit in the control's inner track, not words in a line)
		testing.expect(t, session.find(s, "seg_inner") != nil, "a segmented control of pills")
		session.click(s, "seg2")
		session.frames(s, 2)
		testing.expect_value(t, app.batch.casing, Batch_Case.Upper)
		testing.expect(t, session.find_text(s, "NOTES.TXT") != nil, "the preview in upper case")
		session.key(s, .Escape)
		session.frames(s, 1)
	})
}

// The name-taken question shows the file there and the one copied, each its size and date, the newer one marked.
@(test)
test_conflict_files :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		// an older notes.txt already in Documents
		there := fs.join(dir, "Documents/notes.txt", context.temp_allocator)
		_ = os.write_entire_file(there, transmute([]u8)string("an older one\n"))
		old := time.unix(1_000_000_000, 0)
		_ = os.change_times(there, old, old)
		s, app := start(t, {dir})
		tab := current_tab(app)

		point_at(t, tab, "notes.txt")
		session.key(s, .C, {.Ctrl})
		point_at(t, tab, "Documents")
		session.key(s, .Return)
		wait_read(s)
		session.key(s, .V, {.Ctrl})
		session.wait_until(s, proc(s: ^session.Session) -> bool { return job_asking((^App)(s.user)) != nil }, "the question")
		session.wait_box(s, "both")
		session.frames(s, 2)

		line := session.find_text(s, "There: ")
		testing.expect(t, line != nil, "the file there")
		if line != nil { testing.expectf(t, strings.contains(ui.box_text(line), "2001"), "its date (%s)", ui.box_text(line)) }
		testing.expect(t, session.find_text(s, "Copied: ") != nil, "the file copied")
		newer := session.find(s, "newer")
		testing.expect(t, newer != nil, "the newer one marked")
		if newer != nil { testing.expect(t, newer.parent != nil && newer.parent.name == "coming", "the copied one is the newer") }
		// (its four choices still on one line, in the dialog)
		if r, b := session.find(s, "replace"), session.find(s, "buttons"); r != nil && b != nil { testing.expectf(t, r.rect.max.x <= b.rect.max.x + 0.5, "Replace in the dialog (%v, %v)", r.rect, b.rect) }

		session.click(s, "both")
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Documents/notes 2.txt", context.temp_allocator)), "kept both")
	})
}
