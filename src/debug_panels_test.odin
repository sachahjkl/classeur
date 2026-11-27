package classeur

import "base:runtime"
import "core:strings"
import "core:testing"
import "gt:debug"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// Every panel lists on a bare State (no window, no tab, no updater) and its values take a tool's set.
@(test)
test_debug_panels_bare :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	s: ui.State
	ui.init(&s, nil, nil)
	defer ui.destroy(&s)
	app := new(App)
	defer free(app)
	app.headless = true
	app.check_ms = CHECK_ANIM_MS
	debug_panels_register(&s, app)
	sb := strings.builder_make(context.temp_allocator)
	debug.list(&s, &sb)
	text := strings.to_string(sb)
	for name in ([?]string{"Tabs", "Selection", "Thumbnails", "Watcher", "Undo", "File search", "Jobs", "Updates", "Look"}) {
		testing.expectf(t, strings.contains(text, name), "the panel %s is listed", name)
	}
	testing.expect_value(t, debug.set(&s, "Look/check ms", "500"), "")
	testing.expect_value(t, app.check_ms, f32(500))
	testing.expect_value(t, debug.set(&s, "Thumbnails/system thumbnails", "true"), "")
	testing.expect(t, app.system_thumbs, "the system's thumbnails turned on")
	// (an act with nothing to act on says so, as the command does)
	testing.expect_value(t, debug.press(&s, "Undo/Undo"), "")
	testing.expect_value(t, app.status, "Nothing to undo.")
	delete(app.status)
}

// The acts do the program's own work on a real window: a refused folder shown and read again, the selection, the
// index of the folder, the tick's time.
@(test)
test_debug_panels_acts :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		st := &app.main.state
		tab := current_tab(app)
		f := &tab.folder

		testing.expect_value(t, debug.press(st, "Tabs/Simulate a refused folder"), "")
		session.frames(s, 1)
		testing.expect_value(t, f.listing.error, fs.Error.Denied)
		testing.expect(t, session.find_text(s, "Try again") != nil, "the refused folder's state")
		testing.expect_value(t, debug.press(st, "Tabs/Read again"), "")
		wait_read(s)
		testing.expect_value(t, f.listing.error, fs.Error.None)

		testing.expect_value(t, debug.press(st, "Selection/Select all"), "")
		session.frames(s, 1)
		testing.expect_value(t, len(f.selected), len(f.shown))
		testing.expect_value(t, debug.press(st, "Selection/Select none"), "")
		session.frames(s, 1)
		testing.expect_value(t, len(f.selected), 0)

		testing.expect_value(t, debug.press(st, "File search/Index the folder shown"), "")
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			d := &(^App)(s.user).deep
			return d.fs_index != 0 && !d.opening && d.done
		}, "the folder indexed")
		testing.expect_value(t, app.deep.root, tab.path)
		testing.expect_value(t, debug.press(st, "File search/Drop the index"), "")
		session.frames(s, 1)
		testing.expect_value(t, app.deep.root, "")

		// (the tick's time at 0: a row checks at once, animations on)
		ui.set_animations(st, .On)
		testing.expect_value(t, debug.set(st, "Look/check ms", "0"), "")
		folder_pick(f, 0)
		folder_pick(f, 1, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, st.anims[check_key(tab, 1)].value, f32(1))
	})
}
