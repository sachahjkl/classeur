package classeur

// In-process windows opened from a tab or New window share host.Shared and move the ^Tab directly without spawning a
// new OS process or re-reading the folder; the Setup's facts come after the first frame.

import "base:runtime"
import "core:os"
import "core:testing"
import config "gt:config"
import "gt:platform"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import prefs_page "gt:prefs_page"
import "fs"

// Tearing off a tab opens an in-process window on the same App_Hub and moves the ^Tab with its loaded listing intact.
@(test)
test_tab_window_in_process :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		p := app.panels[0]
		docs := fs.join(dir, "Documents", context.temp_allocator)
		tab_open(app, p, docs, 1)
		p.active = 1
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect_value(t, len(app.hub.windows), 1)
		orig_tab := p.tabs[1]
		orig_entries := len(orig_tab.folder.listing.entries)
		testing.expect(t, orig_tab.folder.loaded && orig_entries > 0, "tab already loaded before tear-off")

		act_tab_window(app)
		// Moved immediately without spawning a worker or another OS process.
		testing.expect_value(t, len(p.tabs), 1)
		testing.expect_value(t, len(app.hub.windows), 2)
		win2 := app.hub.windows[1]
		testing.expect(t, win2.shared == app.shared, "second window shares host.Shared")
		testing.expect(t, win2.standalone, "torn-off window is standalone")
		moved := current_tab(win2)
		testing.expect(t, moved == orig_tab, "exact ^Tab moved into the new window")
		testing.expect(t, moved.folder.loaded && !moved.loading, "listing stays loaded with no disk re-read")
		testing.expect_value(t, len(moved.folder.listing.entries), orig_entries)
		testing.expect(t, moved.folder.group_tz == win2.tz, "timezone pointer updated to destination window")

		// Dragging that tab back into window 1 through hub.handoff moves the exact ^Tab back without reloading.
		app.hub.handoff = tab_detach(win2, win2.panels[0], 0)
		app.hub.handoff_id = moved.id
		app.hub.handoff_from = win2.window_id
		data: platform.Drag_Data
		append(&data.custom, platform.Drag_Entry{TAB_MIME, tab_mime_data(os.get_pid(), win2.window_id, moved.id, moved.path)})
		defer delete(data.custom)
		session.frames(s, 2)
		at := (app.tab_rects_last[0].rect.min + app.tab_rects_last[0].rect.max) * 0.5
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Move})
		platform.drop_inject(app.main.win, .Drop_Over, at, nil, {.Move})
		session.frames(s, 2)
		platform.drop_inject(app.main.win, .Drop, at, nil, {.Move})
		session.frames(s, 2)
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect(t, app.hub.handoff == nil, "handoff claimed by target window")
		testing.expect(t, current_tab(app) == moved, "exact ^Tab adopted back into window 1")
		testing.expect(t, !moved.loading && moved.folder.loaded, "no reload on same-process drop")

		// New window (Ctrl+N) opens another in-process window on the home folder.
		act_app_new_window(app)
		testing.expect_value(t, len(app.hub.windows), 3)
		testing.expect(t, app.hub.windows[2].shared == app.shared, "new window shares host.Shared")
	})
}

// A window that fails to open: error message shown, tab stays in its panel, and a later tear-off succeeds.
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
		testing.expect(t, find_tab(app, id) != nil, "the tab stays")
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect_value(t, len(app.hub.windows), 1)
		testing.expect_value(t, app.status, "No window could be started.")
		app.window_fails = false
		act_tab_window(app)
		testing.expect(t, find_tab(app, id) == nil, "the tab gone to its window")
		testing.expect_value(t, len(app.hub.windows), 2)
	})
}

// The install: read on a task at a real start only (app_run); a test's window reads nothing of the person's and offers
// nothing, and its frames run the install's machinery all the same.
@(test)
test_setup_not_read_by_tests :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		session.frames(s, 3)
		testing.expect(t, !app.install.reading && !app.install.known, "nothing read")
		// (no reading: the switches of the menu and the session stay hidden, nothing written to the desktop)
		names := [?]string{prefs_page.MENU_PREF, prefs_page.AUTOSTART_PREF}
		for name in names {
			r := config.ref_of(&app.prefs, name)
			testing.expect(t, r != config.NO_REF && config.entry(&app.prefs, r).def.hidden, name)
		}
		testing.expect(t, !prefs_page.install_open_now(&app.install), "nothing offered to the tests")
	})
}
