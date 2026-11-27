package classeur

import "base:runtime"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"

// A row's box checks on its way, its fill then its tick; unchecked, its icon comes back at once; with the animations off
// it checks at once.
@(test)
test_check_animates :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		progress :: proc(app: ^App, tab: ^Tab, row: int) -> f32 { return app.main.state.anims[check_key(tab, row)].value }

		ui.set_animations(&app.main.state, .On)
		folder_pick(&tab.folder, 0)
		folder_pick(&tab.folder, 1, {.Ctrl})
		session.frames(s, 3)   // (a tween's first frame starts it: it moves from the next)
		p := progress(app, tab, 1)
		testing.expectf(t, p > 0 && p < 1, "on its way after one frame: %v", p)
		// (bounded: the anim settles within a second of frames)
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			app := (^App)(s.user)
			return app.main.state.anims[check_key(current_tab(app), 1)].value == 1
		}, "checked")
		folder_pick(&tab.folder, 2)
		session.frames(s, 1)
		testing.expect_value(t, progress(app, tab, 1), f32(0))   // (unchecked: the icon at once)

		ui.set_animations(&app.main.state, .Off)
		folder_pick(&tab.folder, 3, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, progress(app, tab, 3), f32(1))
	})
}
