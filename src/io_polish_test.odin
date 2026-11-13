package classeur

// The interface's thread never waits for the disk: a rename, a new folder and the places are done by the workers and
// come back; while they run the interface keeps what it showed (the rename's field, the sidebar's list). The title and
// the first crumb of a tab on a share are read with its folder, not at each frame.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import tasks "gt:tasks"
import "gt:testkit"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// Held by a task put first in the edits' worker: what is asked after it waits until the test lets it go.
@(private = "file")
gate: sync.Sema

@(private = "file")
edits_hold :: proc(app: ^App) {
	tasks.add(&app.edit_pool, proc(data: rawptr) { sync.sema_wait((^sync.Sema)(data)) }, &gate)
}

@(private = "file")
edits_let_go :: proc() { sync.sema_post(&gate) }

// A rename is the worker's: the field stays open, the file keeps its name until the worker has done it; then the new
// name has the cursor, and the rename is a step of the undo.
@(test)
test_rename_on_the_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		point_at(t, tab, "notes.txt")
		edits_hold(app)
		session.key(s, .F2)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "todo.txt")
		session.key(s, .Return)
		session.frames(s, 2)
		testing.expect(t, app.rename.active && app.rename.waiting != 0, "the field waits for the worker's answer")
		testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "not renamed by the interface's thread")
		edits_let_go()
		wait_read(s)
		testing.expect(t, !app.rename.active, "the field closed")
		testing.expect(t, fs.exists(fs.join(dir, "todo.txt", context.temp_allocator)), "renamed")
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "todo.txt")
		testing.expect_value(t, len(app.undo), 1)
	})
}

// A name already there: the worker refuses it, the field stays with what was typed, selected, in the colour of an error.
@(test)
test_rename_refused_by_the_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		point_at(t, tab, "notes.txt")
		session.key(s, .F2)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "archive.zip")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, app.rename.active, "the field stays open")
		testing.expect(t, app.rename.refused, "the name refused")
		testing.expect_value(t, app.rename.waiting, 0)
		testing.expect_value(t, ui.line_edit_string(&app.rename.field), "archive.zip")
		testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "notes.txt is still there")
		testing.expect_value(t, len(app.undo), 0)
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.rename.active)
	})
}

// A new folder is made by the worker; when it is, its name is in the field.
@(test)
test_new_folder_on_the_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		edits_hold(app)
		session.key(s, .N, {.Ctrl, .Shift})
		session.frames(s, 2)
		testing.expect(t, !fs.exists(fs.join(dir, "New folder", context.temp_allocator)), "not made by the interface's thread")
		testing.expect(t, !app.rename.active, "no field before the folder is there")
		edits_let_go()
		wait_read(s)
		info, ok := fs.stat(fs.join(dir, "New folder", context.temp_allocator))
		testing.expect(t, ok && info.kind == .Directory, "made")
		testing.expect(t, app.rename.active, "named in place")
		testing.expect_value(t, app.rename.name, "New folder")
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "New folder")
		// named (its step of the undo follows it), then undone by the worker too
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "Fresh")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "Fresh", context.temp_allocator)), "named")
		testing.expect_value(t, len(app.undo), 1)
		session.key(s, .Z, {.Ctrl})
		wait_read(s)
		testing.expect(t, !fs.exists(fs.join(dir, "Fresh", context.temp_allocator)), "undone")
		testing.expect_value(t, len(app.redo), 1)
	})
}

// The places read again: the sidebar keeps its list until the worker's comes.
@(test)
test_places_on_the_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		n := len(app.places)
		testing.expect(t, n > 0, "the places read at the start")
		places_load(app)
		testing.expect_value(t, len(app.places), n)
		testing.expect_value(t, app.answers_due, 1)
		wait_read(s)
		testing.expect_value(t, len(app.places), n)
		testing.expect_value(t, app.answers_due, 0)
	})
}

// A tab on a share's root is named by the share, its first crumb is the share's URI: both read with the folder. The
// mounts changed meanwhile (here: gvfs's folder elsewhere) change nothing until the folder is read again.
@(test)
test_share_name_read_with_the_folder :: proc(t: ^testing.T) {
	when ODIN_OS != .Linux { return }
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		run := strings.clone(testkit.temp_folder(t, "classeur_run"))
		defer delete(run)
		share := fs.join(run, "gvfs/smb-share:server=nas,share=docs")
		defer delete(share)
		_ = os.make_directory_all(share)
		before := strings.clone(os.get_env("XDG_RUNTIME_DIR", context.temp_allocator))
		defer { os.set_env("XDG_RUNTIME_DIR", before); delete(before) }
		os.set_env("XDG_RUNTIME_DIR", run)
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		testing.expect_value(t, tab.share_root, "")
		tab_go(app, tab, "smb://nas/docs")
		wait_read(s)
		testing.expect_value(t, tab.path, share)
		testing.expect_value(t, tab.share_root, share)
		testing.expect_value(t, tab_title(app, tab), "docs on nas")
		// (no share there now: a lookup at each frame would lose the name)
		os.set_env("XDG_RUNTIME_DIR", dir)
		session.frames(s, 3)
		testing.expect_value(t, tab_title(app, tab), "docs on nas")
		crumbs := home_crumbs(app, tab)
		testing.expect(t, len(crumbs) > 0 && crumbs[0].name == "smb://nas/docs", "the first crumb, the share's URI")
		// read again: the mounts as they are now
		tab_load(app, tab)
		wait_read(s)
		testing.expect_value(t, tab.share_root, "")
		testing.expect_value(t, tab_title(app, tab), "smb-share:server=nas,share=docs")
	})
}
