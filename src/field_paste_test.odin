package classeur

// A paste in a field asks the clipboard and does not wait: the text comes with a later frame's events, which the window's
// input (app_input) passes on to the interface, and the field that asked takes it.

import "base:runtime"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"

@(test)
test_a_field_pastes_the_clipboard_s_text :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt", "report.pdf"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)

		// the rename in place: over the name, selected
		testing.expect(t, folder_cursor_to_name(&tab.folder, "a.txt"))
		folder_pick(&tab.folder, tab.folder.cursor)
		session.key(s, .F2)
		testing.expect(t, app.rename.active)
		session.key(s, .A, {.Ctrl})
		session.set_clipboard(s, "pasted.txt")
		session.key(s, .V, {.Ctrl})
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return ui.field_string(&app.rename.field) == "pasted.txt" }, "the rename's paste")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.rename.active)

		// the filter
		session.key(s, .F, {.Ctrl})
		session.set_clipboard(s, "rep")
		session.key(s, .V, {.Ctrl})
		session.wait_until(s, tab, proc(s: ^session.Session, tab: ^Tab) -> bool { return ui.field_string(&tab.filter) == "rep" }, "the filter's paste")
	})
}
