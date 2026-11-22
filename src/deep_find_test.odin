package classeur

// GoTo and the path field find what is below the current folder at any depth: a file by a few letters of its name, a
// relative path typed whole; a click on the crumbs opens the path field, never a dialog.
// Run with -define:ODIN_TEST_THREADS=1 (one interface at a time).

import "base:runtime"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "gt:ui"
import "fs"

@(private = "file")
DEEP_FIXTURE :: [?]string{
	"packages/", "packages/web/", "packages/web/public/", "packages/web/public/brand/", "packages/web/public/brand/logo.svg",
	"packages/web/src/", "packages/web/src/main.ts", ".git/", ".git/logo.svg", "notes.txt",
}

// Frames until gt:filesearch has finished its initial scan and answered the current query.
@(private = "file")
wait_deep :: proc(s: ^session.Session) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		return deep_ready((^App)(s.user))
	}, "the deep search answered")
	session.frames(s, 2)
}

@(test)
test_goto_deep :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := DEEP_FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		logo := fs.join(dir, "packages/web/public/brand/logo.svg", context.temp_allocator)

		// a few letters of a name four folders down: that file, and not the one under the hidden .git
		session.key(s, .G, {.Ctrl})
		testing.expect(t, ui.view_is_open(&app.views, GOTO_VIEW))
		session.type_text(s, "logo")
		wait_deep(s)
		found := goto_rows(app, dir, "logo")
		if testing.expect(t, len(found.rows) > 0, "a row for logo") {
			testing.expect_value(t, found.rows[0].path, logo)
			testing.expect(t, !found.rows[0].folder, "a file")
		}
		for r in found.rows { testing.expect(t, r.path != fs.join(dir, ".git/logo.svg", context.temp_allocator), "nothing under .git") }
		session.key(s, .Escape)
		session.frames(s, 2)

		// a relative path typed whole: its file first; Enter opens its folder with the file at the cursor
		session.key(s, .G, {.Ctrl})
		session.type_text(s, "packages/web/public/brand/logo.svg")
		wait_deep(s)
		found = goto_rows(app, dir, "packages/web/public/brand/logo.svg")
		if testing.expect(t, len(found.rows) > 0, "a row for the path") { testing.expect_value(t, found.rows[0].path, logo) }
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !ui.view_is_open(&app.views, GOTO_VIEW), "GoTo closed")
		testing.expect_value(t, tab.path, fs.join(dir, "packages/web/public/brand", context.temp_allocator))
		e := folder_cursor_entry(&tab.folder)
		testing.expect(t, e != nil && e.name == "logo.svg", "the file at the cursor")
	})
}

// A folder with a name longer than the row: the crumbs keep an empty part at their end, and a click there opens the path
// field (Windows' long temporary folders covered it with the last crumb).
@(test)
test_crumbs_keep_their_empty_part :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		LONG :: "a_folder_with_a_name_much_longer_than_the_bar_of_crumbs_can_ever_show_whole_in_one_row_of_a_window_that_is_not_wide_at_all/"
		files := [?]string{LONG}
		dir := make_fixture(t, files[:])
		s, app := start(t, {fs.join(dir, LONG[:len(LONG) - 1], context.temp_allocator)}, size = {900, 600})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		session.frames(s, 3)
		crumbs := session.get(s, "crumbs")
		if !testing.expect(t, crumbs != nil, "the crumbs") { return }
		// (the parts drawn end before the row does: the spacer after them, the empty part, keeps a width)
		end: f32
		for b := crumbs.first; b != nil; b = b.next { if b.rect.max.y > b.rect.min.y { end = max(end, b.rect.max.x) } }
		testing.expectf(t, crumbs.rect.max.x - end > 8, "an empty part at the end: the parts end at %v in %v", end, crumbs.rect)
		session.click_at(s, {crumbs.rect.max.x - 4, (crumbs.rect.min.y + crumbs.rect.max.y) * 0.5})
		session.frames(s, 2)
		testing.expect(t, tab.address_open, "the path field")
	})
}

// A click on the empty part of the crumbs: the path field, its rows under it; no dialog. Letters find what is below.
@(test)
test_crumbs_click_types_the_path :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := DEEP_FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		crumbs := session.get(s, "crumbs")
		if !testing.expect(t, crumbs != nil, "the crumbs") { return }
		// (its right end: past the last crumb, the empty part)
		session.click_at(s, {crumbs.rect.max.x - 4, (crumbs.rect.min.y + crumbs.rect.max.y) * 0.5})
		session.frames(s, 2)
		testing.expect(t, tab.address_open, "the path field")
		testing.expect(t, !ui.view_is_open(&app.views, GOTO_VIEW), "no GoTo dialog")
		session.type_text(s, "main")
		wait_deep(s)
		session.wait_box(s, "sugg0")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "packages/web/src", context.temp_allocator))
	})
}

// Typo-tolerant file search via gt:filesearch in GoTo and in the command palette's '/' source.
@(test)
test_filesearch_typo_and_palette :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := [?]string{"models/", "models/schema.odin", "notes.txt"}
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		schema := fs.join(dir, "models/schema.odin", context.temp_allocator)

		// Typo in GoTo: "shcema" finds models/schema.odin.
		session.key(s, .G, {.Ctrl})
		session.type_text(s, "shcema")
		wait_deep(s)
		found := goto_rows(app, dir, "shcema")
		if testing.expect(t, len(found.rows) > 0, "typo-tolerant match in GoTo") {
			testing.expect_value(t, found.rows[0].path, schema)
		}
		session.key(s, .Escape)
		session.frames(s, 2)

		// Command palette '/' source finds models/schema.odin via ui.Palette_Files.
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "/shcema")
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			app := (^App)(s.user)
			src, _, ok := ui.palette_row(&app.palette.pal, 0)
			return ok && src == &app.palette.files.source
		}, "palette '/' files source returns schema.odin")
		src, id, ok := ui.palette_row(&app.palette.pal, 0)
		testing.expect(t, ok && src == &app.palette.files.source && id == schema, "schema.odin first in palette '/'")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, current_tab(app).path, fs.join(dir, "models", context.temp_allocator))
		e := folder_cursor_entry(&current_tab(app).folder)
		testing.expect(t, e != nil && e.name == "schema.odin", "cursor placed on schema.odin")
	})
}
