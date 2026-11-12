package classeur

// Escape during a bookmark's drag; the relative dates past midnight.

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"
import "core:time/datetime"
import config "gt:config"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// Escape ends a bookmark's drag: the bookmarks keep their order, the press held moves nothing more and its release
// on the row opens nothing.
@(test)
test_escape_ends_bookmark_drag :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Documents/", "Photos/", "notes.txt"})
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		append(&app.bookmarks, strings.clone(fs.join(dir, "Documents", context.temp_allocator)))
		append(&app.bookmarks, strings.clone(fs.join(dir, "Photos", context.temp_allocator)))
		session.frames(s, 3)
		tab := current_tab(app)
		first := session.get(s, "bookmark0").rect
		second := session.get(s, "bookmark1").rect
		from := (first.min + first.max) * 0.5
		to := [2]f32{from.x, second.max.y - 2}
		session.press(s, from)
		session.move(s, from + {0, 12})
		session.move(s, to)
		session.frames(s, 2)
		testing.expect(t, app.bm_dragging, "a bookmark's drag")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.bm_dragging, "Escape ends it")
		// (still held: moved, it starts no drag again; let go on its own row, it is no click)
		session.move(s, to + {0, -4})
		session.frames(s, 2)
		testing.expect(t, !app.bm_dragging, "no drag again till the release")
		session.move(s, from)
		session.release(s, from)
		session.frames(s, 3)
		testing.expect_value(t, fs.base(app.bookmarks[0]), "Documents")
		testing.expect_value(t, fs.base(app.bookmarks[1]), "Photos")
		testing.expect_value(t, tab.path, dir)
		testing.expect(t, !app.bm_cancelled, "the release ends the cancelled press")
	})
}

// The milliseconds to the next local midnight, from a few times of the day.
@(test)
test_ms_to_midnight :: proc(t: ^testing.T) {
	testing.expect_value(t, ms_to_midnight({0, 0, 0, 0}), 86_400_000)
	testing.expect_value(t, ms_to_midnight({12, 0, 0, 0}), 43_200_000)
	testing.expect_value(t, ms_to_midnight({21, 16, 30, 250_000_000}), 9_809_750)
	testing.expect_value(t, ms_to_midnight({23, 59, 59, 0}), 1000)
	testing.expect_value(t, ms_to_midnight({23, 59, 59, 999_900_000}), 1)
}

// The relative dates count from app.today: once the day turns, today's date reads "Yesterday". A relative date shown
// asks the loop to wake by the next midnight.
@(test)
test_relative_date_after_midnight :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt"})
		_, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		_ = config.set_from_string(&app.prefs, "files.date_format", "relative", .User)
		settings_apply(app)
		ns := time.now()._nsec
		dt, ok := local_datetime(app.tz, ns)
		testing.expect(t, ok)
		// (the day read again: the wake asked)
		app.today_frame = app.frame + 1
		_ = date_text(app, ns)
		wake := ui.wake_ms(&app.main.state)
		testing.expectf(t, wake > 0 && wake <= 86_400_000 + MIDNIGHT_MARGIN_MS, "a wake by the next midnight: %d", wake)

		app.today_frame, app.today = app.frame, dt.date
		testing.expect_value(t, date_text(app, ns), fmt.tprintf("Today %02d:%02d", dt.hour, dt.minute))
		next, _ := datetime.add_days_to_date(dt.date, 1)
		app.today = next
		testing.expect_value(t, date_text(app, ns), fmt.tprintf("Yesterday %02d:%02d", dt.hour, dt.minute))
	})
}
