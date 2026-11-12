package classeur

// What starts a process or reads the install runs on the workers, its answer landing later: a tab torn off to a window of
// its own leaves once its window has started, and stays when it could not; the Setup's facts come after the first frame.

import "base:runtime"
import "core:sync"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

@(private = "file")
launched :: proc(s: ^session.Session) -> bool { return sync.atomic_load(&(^App)(s.user).launched_on) != 0 }

// A tab torn off: its window started by a worker, the tab still here until that lands; torn again meanwhile, one window.
@(test)
test_tab_window_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		p := app.panels[0]
		tab_open(app, p, fs.join(dir, "Documents", context.temp_allocator), 1)
		p.active = 1
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 2)
		id := p.tabs[1].id
		opened := len(app.opened)
		act_tab_window(app)
		act_tab_window(app)
		testing.expect_value(t, len(app.opened), opened + 1)
		testing.expect(t, find_tab(app, id) != nil, "the tab stays while its window starts")
		session.wait_until(s, launched, "the worker's start")
		testing.expect(t, sync.atomic_load(&app.launched_on) != sync.current_thread_id(), "the window started by a worker")
		session.wait_until(s, id, proc(s: ^session.Session, id: u64) -> bool { return find_tab((^App)(s.user), id) == nil }, "the tab gone to its window")
		testing.expect_value(t, len(p.tabs), 1)
	})
}

// A window that does not start: said, and the tab stays (and may be torn off again).
@(test)
test_tab_window_fails :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		p := app.panels[0]
		tab_open(app, p, fs.join(dir, "Documents", context.temp_allocator), 1)
		p.active = 1
		wait_read(s)
		id := p.tabs[1].id
		app.window_fails = true
		act_tab_window(app)
		session.wait_until(s, launched, "the worker's start")
		session.wait_until(s, id, proc(s: ^session.Session, id: u64) -> bool {
			q := find_tab((^App)(s.user), id)
			return q == nil || !q.tearing
		}, "the start's answer")
		testing.expect(t, find_tab(app, id) != nil, "the tab stays")
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect_value(t, app.status, "No window could be started.")
		// (once the answer is in, a tear starts again)
		app.window_fails = false
		sync.atomic_store(&app.launched_on, 0)
		act_tab_window(app)
		session.wait_until(s, id, proc(s: ^session.Session, id: u64) -> bool { return find_tab((^App)(s.user), id) == nil }, "the tab gone to its window")
	})
}

// The Setup's offer: its facts read on a worker, known only once they land (headless: nothing of the person's is read,
// nothing is offered).
@(test)
test_setup_facts_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		testing.expect(t, !app.setup_known)
		setup_offer(app, false)
		testing.expect(t, !app.setup_known, "not read on the interface's thread")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).setup_known }, "the Setup's facts")
		testing.expect(t, !app.setup.open, "nothing offered to the tests")
	})
}
