package classeur

// The menus of the rows and of the sidebar, the trash's commands, drops on the path and spring-open: driven as a person
// does, on folders made for the test (and a trash of the test's own, never the person's).

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "gt:platform"
import "gt:testkit"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

@(private = "file")
FILES :: [?]string{"Documents/", "Photos/", "notes.txt", "report.pdf", "archive.zip", "Documents/letter.odt"}

@(private = "file")
fixture :: proc(t: ^testing.T) -> string {
	files := FILES
	return make_fixture(t, files[:])
}

// The row's menu with three items selected: Rename stays on, says how many, and opens the batch rename (as F2 does).
@(test)
test_menu_rename_several :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := fixture(t)
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		folder_pick(&tab.folder, 2)
		folder_pick(&tab.folder, 3, toggle = true)
		folder_pick(&tab.folder, 4, toggle = true)
		testing.expect_value(t, tab.folder.count, 3)
		entry_menu_open(app, tab, {300, 200})
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Rename 3 items…") != nil, "titled with the count")
		session.click_text(s, "Rename 3 items")
		session.frames(s, 2)
		testing.expect(t, app.batch.open, "the batch rename opens")
		session.key(s, .Escape)
	})
}

// Paste into this folder, on a folder's row: the file goes into that folder, not into the one shown.
@(test)
test_menu_paste_into :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := fixture(t)
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		point_at(t, tab, "notes.txt")
		session.key(s, .C, {.Ctrl})
		point_at(t, tab, "Photos")
		entry_menu_open(app, tab, {300, 200})
		session.frames(s, 3)
		session.click_text(s, "Paste into this folder")
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/notes.txt", context.temp_allocator)), "pasted into Photos")
		testing.expect(t, !fs.exists(fs.join(dir, "notes 2.txt", context.temp_allocator)), "not into the folder shown")
	})
}

// In the trash (the test's own): Put back returns an item where it was, Empty the trash deletes the rest after the
// question, records and all.
@(test)
test_trash_put_back_and_empty :: proc(t: ^testing.T) {
	when ODIN_OS == .Linux {
		unwatched.run(t, proc(t: ^testing.T) {
			dir := fixture(t)
			data := fs.join(dir, ".data", context.temp_allocator)
			before := strings.clone(os.get_env("XDG_DATA_HOME", context.temp_allocator), runtime.heap_allocator())
			defer { os.set_env("XDG_DATA_HOME", before); delete(before, runtime.heap_allocator()) }
			os.set_env("XDG_DATA_HOME", data)
			s, app := start(t, {dir}, size = {1200, 700})
			context.allocator = runtime.heap_allocator()
			tab := current_tab(app)
			for name in ([]string{"notes.txt", "archive.zip"}) {
				point_at(t, tab, name)
				session.key(s, .Delete)
				wait_jobs(s)
			}
			testing.expect(t, !fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "trashed")

			tab_go(app, tab, "trash:///")
			wait_read(s)
			files := fs.join(data, "Trash/files", context.temp_allocator)
			testing.expect_value(t, tab.path, files)
			testing.expect(t, shows_trash(tab), "the tab is the trash")
			// Put back (its keys), from the row's menu too
			point_at(t, tab, "notes.txt")
			entry_menu_open(app, tab, {300, 200})
			session.frames(s, 3)
			testing.expect(t, session.find_text(s, "Put back") != nil, "the trash's row menu puts back")
			session.key(s, .Escape)
			session.frames(s, 2)
			point_at(t, tab, "notes.txt")
			session.key(s, .R, {.Ctrl, .Alt})
			wait_jobs(s)
			testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "put back where it was")
			testing.expect(t, !fs.exists(fs.join(files, "notes.txt", context.temp_allocator)), "out of the trash")
			testing.expect(t, !fs.exists(fs.join(data, "Trash/info/notes.txt.trashinfo", context.temp_allocator)), "its record gone")

			// Empty the trash: asked first, then every item and its record deleted
			session.key(s, .Delete, {.Ctrl, .Shift})
			testing.expect(t, app.confirm.open && app.confirm.trash, "asked")
			session.wait_box(s, "confirm_act")
			session.click(s, "confirm_act")
			wait_jobs(s)
			testing.expect(t, !fs.exists(fs.join(files, "archive.zip", context.temp_allocator)), "emptied")
			testing.expect(t, !fs.exists(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator)), "its record too")
			testing.expect(t, fs.exists(files), "the trash stays")
			testing.expect_value(t, len(tab.folder.listing.entries), 0)
		})
	}
}

// The sidebar: a volume takes a middle click (a new tab), a place's menu opens it in a new tab, a bookmark dragged
// below the next one moves there.
@(test)
test_sidebar_rows :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := fixture(t)
		// (the home is the test's: the place opened is not the person's)
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		p := current_panel(app)
		if len(app.volumes) > 0 && session.find(s, "vol0") != nil {
			n := len(p.tabs)
			session.click(s, "vol0", .Middle)
			wait_read(s)
			testing.expect_value(t, len(p.tabs), n + 1)
			testing.expect_value(t, p.tabs[p.active].path, app.volumes[0].path)
		}

		// a place's menu
		n := len(p.tabs)
		session.click(s, "place0", .Right)
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "Copy path") != nil, "the row's menu")
		session.click_text(s, "Open in new tab")
		wait_read(s)
		testing.expect_value(t, len(p.tabs), n + 1)
		testing.expect_value(t, p.tabs[p.active].path, app.places[0].path)

		// two bookmarks, the first dragged under the second
		append(&app.bookmarks, strings.clone(fs.join(dir, "Documents", context.temp_allocator)))
		append(&app.bookmarks, strings.clone(fs.join(dir, "Photos", context.temp_allocator)))
		session.frames(s, 3)
		first := session.get(s, "bookmark0").rect
		second := session.get(s, "bookmark1").rect
		session.drag(s, (first.min + first.max) * 0.5, {(second.min.x + second.max.x) * 0.5, second.max.y - 2})
		session.frames(s, 2)
		testing.expect_value(t, fs.base(app.bookmarks[0]), "Photos")
		testing.expect_value(t, fs.base(app.bookmarks[1]), "Documents")
		testing.expect(t, !app.bm_dragging, "the drag over")
	})
}

// A crumb of the path takes a drop (its folder: the parent here); files dragged in the window and held on a folder's
// row open it (spring-open).
@(test)
test_crumb_drop_and_spring :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := fixture(t)
		s, app := start(t, {fs.join(dir, "Documents", context.temp_allocator)}, size = {1200, 700})
		tab := current_tab(app)
		at: [2]f32
		for z in app.drop_zones_last { if z.path == dir { at = (z.rect.min + z.rect.max) * 0.5 } }
		testing.expect(t, at != {}, "the parent's crumb takes a drop")
		other := testkit.temp_folder(t, "classeur_menus_other")
		a := fs.join(other, "a.txt", context.temp_allocator)
		_ = os.write_entire_file(a, transmute([]u8)string("a"))
		data: platform.Drag_Data
		append(&data.files, a)
		defer delete(data.files)
		context.allocator = runtime.heap_allocator()
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Copy, .Move}, {.Ctrl})
		platform.drop_inject(app.main.win, .Drop_Over, at, nil, {.Copy, .Move}, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, app.drop_hover, dir)
		platform.drop_inject(app.main.win, .Drop, at, nil, {.Copy, .Move}, {.Ctrl})
		session.frames(s, 1)
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "a.txt", context.temp_allocator)), "dropped into the crumb's folder")

		// spring-open: notes.txt dragged onto the row of Photos and held there, Photos opens in the tab
		tab_go(app, tab, dir)
		wait_read(s)
		point_at(t, tab, "notes.txt")
		session.frames(s, 2)
		to: [2]f32
		for z in app.drop_zones_last { if strings.has_suffix(z.path, fs.SEPARATOR_STRING + "Photos") && z.rect.min.x > tab.cursor_rect.min.x - 1 { to = (z.rect.min + z.rect.max) * 0.5 } }
		testing.expect(t, to != {}, "the row of Photos")
		from := [2]f32{tab.cursor_rect.min.x + 120, (tab.cursor_rect.min.y + tab.cursor_rect.max.y) * 0.5}
		session.press(s, from)
		session.move(s, from + {0, 12})
		session.move(s, to)
		session.advance(s, SPRING_MS + 200)
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Photos")
		session.release(s, to)
		session.frames(s, 2)
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/notes.txt", context.temp_allocator)), "dropped in the folder it opened")
	})
}
