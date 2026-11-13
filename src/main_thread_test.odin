package classeur

// The interface's thread never waits: a program started (the system's application, a terminal) and the settings written
// run on the workers; whether a folder is in an archive is the read's answer, kept in its tab.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import config "gt:config"
import "gt:testkit"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

// Opening a file with the system's application, and a terminal: started by a worker, not by the interface's thread
// (headless: noted at once, nothing started, the worker's task runs all the same).
@(test)
test_open_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		launched :: proc(s: ^session.Session) -> bool { return sync.atomic_load(&(^App)(s.user).launched_on) != 0 }
		point_at(t, tab, "notes.txt")
		act_open_system(app)
		testing.expect(t, len(app.opened) == 1 && fs.base(app.opened[0]) == "notes.txt", "noted")
		session.wait_until(s, launched, "the worker's start")
		testing.expect(t, sync.atomic_load(&app.launched_on) != sync.current_thread_id(), "the application started by a worker")
		sync.atomic_store(&app.launched_on, 0)
		act_terminal(app)
		testing.expect(t, strings.has_prefix(app.opened[len(app.opened) - 1], "terminal:"), "noted")
		session.wait_until(s, launched, "the worker's start")
		testing.expect(t, sync.atomic_load(&app.launched_on) != sync.current_thread_id(), "the terminal started by a worker")
	})
}

// A preference changed: written by a worker, on disk once it is done, read back as it was set (another version's
// preference kept).
@(test)
test_prefs_written_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		dir := strings.clone(testkit.temp_folder(t, "classeur_prefs"))
		defer delete(dir)
		file := fs.join(dir, ".session")
		defer delete(file)
		app := app_open({folders = {dir}, headless = true, session = file})
		testing.expect(t, app != nil)
		if app == nil { return }
		defer app_close(app)
		_ = config.set_from_string(&app.prefs, "other.version", "kept", .User)
		pref_set_bool(app, "files.show_hidden", true)
		// (handed to the writer's thread by a frame: written by it, the frame waits for nothing)
		// (not in the temporary memory: each round of the loop frees it)
		path := strings.concatenate({file, ".prefs"})
		defer delete(path)
		for _ in 0 ..< 2000 {
			app_frame(app)
			if data, err := os.read_entire_file(path, context.temp_allocator); err == nil && strings.contains(string(data), "files.show_hidden") { break }
			time.sleep(time.Millisecond)
		}
		testing.expect(t, os.exists(path), "on disk")
		q := config.prefs_make()
		defer config.prefs_destroy(&q)
		_ = config.register(&q, PREF_DEFS[:])
		_, problems := config.load_file(&q, path, .User)
		defer delete(problems)
		testing.expect(t, config.bool_of(&q, "files.show_hidden"), "the change on disk")
		text, ok := config.user_text(&q, "other.version")
		testing.expect(t, ok && text == "kept", "another version's preference kept")
	})
}

// A tab's folder in a zip is known read-only from its read's answer: a write is refused at once, nothing is asked of the
// edits' worker; out of the archive, the tab writes again and a zip opens as a folder.
@(test)
test_archive_known_from_the_read :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		zip := fs.join(dir, "real.zip", context.temp_allocator)
		testing.expect(t, os.write_entire_file(zip, stored_zip({{"inner/hello.txt", "hello"}})) == nil)
		s, app := start(t, {zip})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		testing.expect_value(t, tab.path, zip)
		testing.expect(t, tab.in_archive, "the archive's top")
		act_new_folder(app)
		testing.expect_value(t, app.answers_due, 0)
		testing.expect_value(t, app.status, fs.ERROR_TEXT[.Read_Only])
		tab_go(app, tab, fs.join(zip, "inner", context.temp_allocator))
		wait_read(s)
		testing.expect(t, tab.in_archive, "a folder of the archive")
		tab_go(app, tab, dir)
		wait_read(s)
		testing.expect(t, !tab.in_archive, "a folder outside")
		testing.expect(t, !read_only_here(app, tab), "writes outside")
		testing.expect(t, folder_cursor_to_name(&tab.folder, "real.zip"))
		e := folder_cursor_entry(&tab.folder)
		testing.expect(t, e != nil && opens_as_folder(tab, e^), "a zip outside of an archive opens as a folder")
	})
}
