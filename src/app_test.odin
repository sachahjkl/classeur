package classeur

// classeur as a person meets it, with no window of the system (gui_toolkit's testkit/session): a folder made for the
// test, read, sorted, filtered, entered and left; a folder made and renamed; the palette; tabs and panels.
// Run with -define:ODIN_TEST_THREADS=1 (one interface at a time).

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import "gt:platform"
import config "gt:config"
import "gt:png"
import "gt:testkit"
import "gt:testkit/unwatched"
import "gt:ui"
import "gt:testkit/session"
import "fs"

// classeurtool shots: the pictures of the README, from test_shots.
SHOTS :: #config(CLASSEUR_SHOTS, false)
// The tests that measure time run only when asked (classeurtool timed): a loaded machine would fail them for nothing.
TIMED :: #config(CLASSEUR_TIMED, false)

// (shared by the tests of the package: each file of tests uses it)
FIXTURE :: [?]string{
	"Documents/", "Photos/", "Projects/", "notes.txt", "report 2.pdf", "report 10.pdf", "archive.zip", ".hidden",
	"Documents/letter.odt", "Documents/budget.xlsx",
}

// (shared by the tests of the package: each file of tests uses it)
make_fixture :: proc(t: ^testing.T, files: []string) -> string {
	// (clean: the program's paths are; on Windows the temporary folder comes with '/' in it)
	dir := fs.clean(testkit.temp_folder(t, "classeur"), context.temp_allocator)
	for f in files {
		path := fs.join(dir, f, context.temp_allocator)
		if f[len(f) - 1] == '/' {
			_ = os.make_directory_all(path)
		} else {
			_ = os.write_entire_file(path, transmute([]u8)fmt.tprintf("the file %s\n", f))
		}
	}
	return dir
}

// (shared by the tests of the package: each file of tests uses it)
start :: proc(t: ^testing.T, folders: []string, size := [2]int{}, home := "", loc := #caller_location) -> (s: ^session.Session, app: ^App) {
	context.allocator = runtime.heap_allocator()
	app = app_open({folders = folders, headless = true, size = size, home = home})
	if !testing.expect(t, app != nil, "classeur opens", loc = loc) { session.stop_test(t, "no application", loc) }
	testing.cleanup(t, proc(p: rawptr) { app_close((^App)(p)) }, app)
	s = session.attach(t, {win = app.main.win, state = &app.main.state, renderer = &app.shared.r, user = app, allocator = context.allocator,
		frame = proc(user: rawptr) { app_frame((^App)(user)) }}, loc)
	wait_read(s)
	return
}

// Frames until every tab has its folder, and the workers have answered every change to files asked of them (a rename,
// a new folder, an undo, the places: answers_due).
// (shared by the tests of the package: each file of tests uses it)
wait_read :: proc(s: ^session.Session, loc := #caller_location) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		app := (^App)(s.user)
		if app.answers_due > 0 { return false }
		for p in app.panels { for t in p.tabs { if t.loading { return false } } }
		return true
	}, "the folders read", loc = loc)
	session.frames(s, 2)
}

// The cursor on `name`, and it alone selected (as a click does).
// (shared by the tests of the package: each file of tests uses it)
point_at :: proc(t: ^testing.T, tab: ^Tab, name: string, loc := #caller_location) {
	testing.expect(t, folder_cursor_to_name(&tab.folder, name), loc = loc)
	folder_pick(&tab.folder, tab.folder.cursor)
}

// (shared by the tests of the package: each file of tests uses it)
shown_names :: proc(t: ^Tab) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for i in t.folder.shown { append(&out, t.folder.listing.entries[i].name) }
	return out[:]
}

@(test)
test_browse :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		testing.expect_value(t, tab.path, fs.clean(dir, context.temp_allocator))
		// folders first, then the files in natural order; the hidden file is not shown
		names := shown_names(tab)
		testing.expect_value(t, fmt.tprint(names), `["Documents", "Photos", "Projects", "archive.zip", "notes.txt", "report 2.pdf", "report 10.pdf"]`)
		session.wait_text(s, "report 10.pdf")

		// the filter keeps the names with its letters
		session.key(s, .F, {.Ctrl})
		session.type_text(s, "rep")
		testing.expect_value(t, fmt.tprint(shown_names(tab)[:2]), `["report 2.pdf", "report 10.pdf"]`)   // (best matched first)
		// Enter in the filter opens the first row it keeps (a file: the system's application)
		session.key(s, .Return)
		testing.expect_value(t, len(app.opened), 1)
		testing.expect_value(t, fs.base(app.opened[0]), "report 2.pdf")
		session.key(s, .F, {.Ctrl})
		session.key(s, .Escape)
		testing.expect_value(t, len(tab.folder.shown), 7)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "report 2.pdf")

		// Enter opens the folder at the cursor, Backspace goes back up with the cursor on it
		session.key(s, .Home)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "Documents")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Documents")
		testing.expect_value(t, fmt.tprint(shown_names(tab)), `["budget.xlsx", "letter.odt"]`)
		session.key(s, .Backspace)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.clean(dir, context.temp_allocator))
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "Documents")
		session.key(s, .Left, {.Alt})
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Documents")
		session.key(s, .Right, {.Alt})
		wait_read(s)
		testing.expect_value(t, tab.path, fs.clean(dir, context.temp_allocator))

		// sorted by size, the largest first; by name again
		session.click_at(s, title_point(s, .Size))
		testing.expect_value(t, tab.folder.sort.key, fs.Sort_Key.Size)
		testing.expect(t, tab.folder.sort.descending)
		testing.expect_value(t, folder_row_entry(&tab.folder, 3).name, "report 10.pdf")
		session.click_at(s, title_point(s, .Name))
		testing.expect_value(t, folder_row_entry(&tab.folder, 3).name, "archive.zip")

		// Shift+Down selects a range, Ctrl+A all
		session.key(s, .Home)
		session.key(s, .Down, {.Shift}, repeat = 2)
		testing.expect_value(t, tab.folder.count, 3)
		session.key(s, .A, {.Ctrl})
		testing.expect_value(t, tab.folder.count, 7)
		session.key(s, .Down)
		testing.expect_value(t, tab.folder.count, 1)

		// the hidden files, from the palette
		session.key(s, .P, {.Ctrl, .Shift})
		testing.expect(t, app.palette.open)
		session.type_text(s, "hidden files")
		session.key(s, .Return)
		testing.expect(t, !app.palette.open)
		testing.expect(t, app.show_hidden)
		testing.expect(t, slice.contains(shown_names(tab), ".hidden"))
	})
}

@(test)
test_change_files :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)

		// a new folder, named at once
		session.key(s, .N, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, app.rename.active)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "Archives 2026")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !app.rename.active)
		info, ok := fs.stat(fs.join(dir, "Archives 2026", context.temp_allocator))
		testing.expect(t, ok && info.kind == .Directory, "the folder is made and named")
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "Archives 2026")

		// F2 renames the file at the cursor; the extension stays out of the selection
		testing.expect(t, folder_cursor_to_name(&tab.folder, "notes.txt"))
		session.key(s, .F2)
		testing.expect(t, app.rename.active)
		session.type_text(s, "todo")
		session.key(s, .Return)
		wait_read(s)
		_, renamed := fs.stat(fs.join(dir, "todo.txt", context.temp_allocator))
		testing.expect(t, renamed, "notes.txt is now todo.txt")
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "todo.txt")
	})
}

@(test)
test_tabs_and_panels :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		p := current_panel(app)
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect_value(t, p.active, 1)
		session.key(s, .W, {.Ctrl})
		testing.expect_value(t, len(p.tabs), 1)
		session.key(s, .T, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 2)

		// Ctrl+Enter opens the folder at the cursor in a new tab
		session.key(s, .Return, {.Ctrl})
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 3)
		testing.expect_value(t, fs.base(panel_tab(p).path), "Documents")

		// a second panel; F6 goes from one to the other
		session.key(s, .D, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect_value(t, len(app.panels), 2)
		testing.expect_value(t, app.focus, 1)
		// (the stops go round: the sidebar after the last panel, then the first panel)
		session.key(s, .F6)
		testing.expect_value(t, app.keys_at, Keys_At.Sidebar)
		session.key(s, .F6)
		testing.expect_value(t, app.focus, 0)
		testing.expect_value(t, app.keys_at, Keys_At.List)
		session.key(s, .W, {.Ctrl, .Shift})
		testing.expect_value(t, len(app.panels), 1)
	})
}

// A made-up photograph: a sky, a sun, three rows of hills, in the colours of `seed`.
@(private = "file")
landscape :: proc(w, h: int, seed: int) -> []u8 {
	out := make([]u8, w * h * 4, context.temp_allocator)
	hue := f32(seed % 7) / 7
	sky_top := [3]f32{0.15 + 0.5 * hue, 0.35, 0.75 - 0.4 * hue}
	sky_low := [3]f32{0.95, 0.75 - 0.3 * hue, 0.55 + 0.2 * hue}
	sun := [2]f32{f32(w) * (0.25 + 0.5 * f32(seed % 3) / 3), f32(h) * 0.35}
	for y in 0 ..< h {
		for x in 0 ..< w {
			fy := f32(y) / f32(h)
			c := sky_top + (sky_low - sky_top) * fy
			dx, dy := f32(x) - sun.x, f32(y) - sun.y
			if dx * dx + dy * dy < f32(h * h) * 0.012 { c = {1, 0.93, 0.7} }
			for k in 0 ..< 3 {
				fk := f32(k)
				ridge := 0.45 + 0.13 * fk + 0.06 * math.sin(f32(x) / f32(w) * (5 + fk * 3) + f32(seed) * 1.7 + fk)
				if fy > ridge {
					shade := 0.55 - 0.15 * fk
					c = {0.12 + shade * 0.3 * hue, 0.22 + shade * 0.5, 0.18 + shade * 0.25}
				}
			}
			o := out[(y * w + x) * 4:]
			o[0], o[1], o[2], o[3] = u8(clamp(c.r, 0, 1) * 255), u8(clamp(c.g, 0, 1) * 255), u8(clamp(c.b, 0, 1) * 255), 255
		}
	}
	return out
}

// (shared by the tests of the package: each file of tests uses it)
write_pictures :: proc(dir: string, names: []string) {
	for name, i in names {
		w, h := 480, 320
		data := png.encode(landscape(w, h, i + 1), w, h, .Fast, context.temp_allocator)
		_ = os.write_entire_file(fs.join(dir, name, context.temp_allocator), data)
	}
}

@(private = "file")
thumbs_ready :: proc(s: ^session.Session) -> bool {
	app := (^App)(s.user)
	if len(app.thumbs) == 0 { return false }
	for _, th in app.thumbs { if th.state == .Asked { return false } }
	return true
}

@(test)
test_grid :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		write_pictures(fs.join(dir, "Photos", context.temp_allocator), {"a.png", "b.png", "c.png", "d.png", "e.png", "f.png", "g.png"})
		s, app := start(t, {fs.join(dir, "Photos", context.temp_allocator)}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .N2, {.Ctrl})
		testing.expect_value(t, tab_mode(tab), View_Mode.Grid)
		session.wait_until(s, thumbs_ready, "the thumbnails")
		for _, th in app.thumbs {
			testing.expect_value(t, th.state, Thumb_State.Ready)
			testing.expect(t, max(th.size.x, th.size.y) <= THUMB_PX)
		}
		session.frames(s, 2)
		testing.expect(t, tab.grid_cols >= 2, "cards side by side")
		session.key(s, .Home)
		session.key(s, .Right)
		testing.expect_value(t, tab.folder.cursor, 1)
		session.key(s, .Down)
		testing.expect_value(t, tab.folder.cursor, min(1 + tab.grid_cols, 6))
		testing.expect_value(t, tab.folder.count, 1)
		session.key(s, .N1, {.Ctrl})
		testing.expect_value(t, tab_mode(tab), View_Mode.Details)
	})
}

@(test)
test_search :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		_ = os.make_directory_all(fs.join(dir, "Projects/site/notes", context.temp_allocator))
		_ = os.write_entire_file(fs.join(dir, "Projects/site/notes/letter draft.txt", context.temp_allocator), transmute([]u8)string("x"))
		s, app := start(t, {dir})
		tab := current_tab(app)
		// the folder flattened: every entry under it, named by its path
		session.key(s, .F, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, tab.folder.flat)
		testing.expect(t, slice.contains(shown_names(tab), fs.join("Documents", "letter.odt", context.temp_allocator)), "what is in the folders below")
		// the filter's letters, in order, anywhere in the path
		session.type_text(s, "lettr")
		names := shown_names(tab)
		testing.expect_value(t, len(names), 2)
		testing.expect(t, slice.contains(names, fs.join("Documents", "letter.odt", context.temp_allocator)) && slice.contains(names, fs.join("", "Projects/site/notes/letter draft.txt", context.temp_allocator)))
		session.key(s, .Return)
		testing.expect_value(t, len(app.opened), 1)
		testing.expect_value(t, app.opened[0], fs.join(dir, names[0], context.temp_allocator))
		// the toggle again: the folder alone
		session.key(s, .F, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, !tab.folder.flat)
		testing.expect(t, !slice.contains(shown_names(tab), "Documents/letter.odt"))
	})
}

@(test)
test_options :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		session.key(s, .Comma, {.Ctrl})
		testing.expect(t, app.options.open)
		// the settings' search finds it by its words; its switch flips it
		session.frames(s, 2)
		session.type_text(s, "hidden")
		session.frames(s, 2)
		session.click(s, "sw")
		session.frames(s, 1)
		testing.expect(t, app.show_hidden)
		testing.expect(t, slice.contains(shown_names(tab), ".hidden"))
		session.key(s, .Escape)
		testing.expect(t, !app.options.open)
		// the extensions left out of the names shown
		session.key(s, .Comma, {.Ctrl})
		session.frames(s, 2)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "extension")
		session.frames(s, 2)
		session.click(s, "sw")
		session.frames(s, 1)
		session.key(s, .Escape)
		testing.expect(t, !app.settings.show_extensions)
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "notes") != nil, "notes.txt shows as notes")
	})
}

@(test)
test_inspector :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		write_pictures(fs.join(dir, "Photos", context.temp_allocator), {"lake.png"})
		s, app := start(t, {dir})
		tab := current_tab(app)
		inspected :: proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }
		// a text file: its beginning
		point_at(t, tab, "notes.txt")
		session.key(s, .Space)
		testing.expect(t, app.inspector.open)
		session.wait_until(s, inspected, "the inspector")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Text)
		testing.expect_value(t, app.inspector.text, "the file notes.txt\n")
		// a folder: its content
		point_at(t, tab, "Documents")
		session.frames(s, 1)
		session.wait_until(s, inspected, "the inspector")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Folder)
		testing.expect_value(t, len(app.inspector.listing.entries), 2)
		// a picture
		point_at(t, tab, "Photos")
		session.key(s, .Return)
		wait_read(s)
		session.wait_until(s, inspected, "the inspector")
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Picture)
		testing.expect_value(t, app.inspector.size, [2]int{480, 320})
		// the wheel over it zooms (the toolkit's preview); the arrows stay the list's
		session.frames(s, 2)
		pic := session.get(s, "insp_pic")
		session.wheel(s, session.center(pic), {0, -3})   // (up: larger)
		session.frames(s, 4)
		testing.expectf(t, app.inspector.preview.zoom > 1, "zoomed: %v", app.inspector.preview.zoom)
		cursor := tab.folder.cursor
		session.key(s, .Down)
		session.frames(s, 2)
		testing.expect(t, tab.folder.cursor != cursor || len(tab.folder.shown) < 2, "Down moves the list's cursor")
		session.key(s, .Space)
		testing.expect(t, !app.inspector.open)
	})
}

// The pictures of the README (classeurtool shots): a home folder of made-up files; the grid of the pictures beside the
// details of the home folder; the palette.
@(test)
test_shots :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		when !SHOTS { return }
		home := []string{
			"Desktop/", "Documents/", "Downloads/", "Music/", "Pictures/", "Projects/", "Videos/",
			"Projects/classeur/", "Projects/website/", "Projects/notes.md", "Projects/classeur/src/", "Projects/classeur/README.md",
			"Documents/Invoices/", "Documents/Taxes 2025/", "Documents/contract.pdf", "Documents/budget 2026.xlsx", "Documents/letter.odt",
			"Pictures/Holidays 2026/", "Pictures/Holidays 2026/beach.png",
			"Downloads/odin-linux-amd64.tar.gz", "Downloads/fonts.zip", "Downloads/manual.pdf", "Downloads/setup.exe",
			"Music/album/", "Music/track 01.flac", "Music/track 02.flac", "Videos/talk.mp4",
			"todo.txt", "photo.jpg", "build.sh", "README.md", "archive.zip", "notes 2.txt", "notes 10.txt", ".bashrc",
		}
		dir := make_fixture(t, home)
		write_pictures(fs.join(dir, "Pictures", context.temp_allocator), {"harbour.png", "mountain 2.png", "mountain 10.png", "lake.png", "valley.png", "sunset.png", "ridge.png", "dawn.png"})
		s, app := start(t, {dir}, size = {1600, 900}, home = dir)
		session.frames(s, 4)
		session.save_png(s, "main.png")

		// the grid of the pictures at the left, the details of the home folder at the right with three folders selected
		context.allocator = runtime.heap_allocator()   // (what the application keeps is its allocator's)
		session.key(s, .D, {.Ctrl, .Shift})
		wait_read(s)
		left := panel_tab(app.panels[0])
		tab_go(app, left, fs.join(dir, "Pictures", context.temp_allocator))
		left.zoom = ZOOM_GRID
		wait_read(s)
		session.wait_until(s, thumbs_ready, "the thumbnails")
		left.folder.cursor = 2
		session.key(s, .Home)
		session.key(s, .Down)
		session.key(s, .Down, {.Shift}, repeat = 2)
		session.frames(s, 4)
		session.save_png(s, "panels.png")

		session.key(s, .P, {.Ctrl, .Shift})
		session.type_text(s, "open")
		session.frames(s, 2)
		session.save_png(s, "palette.png")
		session.key(s, .Escape)
		// the inspector on a picture, one panel
		for len(app.panels) > 1 { session.key(s, .W, {.Ctrl, .Shift}) }
		tab_go(app, current_tab(app), fs.join(dir, "Pictures", context.temp_allocator))
		current_tab(app).zoom = 0
		wait_read(s)
		point_at(t, current_tab(app), "lake.png")
		session.key(s, .Space)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 3)
		session.save_png(s, "inspector.png")
		session.key(s, .Space)

		session.key(s, .Comma, {.Ctrl})
		session.frames(s, 3)
		session.save_png(s, "options.png")
		session.key(s, .Escape)

		// the search: the home folder flattened, "not" typed in the filter
		session.key(s, .W, {.Ctrl, .Shift})
		app.focus = 0
		tab_go(app, panel_tab(app.panels[0]), dir)
		panel_tab(app.panels[0]).zoom = 0
		wait_read(s)
		session.key(s, .F, {.Ctrl, .Shift})
		wait_read(s)
		session.type_text(s, "not")
		session.key(s, .Down)
		session.frames(s, 4)
		session.save_png(s, "search.png")

		// GoTo, a path being typed
		session.key(s, .Escape)
		session.key(s, .F, {.Ctrl, .Shift})
		wait_read(s)
		ui.field_clear(&panel_tab(app.panels[0]).filter)
		session.key(s, .G, {.Ctrl})
		session.type_text(s, "~/Doc")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).goto.names) > 0 }, "the folders read")
		session.frames(s, 3)
		session.save_png(s, "goto.png")
		session.key(s, .Escape)

		// batch rename of the music
		tab_go(app, panel_tab(app.panels[0]), fs.join(dir, "Music", context.temp_allocator))
		wait_read(s)
		session.key(s, .A, {.Ctrl})
		session.key(s, .F2)
		session.type_text(s, "{n:2} - {name}")
		session.frames(s, 3)
		session.save_png(s, "batch.png")
		session.key(s, .Escape)
	})
}

// Frames until every job has ended and its folders are read again.
// (shared by the tests of the package: each file of tests uses it)
wait_jobs :: proc(s: ^session.Session, loc := #caller_location) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		app := (^App)(s.user)
		if app.paste.id != 0 { return false }   // (a paste's files not come yet: its job is not made)
		for job in app.jobs.list { if job.ended_ms == 0 { return false } }
		return true
	}, "the jobs ended", loc = loc)
	wait_read(s, loc)
}

@(test)
test_jobs :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		// (the trash of the test, never the person's)
		data := fs.join(dir, ".data", context.temp_allocator)
		os.set_env("XDG_DATA_HOME", data)
		s, app := start(t, {dir})
		tab := current_tab(app)

		// copy notes.txt, paste it in Documents
		point_at(t, tab, "notes.txt")
		session.key(s, .C, {.Ctrl})
		point_at(t, tab, "Documents")
		session.key(s, .Return)
		wait_read(s)
		session.key(s, .V, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Documents/notes.txt", context.temp_allocator)), "the copy is there")
		testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "the original stays")
		testing.expect(t, slice.contains(shown_names(tab), "notes.txt"), "the folder is read again")

		// again: the name is taken, the person keeps both
		session.key(s, .V, {.Ctrl})
		session.wait_until(s, proc(s: ^session.Session) -> bool { return job_asking((^App)(s.user)) != nil }, "the question")
		session.wait_box(s, "both")
		session.frames(s, 2)
		// (its four choices on one line, in the dialog)
		if r, b := session.find(s, "replace"), session.find(s, "buttons"); r != nil && b != nil { testing.expectf(t, r.rect.max.x <= b.rect.max.x + 0.5, "Replace in the dialog (%v, %v)", r.rect, b.rect) }
		session.click(s, "both")
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Documents/notes 2.txt", context.temp_allocator)), "kept both: notes 2.txt")

		// cut a file in the parent folder, paste it here: it moves
		session.key(s, .Backspace)
		wait_read(s)
		point_at(t, tab, "report 2.pdf")
		session.key(s, .X, {.Ctrl})
		point_at(t, tab, "Photos")
		session.key(s, .Return)
		wait_read(s)
		session.key(s, .V, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/report 2.pdf", context.temp_allocator)), "moved into Photos")
		testing.expect(t, !fs.exists(fs.join(dir, "report 2.pdf", context.temp_allocator)), "and gone from where it was")

		// to the trash, with what the desktop's trash needs to put it back
		session.key(s, .Backspace)
		wait_read(s)
		point_at(t, tab, "archive.zip")
		session.key(s, .Delete)
		wait_jobs(s)
		testing.expect(t, !fs.exists(fs.join(dir, "archive.zip", context.temp_allocator)), "archive.zip left")
		// (Linux: the freedesktop.org trash of the test; Windows: the Recycle Bin)
		when ODIN_OS == .Linux {
			testing.expect(t, fs.exists(fs.join(data, "Trash/files/archive.zip", context.temp_allocator)), "into the trash")
			info, _ := os.read_entire_file(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator), context.temp_allocator)
			testing.expect(t, strings.has_prefix(string(info), "[Trash Info]\nPath=/"), "with its .trashinfo")
			testing.expect(t, strings.contains(string(info), "/archive.zip\nDeletionDate="), "where it was, and when")
		}

		// undo, step by step: the trash (Linux's, or the Recycle Bin by its $I record), the move, the second copy
		session.key(s, .Z, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "archive.zip", context.temp_allocator)), "undo: archive.zip back from the trash")
		when ODIN_OS == .Linux { testing.expect(t, !fs.exists(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator)), "its .trashinfo gone") }
		session.key(s, .Z, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "report 2.pdf", context.temp_allocator)), "undo: report 2.pdf moved back")
		testing.expect(t, !fs.exists(fs.join(dir, "Photos/report 2.pdf", context.temp_allocator)))
		session.key(s, .Z, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, !fs.exists(fs.join(dir, "Documents/notes 2.txt", context.temp_allocator)), "undo: the copy to the trash")
		when ODIN_OS == .Linux { testing.expect(t, fs.exists(fs.join(data, "Trash/files/notes 2.txt", context.temp_allocator)), "not deleted: trashed") }
		testing.expect(t, fs.exists(fs.join(dir, "Documents/notes.txt", context.temp_allocator)), "the first copy stays")

		// for good, after the question
		point_at(t, tab, "notes.txt")
		session.key(s, .Delete, {.Shift})
		testing.expect(t, app.confirm.open)
		session.wait_box(s, "confirm_act")
		session.click(s, "confirm_act")
		wait_jobs(s)
		testing.expect(t, !fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "deleted")
		testing.expect(t, !slice.contains(shown_names(tab), "notes.txt"))
	})
}

@(test)
test_watch :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		// another program makes a file and removes one: the list follows, no key pressed
		_ = os.write_entire_file(fs.join(dir, "from elsewhere.txt", context.temp_allocator), transmute([]u8)string("hello"))
		_ = os.remove(fs.join(dir, "archive.zip", context.temp_allocator))
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			names := shown_names(current_tab((^App)(s.user)))
			return slice.contains(names, "from elsewhere.txt") && !slice.contains(names, "archive.zip")
		}, "the folder read again")
		testing.expect_value(t, len(tab.folder.shown), 7)
	})
}

@(test)
test_undo_names :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)

		// a new folder, named: one step; undone, it goes
		session.key(s, .N, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, app.rename.active)
		session.type_text(s, "Fresh")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "Fresh", context.temp_allocator)), "the folder made and named")
		testing.expect_value(t, len(app.undo), 1)

		// a rename, undone: the old name again
		point_at(t, tab, "notes.txt")
		session.key(s, .F2)
		session.frames(s, 2)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "renamed.txt")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "renamed.txt", context.temp_allocator)), "renamed")
		session.key(s, .Z, {.Ctrl})
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "undo: the old name")
		testing.expect(t, !fs.exists(fs.join(dir, "renamed.txt", context.temp_allocator)))
		session.key(s, .Z, {.Ctrl})
		wait_read(s)
		testing.expect(t, !fs.exists(fs.join(dir, "Fresh", context.temp_allocator)), "undo: the new folder gone")
		testing.expect_value(t, len(app.undo), 0)
	})
}

@(test)
test_session :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		// (kept on the heap: the frames below empty the temporary allocator)
		dir = strings.clone(dir, runtime.heap_allocator())
		defer delete(dir, runtime.heap_allocator())
		file := fs.join(dir, ".session", runtime.heap_allocator())
		defer delete(file, runtime.heap_allocator())
		documents := fs.join(dir, "Documents", runtime.heap_allocator())
		defer delete(documents, runtime.heap_allocator())
		{
			context.allocator = runtime.heap_allocator()
			app := app_open({folders = {dir}, headless = true, session = file})
			testing.expect(t, app != nil)
			// two panels: the folder and Documents in a tab, zoomed, locked; Photos bookmarked
			tab_open(app, app.panels[0], documents)
			current_tab(app).zoom = ZOOM_GRID
			current_tab(app).locked = true
			panel_open(app, fs.join(dir, "Projects", context.temp_allocator))
			bookmark_toggle(app, fs.join(dir, "Photos", context.temp_allocator))
			folder_sort_by(&app.panels[0].tabs[1].folder, .Size)
			// written while it runs (a program killed loses nothing): after a frame, on a worker
			written := false
			for _ in 0 ..< 400 {
				app_frame(app)
				data, err := os.read_entire_file(file, context.temp_allocator)
				if err == nil && strings.contains(string(data), "Projects") && strings.contains(string(data), fmt.tprintf("tab %d 1 %d 1 ", ZOOM_GRID, int(fs.Sort_Key.Size))) { written = true; break }
				time.sleep(5 * time.Millisecond)
			}
			testing.expect(t, written, "the session written before the window closes")
			app_close(app)
		}
		testing.expect(t, fs.exists(file), "the session is written")
		// the folder Projects goes: its tab opens at its parent
		testing.expect(t, fs.remove(fs.join(dir, "Projects", context.temp_allocator)) == .None)
		{
			context.allocator = runtime.heap_allocator()
			// (a folder given: it opens beside the session's tabs, in the panel with the keyboard)
			photos := fs.join(dir, "Photos", context.temp_allocator)
			app := app_open({folders = {photos}, headless = true, session = file})
			defer app_close(app)
			// (the reads come: the tab of Projects, gone, goes up)
			for _ in 0 ..< 400 {
				app_frame(app)
				loading := false
				for p in app.panels { for tb in p.tabs { if tb.loading { loading = true } } }
				if !loading { break }
			}
			testing.expect_value(t, len(app.panels), 2)
			testing.expect_value(t, len(app.panels[0].tabs), 2)
			testing.expect_value(t, app.panels[0].active, 1)
			t1 := app.panels[0].tabs[1]
			testing.expect_value(t, t1.path, documents)
			testing.expect_value(t, t1.zoom, ZOOM_GRID)
			testing.expect(t, t1.locked)
			testing.expect(t, t1.folder.sort.key == .Size && t1.folder.sort.descending, "its sort")
			testing.expect_value(t, app.panels[1].tabs[0].path, dir)
			testing.expect_value(t, app.focus, 1)
			testing.expect_value(t, len(app.panels[1].tabs), 2)
			testing.expect_value(t, app.panels[1].tabs[1].path, fs.join(dir, "Photos", context.temp_allocator))
			testing.expect_value(t, app.panels[1].active, 1)
			testing.expect_value(t, len(app.bookmarks), 1)
		}
	})
}

@(test)
test_goto :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		_ = os.make_directory_all(fs.join(dir, "Projects/classeur/src", context.temp_allocator))
		s, app := start(t, {dir})
		tab := current_tab(app)

		// a path: the folders in it, found by the letters after the last separator; Tab completes, Enter goes
		session.key(s, .G, {.Ctrl})
		testing.expect(t, app.goto.open)
		session.type_text(s, fs.join(dir, "proj", context.temp_allocator))
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).goto.names) > 0 }, "the folder read")
		session.frames(s, 2)
		session.key(s, .Tab)
		session.frames(s, 2)
		testing.expect_value(t, ui.field_string(&app.goto.field), fmt.tprintf("%s%s", fs.join(dir, "Projects", context.temp_allocator), fs.SEPARATOR_STRING))
		session.type_text(s, "cla")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return strings.has_suffix((^App)(s.user).goto.dir, "Projects") }, "Projects read")
		session.frames(s, 2)
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !app.goto.open)
		testing.expect_value(t, tab.path, fs.join(dir, "Projects/classeur", context.temp_allocator))

		// a whole path ended by a separator: Enter goes to it, not to its first folder
		session.key(s, .G, {.Ctrl})
		session.type_text(s, fmt.tprintf("%s%s", fs.join(dir, "Projects", context.temp_allocator), fs.SEPARATOR_STRING))
		session.wait_until(s, proc(s: ^session.Session) -> bool { return strings.has_suffix((^App)(s.user).goto.dir, "Projects") }, "Projects read")
		session.frames(s, 2)
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "Projects", context.temp_allocator))

		// words: a recent folder by a few letters of its path
		context.allocator = runtime.heap_allocator()
		tab_go(app, tab, dir)
		wait_read(s)
		session.key(s, .G, {.Ctrl})
		session.type_text(s, "jectsclas")
		session.frames(s, 2)
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "Projects/classeur", context.temp_allocator))
	})
}

@(test)
test_more_actions :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)

		// a new file, named in place; undone, redone
		session.key(s, .N, {.Ctrl, .Alt})
		wait_read(s)
		testing.expect(t, app.rename.active)
		session.type_text(s, "draft")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "draft.txt", context.temp_allocator)), "the new file named (its extension kept)")
		session.key(s, .Z, {.Ctrl})
		wait_read(s)
		testing.expect(t, !fs.exists(fs.join(dir, "draft.txt", context.temp_allocator)), "undone")
		session.key(s, .Y, {.Ctrl})
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "draft.txt", context.temp_allocator)), "redone")
		testing.expect_value(t, len(app.redo), 0)

		// a terminal here (headless: noted, not started)
		session.key(s, .F4)
		testing.expect(t, len(app.opened) > 0 && strings.has_prefix(app.opened[len(app.opened) - 1], "terminal:"))
		// a terminal in the folder under the cursor (the first row: Documents)
		session.key(s, .Home)
		session.key(s, .F4, {.Shift})
		testing.expect(t, len(app.opened) > 0 && strings.has_suffix(app.opened[len(app.opened) - 1], "Documents"), "a terminal in Documents")

		// tabs: three, the others closed
		context.allocator = runtime.heap_allocator()
		p := current_panel(app)
		tab_open(app, p, fs.join(dir, "Documents", context.temp_allocator), p.active + 1)
		tab_open(app, p, fs.join(dir, "Photos", context.temp_allocator), p.active + 1)
		testing.expect_value(t, len(p.tabs), 3)
		act_tab_close_others(app)
		testing.expect_value(t, len(p.tabs), 1)
		testing.expect_value(t, current_tab(app).path, fs.join(dir, "Photos", context.temp_allocator))
		_ = tab
	})
}

@(test)
test_batch_rename :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		// the two reports and notes.txt
		for name in ([]string{"notes.txt", "report 2.pdf", "report 10.pdf"}) {
			testing.expect(t, folder_cursor_to_name(&tab.folder, name))
			folder_pick(&tab.folder, tab.folder.cursor, toggle = true)
		}
		testing.expect_value(t, tab.folder.count, 3)
		session.key(s, .F2)
		session.frames(s, 2)
		testing.expect(t, app.batch.open)
		session.type_text(s, "doc {n:2}.{ext}")
		session.frames(s, 2)
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !app.batch.open)
		names := shown_names(tab)
		testing.expectf(t, slice.contains(names, "doc 01.txt") || slice.contains(names, "doc 01.pdf"), "numbered (%s)", app.status)
		testing.expect(t, !slice.contains(names, "notes.txt") && !slice.contains(names, "report 2.pdf"))
		// undone at once: the three names back
		session.key(s, .Z, {.Ctrl})
		wait_read(s)
		names = shown_names(tab)
		testing.expect(t, slice.contains(names, "notes.txt") && slice.contains(names, "report 2.pdf") && slice.contains(names, "report 10.pdf"), "undone")
	})
}

@(test)
test_drag_and_drop :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		// a drop of another program's (two files) on the row of Documents: a move (one volume)
		other := testkit.temp_folder(t, "classeur_other")
		a := fs.join(other, "a.txt", context.temp_allocator)
		b := fs.join(other, "b.txt", context.temp_allocator)
		_ = os.write_entire_file(a, transmute([]u8)string("a"))
		_ = os.write_entire_file(b, transmute([]u8)string("b"))
		testing.expect(t, folder_cursor_to_name(&tab.folder, "Documents"))
		session.frames(s, 2)
		at: [2]f32
		for z in app.drop_zones_last { if strings.has_suffix(z.path, fs.SEPARATOR_STRING + "Documents") { at = (z.rect.min + z.rect.max) * 0.5 } }
		testing.expect(t, at != {}, "Documents takes a drop")
		data: platform.Drag_Data
		append(&data.files, a, b)
		defer delete(data.files)
		context.allocator = runtime.heap_allocator()
		testing.expect_value(t, drop_answer(app, .Drop_Over, at, {}, {.Copy, .Move}), Maybe(platform.Drop_Effect)(nil))   // (no data yet)
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Copy, .Move})
		platform.drop_inject(app.main.win, .Drop_Over, at, nil, {.Copy, .Move})
		session.frames(s, 1)
		testing.expect(t, strings.has_suffix(app.drop_hover, fs.SEPARATOR_STRING + "Documents"), "the target marked")
		platform.drop_inject(app.main.win, .Drop, at, nil, {.Copy, .Move})
		session.frames(s, 1)
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Documents/a.txt", context.temp_allocator)), "a.txt moved in")
		testing.expect(t, !fs.exists(a), "and gone from where it was")
		// Ctrl: a copy; on the list (the folder itself) with files already there: refused
		_ = os.write_entire_file(a, transmute([]u8)string("a"))
		clear(&data.files)
		append(&data.files, a)
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Copy, .Move}, {.Ctrl})
		platform.drop_inject(app.main.win, .Drop, at, nil, {.Copy, .Move}, {.Ctrl})
		session.frames(s, 1)
		// (a.txt is in Documents already: the copy asks; Escape skips it)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return job_asking((^App)(s.user)) != nil }, "the question")
		session.frames(s, 2)
		session.key(s, .Escape)
		wait_jobs(s)
		testing.expect(t, fs.exists(a), "copied: the source stays")
		// a row dragged out of the list onto the row of Photos (the drag of the system, scripted): moved
		session.key(s, .Escape)
		point_at(t, tab, "archive.zip")
		session.frames(s, 2)
		from, to: [2]f32
		for z in app.drop_zones_last { if strings.has_suffix(z.path, fs.SEPARATOR_STRING + "Photos") { to = (z.rect.min + z.rect.max) * 0.5 } }
		from = (tab.cursor_rect.min + tab.cursor_rect.max) * 0.5
		from.x = tab.cursor_rect.min.x + 120
		// (in the window: classeur's own, Photos lit and the ghost beside the pointer while it is held)
		session.press(s, from)
		session.move(s, from + {0, 12})
		session.move(s, to)
		session.frames(s, 2)
		testing.expect(t, strings.has_suffix(app.drop_hover, fs.SEPARATOR_STRING + "Photos"), "Photos lit")
		testing.expect(t, session.find(s, "file_ghost") != nil, "the ghost")
		when SHOTS { session.save_png(s, "file_drag.png") }
		session.release(s, to)
		session.frames(s, 2)
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/archive.zip", context.temp_allocator)), "dragged into Photos")
		testing.expect(t, !app.file_drag && len(app.drag_paths) == 0, "the drag over")
		// to the window's edge: the system's drag takes it (scripted: back over Photos, let go there)
		point_at(t, tab, "notes.txt")
		session.frames(s, 2)
		from = {tab.cursor_rect.min.x + 120, (tab.cursor_rect.min.y + tab.cursor_rect.max.y) * 0.5}
		platform.drag_script(app.main.win, {{to, {}}, {to, {}}})
		session.press(s, from)
		session.move(s, from + {0, 12})
		session.move(s, {2, from.y})
		session.release(s, {2, from.y})
		session.frames(s, 2)
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/notes.txt", context.temp_allocator)), "out and back by the system's drag")

		// files of this folder dropped on its own list: nothing
		here := fs.join(dir, "notes.txt", context.temp_allocator)
		testing.expect_value(t, drop_effect_for_test(app, {here}, dir), Maybe(platform.Drop_Effect)(nil))
		testing.expect_value(t, drop_effect_for_test(app, {fs.join(dir, "Documents", context.temp_allocator)}, fs.join(dir, "Documents/Sub", context.temp_allocator)), Maybe(platform.Drop_Effect)(nil))
	})
}

@(test)
test_band :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 700})
		tab := current_tab(app)
		session.frames(s, 2)
		lb := ui.box_from_key(tab.vl.key)
		testing.expect(t, lb != nil)
		// from the empty part under the rows, up over the last three
		n := len(tab.folder.shown)
		bottom := lb.rect.min.y + tab.vl.offsets[n] - lb.view_off.y
		from := [2]f32{lb.rect.min.x + 200, bottom + 40}
		to := [2]f32{lb.rect.min.x + 250, lb.rect.min.y + tab.vl.offsets[n - 3] - lb.view_off.y + 5}
		session.press(s, from)
		session.move(s, from + {0, -10})
		session.move(s, to)
		session.frames(s, 1)
		testing.expect_value(t, tab.folder.count, 3)
		session.release(s, to)
		session.frames(s, 2)
		testing.expect_value(t, tab.folder.count, 3)
		testing.expect(t, !app.band.active)
	})
}

@(test)
test_types :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		tab := current_tab(app)
		f := &tab.folder
		all := len(f.shown)
		context.allocator = runtime.heap_allocator()
		// the PDFs out: two rows fewer
		folder_toggle_type(f, "pdf")
		testing.expect_value(t, len(f.shown), all - 2)
		testing.expect(t, !slice.contains(shown_names(tab), "report 2.pdf"))
		// the folders alone
		folder_set_kinds(f, .Folders)
		for n in shown_names(tab) { testing.expect(t, n == "Documents" || n == "Photos" || n == "Projects", n) }
		// back to all
		folder_set_kinds(f, .All)
		folder_all_types(f, true)
		testing.expect_value(t, len(f.shown), all)
		types := folder_types(f)
		testing.expect(t, len(types) > 0 && types[0].ext == "pdf" && types[0].count == 2, "the most common type first")
		_ = s
		_ = app
	})
}

@(test)
test_tab_drag :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		p := app.panels[0]
		tab_open(app, p, fs.join(dir, "Documents", context.temp_allocator), 1)
		tab_open(app, p, fs.join(dir, "Photos", context.temp_allocator), 2)
		wait_read(s)
		session.frames(s, 2)
		// the first tab dragged past the third: it goes last
		first, last: ui.Rect
		for tr in app.tab_rects_last { if tr.index == 0 { first = tr.rect }; if tr.index == 2 { last = tr.rect } }
		from := (first.min + first.max) * 0.5
		to := [2]f32{last.max.x - 4, from.y}
		session.press(s, from)
		session.move(s, from + {20, 0})
		session.move(s, to)
		session.release(s, to)
		session.frames(s, 2)
		testing.expect_value(t, fs.base(p.tabs[2].path), fs.base(dir))
		// the tab dragged to the right quarter of the panel: a new panel with it
		pr := app.panel_rects[0]
		from = (app.tab_rects_last[0].rect.min + app.tab_rects_last[0].rect.max) * 0.5
		to = {pr.max.x - 20, (pr.min.y + pr.max.y) * 0.5}
		session.press(s, from)
		session.move(s, from + {20, 0})
		session.move(s, to)
		session.release(s, to)
		session.frames(s, 2)
		testing.expect_value(t, len(app.panels), 2)
		testing.expect_value(t, len(app.panels[0].tabs), 2)
		testing.expect_value(t, len(app.panels[1].tabs), 1)
	})
}

// No two commands share a key; every command has one.
@(test)
test_keys :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		seen := make(map[Shortcut]string, context.temp_allocator)
		for c in COMMANDS {
			testing.expectf(t, c.keys[0].key != .None, "%s has a key", c.id)
			for k in c.keys {
				if k.key == .None { continue }
				if other, taken := seen[k]; taken { testing.expectf(t, false, "%s and %s share %s", other, c.id, ui.chord_text(k)) }
				seen[k] = c.id
			}
		}
	})
}

@(test)
test_layouts :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		app.session_path = strings.clone(fs.join(dir, ".session", context.temp_allocator))
		// two panels saved as "work"
		panel_open(app, fs.join(dir, "Documents", context.temp_allocator))
		wait_read(s)
		layout_save(app, "work")
		// back to one panel, then the layout again
		for len(app.panels) > 1 { panel_close(app, app.panels[len(app.panels) - 1]) }
		testing.expect_value(t, len(app.panels), 1)
		testing.expect(t, layout_open(app, "work"))
		wait_read(s)
		testing.expect_value(t, len(app.panels), 2)
		testing.expect_value(t, panel_tab(app.panels[1]).path, fs.join(dir, "Documents", context.temp_allocator))
		// read again from its file, once its writer has written it (on a worker)
		file_writer_flush(&app.layouts_writer)
		layouts_free(&app.layouts)
		layouts_load(app)
		testing.expect(t, layout_open(app, "work"))
		wait_read(s)
		testing.expect_value(t, len(app.panels), 2)
	})
}

// classeur install, status, uninstall, on the test's own folders (never the person's desktop).
@(test)
test_install :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		when ODIN_OS != .Linux { return }
		root := testkit.temp_folder(t, "classeur_install")
		for name in ([]string{"APPLICATIONS_DIR", "ICONS_DIR", "BIN_DIR", "AUTOSTART_DIR", "MENU_DIR"}) {
			dir := fs.join(root, name, context.temp_allocator)
			_ = os.make_directory_all(dir)
			os.set_env(fmt.tprintf("CLASSEUR_DESKTOP_%s", name), dir)
		}
		defer for name in ([]string{"APPLICATIONS_DIR", "ICONS_DIR", "BIN_DIR", "AUTOSTART_DIR", "MENU_DIR"}) { os.unset_env(fmt.tprintf("CLASSEUR_DESKTOP_%s", name)) }
		entry := fs.join(root, "APPLICATIONS_DIR/classeur.desktop", context.temp_allocator)
		testing.expect_value(t, cmd_install({}), 0)
		testing.expect(t, fs.exists(entry), "the menu's entry")
		testing.expect(t, fs.exists(fs.join(root, "BIN_DIR/classeur", context.temp_allocator)), "on the PATH")
		text, _ := os.read_entire_file(entry, context.temp_allocator)
		testing.expect(t, strings.contains(string(text), "FileManager"), "a file manager for the menus")
		testing.expect_value(t, cmd_status({}), 0)
		testing.expect_value(t, cmd_uninstall({}), 0)
		testing.expect(t, !fs.exists(entry), "taken away")
	})
}

// The zoom's slider: a click on the percent shows it; dragged up, the view goes to the largest step.
@(test)
test_zoom_slider :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.frames(s, 2)
		session.click(s, "zoom")
		session.frames(s, 3)
		slider := session.get(s, "slider")
		r := slider.rect
		from := [2]f32{(r.min.x + r.max.x) * 0.5, r.max.y - 10}
		session.press(s, from)
		session.move(s, {from.x, (r.min.y + r.max.y) * 0.5})
		session.move(s, {from.x, r.min.y + 2})
		when SHOTS { session.save_png(s, "zoom.png") }
		session.release(s, {from.x, r.min.y + 2})
		session.frames(s, 2)
		testing.expect_value(t, tab.zoom, len(ZOOMS) - 1)
		// a click on a step's row: that step
		session.click(s, "zstep2")
		session.frames(s, 2)
		testing.expect_value(t, tab.zoom, 2)
		when SHOTS { session.save_png(s, "zoom_steps.png") }
	})
}

// A panel below another: its own column, its tabs at its top; the session keeps it; a tab dragged to a panel's bottom
// quarter makes one.
@(test)
test_split_below :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 800})
		session.key(s, .J, {.Ctrl, .Shift})
		wait_read(s)
		session.frames(s, 2)
		testing.expect_value(t, len(app.panels), 2)
		testing.expect(t, app.panels[1].below)
		top, bottom := app.panel_rects[0], app.panel_rects[1]
		testing.expect(t, bottom.min.y >= top.max.y, "under it")
		testing.expect_value(t, bottom.min.x, top.min.x)
		testing.expect(t, session.find(s, "below_tabs") != nil, "its tabs at its top")
		when SHOTS { session.save_png(s, "split.png") }
		// a column at the right of both: Ctrl+Shift+D from the top panel goes after the column
		app.focus = 0
		session.key(s, .D, {.Ctrl, .Shift})
		wait_read(s)
		session.frames(s, 2)
		testing.expect_value(t, len(app.panels), 3)
		testing.expect(t, app.panels[1].below && !app.panels[2].below, "the one below stays in its column")
		// the session's lines keep it
		context.allocator = runtime.heap_allocator()
		b := strings.builder_make(context.temp_allocator)
		panels_text(app, &b)
		testing.expect(t, strings.contains(strings.to_string(b), " below\n"))
		// the top panel closed: the one below is the top of its column
		panel_close(app, app.panels[0])
		testing.expect(t, !app.panels[0].below)
	})
}

// The details' columns: hidden and shown again from the header's menu, a title dragged to another place.
@(test)
test_columns :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1400, 700})
		session.frames(s, 2)
		testing.expect_value(t, columns_text(app), "Modified Type Folders Files Size")
		// the header's menu: Type off
		session.click(s, "header", .Right)
		session.frames(s, 2)
		testing.expect(t, ui.ctx_menu_any_open(), "the columns' menu")
		// (its item Type: a row's label, not the column's title nor the menu's search field)
		item: ^ui.Box
		for k in 0 ..< 8 {
			b := session.find_text(s, "Type", k)
			if b == nil { break }
			if b.name == "lbl" { item = b; break }
		}
		testing.expect(t, item != nil, "the item Type")
		if item != nil { session.click_at(s, (item.rect.min + item.rect.max) * 0.5) }
		session.frames(s, 2)
		testing.expect_value(t, columns_text(app), "Modified Folders Files Size")
		testing.expect(t, session.find(s, "hd_2") == nil, "no Type column")
		session.key(s, .Escape)
		// Size's title dragged before Modified's
		session.frames(s, 2)
		modified := session.get(s, "hd_1").rect
		from := title_point(s, .Size)
		to := [2]f32{modified.min.x + 4, from.y}
		session.press(s, from)
		session.move(s, from - {20, 0})
		session.move(s, to)
		session.release(s, to)
		session.frames(s, 2)
		testing.expect_value(t, columns_text(app), "Size Modified Folders Files")
		testing.expect_value(t, tab_folder_sort_key(app), fs.Sort_Key.Name)   // (a drag sorts nothing)
	})
}

@(private = "file")
columns_text :: proc(app: ^App) -> string {
	b := strings.builder_make(context.temp_allocator)
	for k in app.columns.order {
		if k == 0 || !app.columns.shown[k] { continue }
		fmt.sbprintf(&b, strings.builder_len(b) > 0 ? " %v" : "%v", Detail(k))
	}
	return strings.to_string(b)
}

@(private = "file")
tab_folder_sort_key :: proc(app: ^App) -> fs.Sort_Key { return current_tab(app).folder.sort.key }

// A tab dragged out of the window: let go nowhere, it becomes a window of its own (headless: noted) and leaves this one;
// a classeur tab dropped from another window opens here.
@(test)
test_tab_out :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		p := app.panels[0]
		documents := strings.clone(fs.join(dir, "Documents", context.temp_allocator))
		tab_open(app, p, documents, 1)
		wait_read(s)
		session.frames(s, 2)
		var_rect: ui.Rect
		for tr in app.tab_rects_last { if tr.index == 1 { var_rect = tr.rect } }
		from := (var_rect.min + var_rect.max) * 0.5
		// (the scripted drag of the system ends outside the window: no window of classeur takes it)
		platform.drag_script(app.main.win, {{{-50, -50}, {}}, {{-60, -60}, {}}})
		session.press(s, from)
		session.move(s, from + {0, 30})
		session.move(s, {from.x, -20})
		// (its window starts on a worker: the tab leaves when that lands)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).panels[0].tabs) == 1 }, "the tab gone to its window")
		testing.expect_value(t, len(p.tabs), 1)
		testing.expect(t, len(app.opened) > 0 && app.opened[len(app.opened) - 1] == strings.concatenate({"window:", documents}, context.temp_allocator), "a window of its own")
		session.release(s, {from.x, -20})
		// a tab of another window dropped on this one's tab row: opened here
		photos := fs.join(dir, "Photos", context.temp_allocator)
		data: platform.Drag_Data
		append(&data.custom, platform.Drag_Entry{TAB_MIME, tab_mime_data(1, 7, photos)})   // (another process's tab)
		defer delete(data.custom)
		at := (app.tab_rects_last[0].rect.min + app.tab_rects_last[0].rect.max) * 0.5
		// (past the first tab's middle: after it; its ghost there while it is over the row)
		at.x = app.tab_rects_last[0].rect.max.x - 4
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Move})
		platform.drop_inject(app.main.win, .Drop_Over, at, nil, {.Move})
		session.frames(s, 3)
		testing.expect(t, session.find(s, "tab_land") != nil, "its ghost in the row")
		when SHOTS { session.save_png(s, "tab_coming.png") }
		platform.drop_inject(app.main.win, .Drop, at, nil, {.Move})
		session.frames(s, 2)
		wait_read(s)
		testing.expect_value(t, len(p.tabs), 2)
		testing.expect_value(t, p.tabs[1].path, photos)
		testing.expect_value(t, current_tab(app).path, photos)
		testing.expect(t, !app.tab_coming && session.find(s, "tab_land") == nil, "the ghost gone")
		delete(documents)
	})
}

// A key of one's own from the palette: a sequence (Ctrl+M, then T) bound to "New tab", which then opens one; an alias.
@(test)
test_own_keys :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		session.key(s, .P, {.Ctrl, .Shift})
		session.type_text(s, "new tab")
		session.frames(s, 2)
		testing.expect_value(t, COMMANDS[palette_first(app)].id, "tab_new")
		session.key(s, .Return, {.Ctrl})
		session.frames(s, 1)
		testing.expect(t, app.palette.recording >= 0, "recording")
		session.key(s, .M, {.Ctrl})
		session.key(s, .T)
		session.key(s, .Return)
		session.frames(s, 1)
		testing.expect_value(t, app.palette.recording, -1)
		testing.expect_value(t, binding_text(app.keymap.custom["tab_new"]), "Ctrl+M, T")
		testing.expect_value(t, ui.field_string(&app.palette.field), "new tab")
		// an alias: "ntab" for it (the letters of its words: "nt" alone is in "Font size", a whole match first)
		ui.field_set(&app.palette.field, "ntab")
		session.frames(s, 1)
		session.key(s, .Return, {.Alt})
		session.key(s, .Escape)
		testing.expect(t, alias_command(app, "ntab") != nil && alias_command(app, "ntab").id == "tab_new")
		// the sequence opens a tab; Ctrl+T alone no longer does (its own keys gave way)
		before := len(current_panel(app).tabs)
		session.key(s, .M, {.Ctrl})
		session.key(s, .T)
		session.frames(s, 1)
		testing.expect_value(t, len(current_panel(app).tabs), before + 1)
		session.key(s, .T, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, len(current_panel(app).tabs), before + 1)
		// the preference holds them, read again as they were
		testing.expect_value(t, config.string_of(&app.prefs, "keys.custom"), "tab_new=Ctrl+M, T")
		b, ok := binding_parse("Ctrl+M, T")
		testing.expect(t, ok && b == app.keymap.custom["tab_new"])
	})
}

// The tree view: Right opens the folder at the cursor in place (its entries under it, a step in), Left closes it.
@(test)
test_tree :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .E, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, tab.tree)
		point_at(t, tab, "Documents")
		session.key(s, .Right)
		wait_read(s)
		names := shown_names(tab)
		at, _ := slice.linear_search(names, "Documents")
		budget := fs.join("Documents", "budget.xlsx", context.temp_allocator)
		letter := fs.join("Documents", "letter.odt", context.temp_allocator)
		testing.expectf(t, at + 2 < len(names) && names[at + 1] == budget && names[at + 2] == letter, "under it, in order: %v", names)
		testing.expect_value(t, names[at + 3], "Photos")
		when SHOTS { session.frames(s, 2); session.save_png(s, "tree.png") }
		// Left on one of its files: the cursor to the folder; Left again: closed
		testing.expect(t, folder_cursor_to_name(&tab.folder, letter))
		session.key(s, .Left)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "Documents")
		session.key(s, .Left)
		wait_read(s)
		testing.expect(t, !slice.contains(shown_names(tab), letter), "closed")
	})
}

// Group by type: the folders, then each extension (the sort's order in each), a title above each group's first row.
@(test)
test_group :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .N6, {.Ctrl, .Alt})
		session.frames(s, 3)
		testing.expect_value(t, tab.group, Group_By.Type)
		testing.expect_value(t, fmt.tprint(shown_names(tab)), fmt.tprint([]string{"Documents", "Photos", "Projects", "report 2.pdf", "report 10.pdf", "notes.txt", "archive.zip"}))
		testing.expect(t, session.find_text(s, "PDF") != nil && session.find_text(s, "Folders") != nil, "the groups' titles")
		when SHOTS { session.save_png(s, "group.png") }
		// the same key again: no groups
		session.key(s, .N6, {.Ctrl, .Alt})
		session.frames(s, 2)
		testing.expect_value(t, tab.group, Group_By.None)
		testing.expect_value(t, shown_names(tab)[3], "archive.zip")
	})
}

// A group folded by a click on its title: its first row alone, as the title; a click again: all of it.
@(test)
test_group_fold :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .N6, {.Ctrl, .Alt})
		session.frames(s, 3)
		testing.expect_value(t, len(tab.folder.shown), 7)
		session.click_text(s, "PDF")
		session.frames(s, 3)
		testing.expect_value(t, len(tab.folder.shown), 6)   // (report 10.pdf folded under the title on report 2.pdf's row)
		testing.expect(t, !slice.contains(shown_names(tab), "report 10.pdf"))
		when SHOTS { session.save_png(s, "group_folded.png") }
		session.click_text(s, "PDF")
		session.frames(s, 3)
		testing.expect_value(t, len(tab.folder.shown), 7)
	})
}

// The tree in the names view (Right opens) and in the columns view (the chevron opens).
@(test)
test_tree_views :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		letter := fs.join("Documents", "letter.odt", context.temp_allocator)
		session.key(s, .N3, {.Ctrl})
		session.key(s, .E, {.Ctrl, .Shift})
		wait_read(s)
		point_at(t, tab, "Documents")
		session.key(s, .Right)
		wait_read(s)
		testing.expect(t, slice.contains(shown_names(tab), letter), "the names view: opened")
		session.key(s, .Left)
		wait_read(s)
		testing.expect(t, !slice.contains(shown_names(tab), letter))
		// the columns view: its chevron
		session.key(s, .N4, {.Ctrl})
		session.frames(s, 3)
		session.click(s, "tree_Documents")
		wait_read(s)
		session.frames(s, 2)
		testing.expect(t, slice.contains(shown_names(tab), letter), "the columns view: opened")
		when SHOTS { session.save_png(s, "tree_columns.png") }
	})
}

// The columns view: the names filled column by column, scrolled sideways (End, the wheel), Right a column further.
@(test)
test_columns_view :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		names := make([dynamic]string, context.temp_allocator)
		for i in 0 ..< 60 { append(&names, fmt.tprintf("file %02d.txt", i)) }
		dir := make_fixture(t, names[:])
		s, app := start(t, {dir}, size = {900, 500})
		tab := current_tab(app)
		session.key(s, .N4, {.Ctrl})
		session.frames(s, 4)
		per := tab.grid_cols
		testing.expect(t, per > 2 && per < 60, "several columns")
		a := session.get(s, "item0").rect
		b := session.get(s, "item1").rect
		c := session.get(s, fmt.tprintf("item%d", per)).rect
		testing.expect(t, b.min.y > a.min.y && b.min.x == a.min.x, "the second name under the first")
		testing.expect(t, c.min.x > a.min.x && c.min.y == a.min.y, "the next column starts at the top")
		// End: the last name, the view scrolled sideways to it
		session.key(s, .End)
		session.frames(s, 8)
		box := ui.box_from_key(tab.cols_key)
		testing.expect(t, box.view_target.x > 0, "scrolled sideways")
		testing.expect_value(t, tab.folder.cursor, 59)
		// Home, then Right: a column further
		session.key(s, .Home)
		session.key(s, .Right)
		testing.expect_value(t, tab.folder.cursor, per)
		// the wheel scrolls sideways
		session.key(s, .Home)
		session.frames(s, 8)
		before := box.view_target.x
		session.wheel(s, (box.rect.min + box.rect.max) * 0.5, {0, 3})
		session.frames(s, 2)
		testing.expect(t, ui.box_from_key(tab.cols_key).view_target.x > before, "the wheel down: the next columns")
	})
}

// The jobs' window: a copy that failed, its error shown; Retry once the file is there copies it.
@(test)
test_jobs_view :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		missing := fs.join(dir, "later.txt", context.temp_allocator)
		job_add(app, .Copy, {missing}, fs.join(dir, "Documents", context.temp_allocator))
		wait_jobs(s)
		testing.expect_value(t, sync.atomic_load(&app.jobs.list[0].state), Job_State.Failed)
		session.key(s, .J, {.Ctrl, .Alt})
		session.frames(s, 2)
		testing.expect(t, app.jobs_view.open)
		testing.expect(t, session.find_text(s, "1 failed") != nil, "it says so")
		when SHOTS { session.save_png(s, "jobs.png") }
		_ = os.write_entire_file(missing, transmute([]u8)string("now"))
		session.click(s, "retry")
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Documents/later.txt", context.temp_allocator)), "retried: copied")
		testing.expect_value(t, len(app.jobs.list), 2)
	})
}

// The jobs' view goes to the background and comes back: it opens by itself for a job that runs on, Background sends it
// away, Ctrl+Alt+J brings it back.
@(test)
test_jobs_background :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		// (notes.txt into Documents twice: the second asks, so it runs on)
		documents := fs.join(dir, "Documents", context.temp_allocator)
		notes := fs.join(dir, "notes.txt", context.temp_allocator)
		job_add(app, .Copy, {notes}, documents)
		wait_jobs(s)
		job_add(app, .Copy, {notes}, documents)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).jobs_view.open }, "the view opened by itself")
		// (the question answered: the job ends; the view stays until it is sent away)
		session.wait_box(s, "skip")
		session.click(s, "skip")
		wait_jobs(s)
		testing.expect(t, app.jobs_view.open, "still shown")
		session.click(s, "jobs_bg")
		session.frames(s, 1)
		testing.expect(t, !app.jobs_view.open, "in the background")
		session.key(s, .J, {.Ctrl, .Alt})
		session.frames(s, 2)
		testing.expect(t, app.jobs_view.open, "back")
		when SHOTS { session.save_png(s, "jobs_open.png") }
	})
}

// The path field's suggestions: the folders of the path typed, Down then Enter goes to one; a click too.
@(test)
test_address_suggest :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .L, {.Ctrl})
		session.frames(s, 1)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, fmt.tprintf("%s%s", dir, fs.SEPARATOR_STRING))
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).goto.names) > 0 }, "the folder read")
		// (the folder is listed on a worker: the suggestions follow when it is read)
		session.wait_box(s, "sugg0")
		when SHOTS { session.save_png(s, "address.png") }
		// Down twice: Photos (Documents, Photos, Projects)
		session.key(s, .Down)
		session.key(s, .Down)
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "Photos", context.temp_allocator))
		// a click on one
		session.key(s, .L, {.Ctrl})
		session.frames(s, 1)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, fmt.tprintf("%s%sPro", dir, fs.SEPARATOR_STRING))
		session.wait_until(s, proc(s: ^session.Session) -> bool { return strings.has_suffix((^App)(s.user).goto.dir, fs.base((^App)(s.user).home)) || len((^App)(s.user).goto.names) > 0 }, "read")
		session.wait_box(s, "sugg0")
		session.click(s, "sugg0")
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(dir, "Projects", context.temp_allocator))
	})
}

// The palette: nothing typed, every command under its group's title, the ones run last first; the wheel scrolls.
@(test)
test_palette_groups :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 800})
		session.key(s, .P, {.Ctrl, .Shift})
		session.type_text(s, "hidden files")
		session.key(s, .Return)
		session.frames(s, 1)
		session.key(s, .P, {.Ctrl, .Shift})
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Recent") != nil && session.find_text(s, "Go") != nil, "the groups' titles")
		testing.expect_value(t, COMMANDS[palette_line_command(app, 0)].id, "hidden")
		when SHOTS { session.save_png(s, "palette_groups.png") }
		rows := session.get(s, "palette_list")
		session.wheel(s, (rows.rect.min + rows.rect.max) * 0.5, {0, 3})
		session.frames(s, 2)
		session.frames(s, 20)
		testing.expect(t, session.get(s, "palette_list").view_off.y > 0, "scrolled")
		session.key(s, .Escape)
	})
}

// classeur's Setup screen opens over the window (it only reads where an install would go: nothing is installed, no
// answer is written).
@(test)
test_setup_dialog :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 720})
		context.allocator = runtime.heap_allocator()
		act_setup(app)
		session.frames(s, 4)
		testing.expect(t, app.setup.open, "open")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).setup.known }, "the install read")
		session.frames(s, 2)
		testing.expect(t, session.find(s, "setup_install") != nil, "an install offered")
		when SHOTS { session.save_png(s, "setup.png") }
		// Escape closes it without an answer (headless: nothing kept in the person's config)
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.setup.open, "closed")
		// the entry's menu, with its icons
		entry_menu_open(app, current_tab(app), {300, 200})
		session.frames(s, 3)
		when SHOTS { session.save_png(s, "menu.png") }
		// typed: the field shows it, the lines that have it stay
		session.type_text(s, "term")
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "term") != nil, "the query shown")
		testing.expect(t, session.find_text(s, "Cut") == nil, "Cut filtered out")
		when SHOTS { session.save_png(s, "menu_typed.png") }
		session.key(s, .Escape)
	})
}

// A row's icon is its box (File Pilot's): the pointer over it shows the box, a click checks the row and keeps the
// others; the rows checked among others show their box; the header's box, over the icons, checks every row or none.
@(test)
test_icon_checks :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "box") == nil, "icons, no box")
		session.hover(s, "check1")
		session.frames(s, 2)
		testing.expect(t, session.find(s, "box") != nil, "the pointer over an icon shows its box")
		// (a click on the icon itself: its row is the box clicked)
		session.click_at(s, session.center(session.get(s, "check1")))
		session.click_at(s, session.center(session.get(s, "check3")))
		session.frames(s, 2)
		testing.expect_value(t, tab.folder.count, 2)
		session.leave(s)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "box", 1) != nil, "the rows checked among others show their box")
		when SHOTS { session.save_png(s, "icon_checks.png") }
		session.click(s, "check_all")
		session.frames(s, 1)
		testing.expect_value(t, tab.folder.count, 0)
		session.click(s, "check_all")
		session.frames(s, 1)
		testing.expect_value(t, tab.folder.count, len(tab.folder.shown))
	})
}

// The settings' rounding is the whole interface's (the toolkit's boxes and classeur's own drawings), the density too; the
// Updates page has the line of update.auto.
@(test)
test_settings_look :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 800})
		context.allocator = runtime.heap_allocator()
		testing.expect_value(t, ui.rounding(&app.main.state), f32(ROUNDING))
		_ = config.set_from_string(&app.prefs, "look.rounding", "1.5", .User)
		_ = config.set_from_string(&app.prefs, "look.density", "compact", .User)
		settings_apply(app)
		testing.expect_value(t, ui.rounding(&app.main.state), f32(1.5))
		testing.expect(t, app.settings.compact, "compact")
		session.click(s, "check1")
		session.click(s, "check2")
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		session.frames(s, 3)
		when SHOTS { session.save_png(s, "round_window.png") }
		session.key(s, .Comma, {.Ctrl})
		session.frames(s, 3)
		when SHOTS { session.save_png(s, "settings_round.png") }
		// the rounding's slider held at its start: square at once, before it is let go
		sl := session.get(s, "sl")
		from := session.center(sl)
		to := [2]f32{sl.rect.min.x + 1, from.y}
		session.press(s, from)
		session.move(s, to)
		session.frames(s, 2)
		testing.expectf(t, ui.rounding(&app.main.state) < 0.2, "shown while held: %v", ui.rounding(&app.main.state))
		session.release(s, to)
		session.frames(s, 2)
		testing.expect(t, config.float_of(&app.prefs, "look.rounding") < 0.2, "written at the release")
		// held again, and the settings closed meanwhile: what it showed goes back to what is written
		written := ui.rounding(&app.main.state)
		session.press(s, to)
		session.move(s, {sl.rect.max.x - 1, from.y})
		session.frames(s, 2)
		testing.expect(t, ui.rounding(&app.main.state) > 1.5, "shown")
		app.options.open = false
		session.frames(s, 2)
		testing.expect_value(t, ui.rounding(&app.main.state), written)
		session.release(s, {sl.rect.max.x - 1, from.y})
		session.key(s, .Comma, {.Ctrl})
		session.frames(s, 2)
		session.type_text(s, "update")
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Update") != nil, "the update line")
		when SHOTS { session.save_png(s, "settings_update.png") }
		session.key(s, .Escape)
		session.key(s, .Escape)
	})
}

// The palette opens with Ctrl+K, as in the other programs, and the "…" menu offers it with its keys.
@(test)
test_palette_keys :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		session.key(s, .K, {.Ctrl})
		session.frames(s, 2)
		testing.expect(t, app.palette.open, "Ctrl+K")
		session.key(s, .Escape)
		session.frames(s, 2)
		panel_menu_open(app, {300, 120})
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Command palette") != nil && session.find_text(s, "Ctrl+K") != nil, "the menu's line and its keys")
		session.key(s, .Escape)
	})
}

// The columns' filters: the Size column's funnel leaves the folders out, its menu counts each group; the Modified column's
// leaves out today's; the funnels are lit while they filter. (A menu's lines are chosen by the keyboard.)
@(test)
test_column_filters :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		session.frames(s, 2)
		n := len(tab.folder.shown)
		session.hover(s, "hd_5")
		session.frames(s, 2)
		session.click(s, "filter_Size")
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "Tiny (under 16 KB)") != nil, "the size groups")
		when SHOTS { session.save_png(s, "filter_size.png") }
		session.key(s, .Down, repeat = 2)   // (Every size, Folders)
		session.key(s, .Return)
		session.frames(s, 2)
		testing.expect_value(t, len(tab.folder.shown), n - 3)
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "filter_Size") != nil, "lit while it filters")
		// today's rows out: none left (the fixture is made now)
		session.hover(s, "hd_1")
		session.frames(s, 2)
		session.click(s, "filter_Modified")
		session.frames(s, 2)
		session.key(s, .Down, repeat = 2)   // (Every date, Today)
		session.key(s, .Return)
		session.frames(s, 2)
		testing.expect_value(t, len(tab.folder.shown), 0)
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "No row fits the filters") != nil, "said")
		folder_all_ranks(&tab.folder, .Date)
		testing.expect_value(t, len(tab.folder.shown), n - 3)
		// another folder: every row again (the columns' filters were this folder's)
		context.allocator = runtime.heap_allocator()
		tab_go(app, tab, fs.join(dir, "Documents", context.temp_allocator))
		wait_read(s)
		testing.expect(t, tab.folder.dates_off == {} && tab.folder.sizes_off == {}, "cleared")
	})
}

// The sidebar's sections are moved: a heading's menu (Move to the top), a heading dragged under another (a line says
// where it lands); the order is kept in side.order.
@(test)
test_side_order :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		testing.expect_value(t, app.side_order[0], Side_Section.Recents)
		// the menu: Places to the top (Move up, Move down, -, Move to the top: Places is last, Move down is not offered)
		session.click(s, "sec_Places", .Right)
		session.frames(s, 2)
		session.key(s, .Down)   // (Move up)
		session.key(s, .Down)   // (Move to the top: Move down is disabled)
		session.key(s, .Return)
		session.frames(s, 2)
		testing.expect_value(t, app.side_order[0], Side_Section.Places)
		testing.expect_value(t, config.string_of(&app.prefs, "side.order"), "places,recents,bookmarks,storage,network")
		// a drag: Places, now first, let go under Network's heading (the last)
		from := session.center(session.get(s, "sec_Places"))
		to := session.center(session.get(s, "sec_Network")) + {0, 30}
		session.press(s, from)
		session.move(s, from + {0, 12})
		session.move(s, to)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "side_drag_line") != nil, "the line where it lands")
		when SHOTS { session.save_png(s, "side_drag.png") }
		session.release(s, to)
		session.frames(s, 2)
		testing.expect_value(t, app.side_order[len(Side_Section) - 1], Side_Section.Places)
		// its keys: the section last touched (Places, dragged) a place up, over Network (shown with no share too)
		session.key(s, .Up, {.Ctrl, .Alt, .Shift})
		session.frames(s, 1)
		at := map[Side_Section]int{}
		defer delete(at)
		for x, i in app.side_order { at[x] = i }
		testing.expectf(t, at[.Places] + 1 == at[.Network], "Places just over Network: %v", app.side_order)
	})
}

// Ctrl+wheel through the zoom's steps: at every frame of the moves, every icon shown has its picture (a size not made yet
// shows the nearest one made): no icon goes blank.
@(test)
test_zoom_icons_stay :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		wait_read(s)
		// (a picture of the system's, or Lucide's where the system has none: the CI's machines have no icon theme)
		shown :: proc(b: ^ui.Box) -> bool { return b.custom != nil || .Draw_Text in b.flags }
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			b := session.find(s, "icon")
			return b != nil && (b.custom != nil || .Draw_Text in b.flags)
		}, "the first icons")
		session.frames(s, 4)
		blank := 0
		list := session.get(s, "list")
		at := session.center(list)
		for _ in 0 ..< 4 {
			session.wheel(s, at, {0, -1}, {.Ctrl})   // (up: larger)
			for _ in 0 ..< 12 {
				session.frames(s, 1)
				for i in 0 ..< 200 {
					b := session.find(s, "icon", i)
					if b == nil { break }
					if !shown(b) { blank += 1 }
				}
			}
		}
		testing.expect(t, tab.zoom > 0, "zoomed")
		testing.expect_value(t, blank, 0)
	})
}

// A tab dragged shows where it goes: its ghost under the pointer, the line between the tabs of a row, the half of the
// panel a new panel takes; let go there, the new panel is made. Its menu's line sends it to a window of its own.
@(test)
test_tab_drag_feedback :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		session.frames(s, 2)
		p := current_panel(app)
		testing.expect_value(t, len(p.tabs), 2)
		first := app.tab_rects_last[0].rect
		from := (first.min + first.max) * 0.5
		session.press(s, from)
		session.move(s, from + {12, 0})
		// (past the second tab's middle, whatever the tabs' widths: after it)
		last := app.tab_rects_last[1].rect
		session.move(s, {last.max.x - 3, from.y})
		session.frames(s, 2)
		{
			d := app.tab_drag
			testing.expectf(t, session.find(s, "tab_land") != nil, "its ghost where it lands in the row: active %v land %v/%v/%v mouse %v from %v last %v window %v out %v tabs %v panels %v",
				d.active, d.land_panel, d.land_at, d.land_split, ui.mouse_pos(), from, last, app.window_px, app.tab_out, app.tab_rects_last[:], app.panel_rects[:])
		}
		testing.expect(t, session.find(s, "tab_ghost") == nil, "nothing else over it")
		when SHOTS { session.save_png(s, "tab_land.png") }
		// the right quarter of the panel: a new panel at the right
		pr := app.panel_rects[0]
		right := [2]f32{pr.max.x - (pr.max.x - pr.min.x) * 0.1, (pr.min.y + pr.max.y) * 0.5}
		session.move(s, right)
		session.frames(s, 2)
		testing.expect(t, session.find(s, "tab_ghost") != nil, "off the rows: the ghost follows the pointer")
		testing.expect(t, session.find(s, "tab_drop_split") != nil && session.find_text(s, "A new panel at the right") != nil, "the half it takes")
		when SHOTS { session.save_png(s, "tab_split.png") }
		session.release(s, right)
		session.frames(s, 3)
		testing.expect_value(t, len(app.panels), 2)
		testing.expect(t, session.find(s, "tab_ghost") == nil, "the ghost gone")
		// the menu's line: the shown tab to a window of its own (headless: noted)
		act_tab_window(app)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).panels) == 1 }, "the tab gone to its window")
		testing.expect(t, len(app.opened) > 0 && strings.has_prefix(app.opened[len(app.opened) - 1], "window:"), "a window of its own")
		testing.expect_value(t, len(app.panels), 1)
	})
}

// What a dragged tab carries, read back: a Windows path keeps its colon; a string that is not one is refused.
@(test)
test_tab_mime :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		pid, id, path, ok := tab_mime_parse(tab_mime_data(42, 7, `C:\Users\me\Documents`))
		testing.expect(t, ok)
		testing.expect_value(t, pid, 42)
		testing.expect_value(t, id, u64(7))
		testing.expect_value(t, path, `C:\Users\me\Documents`)
		_, _, _, ok = tab_mime_parse("/home/me")
		testing.expect(t, !ok, "no process, no id")
		_, _, _, ok = tab_mime_parse("x:y:/home/me")
		testing.expect(t, !ok, "not numbers")
		// the icons' sizes: the next one up, the largest past it
		testing.expect_value(t, icon_size_for(22), 24)
		testing.expect_value(t, icon_size_for(24), 24)
		testing.expect_value(t, icon_size_for(1000), 256)
	})
}

// A tab closed while it is dragged ends the drag (the next one starts again).
@(test)
test_tab_drag_closed :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		session.frames(s, 2)
		first := app.tab_rects_last[1].rect
		from := (first.min + first.max) * 0.5
		session.press(s, from)
		session.move(s, from + {30, 0})
		session.frames(s, 2)
		testing.expect(t, app.tab_drag.active, "dragging")
		session.key(s, .W, {.Ctrl})
		session.frames(s, 3)
		testing.expect(t, !app.tab_drag.active, "over: its tab went")
		session.release(s, from + {30, 0})
	})
}

// Sorted by size, the folders go by what they hold, as it is measured (their sizes in their entries; once a frame);
// the Size column has a bar of each row's share of the largest.
@(test)
test_sort_by_measures :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		f := &tab.folder
		folder_set_sort(f, {key = .Size, descending = true, mixed = true})
		// (the three folders measured: their sizes in their entries)
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			tab := current_tab((^App)(s.user))
			n := 0
			for e in tab.folder.listing.entries { if e.kind == .Directory && e.size >= 0 { n += 1 } }
			return n == 3
		}, "the folders measured")
		session.frames(s, 3)
		prev := max(i64)
		for i in f.shown {
			e := f.listing.entries[i]
			testing.expectf(t, e.size <= prev, "%s (%d) after %d", e.name, e.size, prev)
			prev = e.size
		}
		first := f.listing.entries[f.shown[0]]
		testing.expect_value(t, first.kind, fs.Kind.Directory)   // (Documents' 61 bytes: more than any file)
		when SHOTS { session.save_png(s, "size_sort.png") }
	})
}

// A zip of stored files, as a zip writer makes one (local headers, the central directory, its end).
// (shared by the tests of the package: each file of tests uses it)
stored_zip :: proc(files: [][2]string) -> []u8 {
	le16 :: proc(b: ^[dynamic]u8, v: int) { append(b, u8(v), u8(v >> 8)) }
	le32 :: proc(b: ^[dynamic]u8, v: int) { le16(b, v); le16(b, v >> 16) }
	b := make([dynamic]u8, context.temp_allocator)
	central := make([dynamic]u8, context.temp_allocator)
	for f in files {
		at := len(b)
		le32(&b, 0x04034b50); le16(&b, 20); le16(&b, 0); le16(&b, 0); le16(&b, 0); le16(&b, 0x5a21)
		le32(&b, 0); le32(&b, len(f[1])); le32(&b, len(f[1])); le16(&b, len(f[0])); le16(&b, 0)
		append(&b, ..transmute([]u8)f[0]); append(&b, ..transmute([]u8)f[1])
		le32(&central, 0x02014b50); le16(&central, 20); le16(&central, 20); le16(&central, 0); le16(&central, 0)
		le16(&central, 0); le16(&central, 0x5a21); le32(&central, 0); le32(&central, len(f[1])); le32(&central, len(f[1]))
		le16(&central, len(f[0])); le16(&central, 0); le16(&central, 0); le16(&central, 0); le16(&central, 0); le32(&central, 0); le32(&central, at)
		append(&central, ..transmute([]u8)f[0])
	}
	cd := len(b)
	append(&b, ..central[:])
	le32(&b, 0x06054b50); le16(&b, 0); le16(&b, 0); le16(&b, len(files)); le16(&b, len(files)); le32(&b, len(central)); le32(&b, cd); le16(&b, 0)
	return b[:]
}

// An archive is a folder (File Pilot's): Enter goes into it, its folders named only by their files are folders, a file
// copied out of it is taken out, a write in it is refused, a file of it opened is taken out first.
@(test)
test_archive_folders :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		zip := fs.join(dir, "real.zip", context.temp_allocator)
		testing.expect(t, os.write_entire_file(zip, stored_zip({{"inner/hello.txt", "hello"}, {"top.txt", "top!"}})) == nil)
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		wait_read(s)
		point_at(t, tab, "real.zip")
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, tab.path, zip)
		testing.expect(t, slice.contains(shown_names(tab), "inner") && slice.contains(shown_names(tab), "top.txt"), "its top")
		point_at(t, tab, "inner")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, slice.contains(shown_names(tab), "hello.txt"), "a folder named only by its file")
		when SHOTS { session.save_png(s, "archive.png") }
		// copied out: taken out
		hello := fs.join(tab.path, "hello.txt", context.temp_allocator)
		job_add(app, .Copy, {hello}, dir)
		wait_jobs(s)
		got, _ := os.read_entire_file(fs.join(dir, "hello.txt", context.temp_allocator), context.temp_allocator)
		testing.expect_value(t, string(got), "hello")
		// a write in it: refused
		testing.expect_value(t, fs.make_folder(fs.join(tab.path, "new", context.temp_allocator)), fs.Error.Read_Only)
		testing.expect_value(t, fs.remove(hello), fs.Error.Read_Only)
		// opened: taken out first (to a folder of the test's), then given to the system (headless: noted)
		fs.take_out_root = fs.join(dir, ".taken", context.temp_allocator)
		defer fs.take_out_root = ""
		before := len(app.opened)
		testing.expect(t, tab.in_archive, "the read knows its folder is in the archive")
		open_system(app, hello, tab.in_archive)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return len((^App)(s.user).opened) > 0 && strings.has_suffix((^App)(s.user).opened[len((^App)(s.user).opened) - 1], "hello.txt") }, "taken out and opened")
		testing.expect(t, len(app.opened) > before, "opened")
		out := app.opened[len(app.opened) - 1]
		testing.expect(t, !strings.has_prefix(out, zip), "from outside of the archive")
		taken, _ := os.read_entire_file(out, context.temp_allocator)
		testing.expect_value(t, string(taken), "hello")
	})
}

// The inspector's properties (where, dates, permissions, owner) and its edge: dragged left, it is wider, kept when let go.
@(test)
test_inspector_props :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		point_at(t, tab, "notes.txt")
		act_inspector(app)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 3)
		testing.expect(t, app.inspector.has_props, "its properties read")
		testing.expect(t, session.find_text(s, PERMISSIONS_WORD) != nil, "its permissions")
		when ODIN_OS != .Windows { testing.expect(t, strings.contains(app.inspector.props.permissions, "rw"), "rw") }
		when SHOTS { session.save_png(s, "inspector_props.png") }
		before := app.inspector.pane.size[.X]
		h := session.get(s, "insp_split")
		from := session.center(h)
		session.drag(s, from, from - {120, 0})
		session.frames(s, 2)
		testing.expectf(t, app.inspector.pane.size[.X] > before + 50, "wider: %v from %v", app.inspector.pane.size[.X], before)
		testing.expect_value(t, config.int_of(&app.prefs, "inspector.width"), i64(app.inspector.pane.size[.X]))
	})
}

// The inspector shows a source file in its language's colours.
@(test)
test_inspector_code :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		testing.expect(t, os.write_entire_file(fs.join(dir, "main.odin", context.temp_allocator), "package main\n\n// the start\nmain :: proc() {\n\tfmt.println(\"hello\", 42)\n}\n") == nil)
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		point_at(t, tab, "main.odin")
		act_inspector(app)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 3)
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Text)
		testing.expect(t, session.find(s, "insp_body") != nil, "its text")
		when SHOTS { session.save_png(s, "inspector_code.png") }
		// a script with no extension: its language from what it holds
		testing.expect(t, os.write_entire_file(fs.join(dir, "deploy", context.temp_allocator), "#!/bin/sh\nset -e\necho \"done\"\n") == nil)
		act_refresh(app)
		wait_read(s)
		point_at(t, tab, "deploy")
		session.frames(s, 2)
		session.wait_until(s, proc(s: ^session.Session) -> bool { a := (^App)(s.user); return a.inspector.ready && strings.has_suffix(a.inspector.path, "deploy") }, "the script inspected")
		testing.expect(t, app.inspector.language, "its colours, by its #! line")
	})
}

// A second start's message: its launcher's token on a line of its own, then its folders.
@(test)
test_app_message :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		token, folders := app_message_read(app_message_make("tok-1", {"/a", "/b c"}))
		testing.expect_value(t, token, "tok-1")
		testing.expect_value(t, len(folders), 2)
		testing.expect_value(t, folders[1], "/b c")
		token, folders = app_message_read(app_message_make("", {"/a"}))
		testing.expect_value(t, token, "")
		testing.expect_value(t, len(folders), 1)
		_, folders = app_message_read(app_message_make("t", nil))
		testing.expect_value(t, len(folders), 0)
	})
}

// A walk's batch added to a folder that filters: the order merged stays sorted, the lower-case names follow, the cursor
// stays on its entry.
@(test)
test_folder_add_entries :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		f: Folder
		defer folder_destroy(&f)
		first: fs.Listing
		first.path = fs.keep_name(&first, "/x")
		for name in ([]string{"b.txt", "d.txt", "f.txt"}) { append(&first.entries, fs.Entry{name = fs.keep_name(&first, name), kind = .File, size = 1}) }
		folder_set_listing(&f, &first)
		folder_set_filter(&f, "txt")
		folder_cursor_to_name(&f, "d.txt")
		batch: fs.Listing
		defer fs.listing_destroy(&batch)
		for name in ([]string{"e.txt", "a.txt", "c.txt"}) { append(&batch.entries, fs.Entry{name = fs.keep_name(&batch, name), kind = .File, size = 1}) }
		folder_add_entries(&f, &batch)
		testing.expect_value(t, len(f.order), 6)
		for k in 1 ..< len(f.order) {
			testing.expect(t, !fs.entry_less(f.listing.entries[f.order[k]], f.listing.entries[f.order[k - 1]], f.sort), "sorted")
		}
		testing.expect_value(t, len(f.lowered), len(f.listing.entries))
		testing.expect_value(t, len(f.shown), 6)
		e := folder_cursor_entry(&f)
		testing.expect(t, e != nil && e.name == "d.txt", "the cursor on its entry")
	})
}

// The alternating rows: a faint shade (a picture to look at).
@(test)
test_stripes :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 500})
		context.allocator = runtime.heap_allocator()
		_ = config.set_from_string(&app.prefs, "look.alternating_rows", "true", .User)
		settings_apply(app)
		current_tab(app).zoom = 0
		wait_read(s)
		session.frames(s, 3)
		testing.expect(t, app.settings.alternating_rows)
		when SHOTS { session.save_png(s, "stripes.png") }
	})
}

// Ctrl and a drag from a selected row take the rows it passes out of the selection; a right click on the list's empty
// part opens the folder's menu.
@(test)
test_ctrl_band_and_empty_menu :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		session.frames(s, 2)
		folder_select_all(&tab.folder)
		n := tab.folder.count
		row1 := session.get(s, "check1").rect
		row3 := session.get(s, "check3").rect
		from := [2]f32{row1.max.x + 200, (row1.min.y + row1.max.y) * 0.5}
		to := [2]f32{from.x, (row3.min.y + row3.max.y) * 0.5}
		// (Ctrl held through the press, the drag and the release)
		ctrl :: proc(s: ^session.Session, kind: platform.Event_Kind, at: [2]f32) {
			s.pointer = at
			if kind == .Mouse_Press { s.buttons += {.Left} }
			if kind == .Mouse_Release { s.buttons -= {.Left} }
			session.event(s, {kind = kind, button = .Left, pos = at, mods = {.Ctrl}})
			session.frames(s, 2)
		}
		session.move(s, from)
		ctrl(s, .Mouse_Press, from)
		ctrl(s, .Mouse_Move, from + {0, 6})
		ctrl(s, .Mouse_Move, to)
		ctrl(s, .Mouse_Release, to)
		testing.expectf(t, tab.folder.count == n - 3, "rows 1 to 3 taken out: %d of %d", tab.folder.count, n)
		testing.expect(t, len(app.drag_paths) == 0, "no file dragged")
		// the empty part, right-clicked: the folder's menu (New folder)
		session.click_at(s, {from.x, 600}, .Right)
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "New folder") != nil, "the folder's menu")
		when SHOTS { session.save_png(s, "empty_menu.png") }
		session.key(s, .Escape)
	})
}

// Letters typed with the list's keyboard go to the panel's filter (File Pilot's); Space still opens the inspector.
@(test)
test_type_to_filter :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		wait_read(s)
		session.frames(s, 2)
		session.type_text(s, "rep")
		session.frames(s, 2)
		testing.expect_value(t, ui.field_string(&tab.filter), "rep")
		names := shown_names(tab)
		testing.expect(t, slice.contains(names, "report 2.pdf") && slice.contains(names, "report 10.pdf") && !slice.contains(names, "notes.txt"), "filtered")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect_value(t, ui.field_string(&tab.filter), "")
		session.key(s, .Space)
		session.frames(s, 2)
		testing.expect(t, app.inspector.open, "Space: the inspector")
		testing.expect_value(t, ui.field_string(&tab.filter), "")
	})
}

// Our own drag, as Linux gives it: its enter and its moves carry no data (read at the drop): the folder under the
// pointer, a place of the sidebar, still takes it (its files are the drag's own).
@(test)
test_own_drag_without_data :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 700})
		context.allocator = runtime.heap_allocator()
		wait_read(s)
		session.frames(s, 2)
		notes := fs.join(dir, "notes.txt", context.temp_allocator)
		own := []string{notes}
		app.dragging = own   // (as drag_run has it while the system's drag runs)
		at: [2]f32
		for z in app.drop_zones_last { if strings.has_suffix(z.path, fs.SEPARATOR_STRING + "Photos") { at = (z.rect.min + z.rect.max) * 0.5 } }
		testing.expect(t, at != {}, "Photos takes a drop")
		empty: platform.Drag_Data
		platform.drop_inject(app.main.win, .Drop_Enter, at, &empty, {.Copy, .Move})
		session.frames(s, 1)
		testing.expectf(t, strings.has_suffix(app.drop_hover, "Photos"), "the target marked: %q", app.drop_hover)
		// (the drop: the data still empty, as the drag of this very process gives it)
		platform.drop_inject(app.main.win, .Drop, at, &empty, {.Copy, .Move})
		session.frames(s, 1)
		app.dragging = nil
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Photos/notes.txt", context.temp_allocator)), "moved into Photos")
	})
}

// The pointer's gestures in every view (Details, List, Columns, Grid): the rectangle from the empty part selects the
// items it touches on screen; a right click there opens the folder's menu; Ctrl and a drag from a selected item takes
// the items it passes out of the selection; a file dragged onto a folder goes into it.
@(private = "file")
mouse_matrix :: proc(t: ^testing.T, zoom: int) {
	files := FIXTURE
	dir := make_fixture(t, files[:])
	s, app := start(t, {dir}, size = {1000, 700})
	context.allocator = runtime.heap_allocator()
	tab := current_tab(app)
	tab.zoom = zoom
	wait_read(s)
	session.frames(s, 6)
	mode := tab_mode(tab)
	n := len(tab.folder.shown)
	lb := band_box(tab)
	testing.expectf(t, lb != nil, "%v: the items' box", mode)
	if lb == nil { return }
	// an item's rectangle on screen: its box (Columns, Grid) or its row of the list
	rect_of :: proc(s: ^session.Session, tab: ^Tab, lb: ^ui.Box, i: int) -> (ui.Rect, bool) {
		if tab_mode(tab) >= .Columns {
			b := session.get(s, fmt.tprintf("item%d", i))
			if b == nil { return {}, false }
			return b.rect, true
		}
		offs := tab.vl.offsets[:]
		if i + 1 >= len(offs) { return {}, false }
		y := lb.rect.min.y - lb.view_off.y
		return {{lb.rect.min.x, y + offs[i]}, {lb.rect.max.x, y + offs[i + 1]}}, true
	}
	middle :: proc(r: ui.Rect) -> [2]f32 { return (r.min + r.max) * 0.5 }
	index_of :: proc(tab: ^Tab, name: string) -> int {
		for e, i in tab.folder.shown { if tab.folder.listing.entries[e].name == name { return i } }
		return -1
	}
	empty := lb.rect.max - {20, 20}
	for i in 0 ..< n {
		r, ok := rect_of(s, tab, lb, i)
		if ok && empty.x >= r.min.x && empty.x < r.max.x && empty.y >= r.min.y && empty.y < r.max.y { testing.expectf(t, false, "%v: the corner is on item %d", mode, i) }
	}

	// 1. the rectangle, from the empty corner to the first item's middle
	r0, _ := rect_of(s, tab, lb, 0)
	to := middle(r0)
	session.press(s, empty)
	session.move(s, empty + {-10, -10})
	session.move(s, to)
	session.frames(s, 2)
	band := ui.Rect{{min(empty.x, to.x), min(empty.y, to.y)}, {max(empty.x, to.x), max(empty.y, to.y)}}
	want := 0
	for i in 0 ..< n {
		r, ok := rect_of(s, tab, lb, i)
		if ok && r.max.x > band.min.x && r.min.x < band.max.x && r.max.y > band.min.y && r.min.y < band.max.y { want += 1 }
	}
	testing.expectf(t, want >= 1 && tab.folder.count == want, "%v: the rectangle selects what it touches: %d selected, %d touched", mode, tab.folder.count, want)
	when SHOTS { session.save_png(s, fmt.tprintf("band_%v.png", mode)) }
	session.release(s, to)
	session.frames(s, 2)
	testing.expectf(t, tab.folder.count == want && !app.band.active, "%v: kept when let go", mode)
	testing.expectf(t, !app.file_drag && len(app.drag_paths) == 0, "%v: no file dragged by the rectangle", mode)

	// 2. a right click on the empty part: the folder's menu
	session.click_at(s, empty, .Right)
	session.frames(s, 3)
	testing.expectf(t, session.find_text(s, "New folder") != nil, "%v: the folder's menu", mode)
	session.key(s, .Escape)
	session.frames(s, 2)

	// 3. Ctrl and a drag from a selected item to the next: both taken out of the selection
	folder_select_all(&tab.folder)
	session.frames(s, 2)
	ra, _ := rect_of(s, tab, lb, 0)
	rb, _ := rect_of(s, tab, lb, 1)
	ctrl :: proc(s: ^session.Session, kind: platform.Event_Kind, at: [2]f32) {
		s.pointer = at
		if kind == .Mouse_Press { s.buttons += {.Left} }
		if kind == .Mouse_Release { s.buttons -= {.Left} }
		session.event(s, {kind = kind, button = .Left, pos = at, mods = {.Ctrl}})
		session.frames(s, 2)
	}
	a, b := middle(ra), middle(rb)
	session.move(s, a)
	ctrl(s, .Mouse_Press, a)
	ctrl(s, .Mouse_Move, a + (b - a) * 0.3)
	ctrl(s, .Mouse_Move, b)
	ctrl(s, .Mouse_Release, b)
	testing.expectf(t, tab.folder.count == n - 2, "%v: Ctrl and a drag deselect: %d of %d", mode, tab.folder.count, n)
	testing.expectf(t, !app.file_drag && len(app.drag_paths) == 0, "%v: no file dragged by Ctrl", mode)

	// 4. a click of the wheel on a folder: its tab (the toolkit's autoscroll leaves the rows' middle button alone)
	{
		tabs := len(current_panel(app).tabs)
		rp, _ := rect_of(s, tab, lb, index_of(tab, "Photos"))
		session.click_at(s, middle(rp), .Middle)
		session.frames(s, 3)
		testing.expectf(t, len(current_panel(app).tabs) == tabs + 1, "%v: a click of the wheel opens a tab", mode)
		current_panel(app).active = 0
		tab = current_tab(app)
		session.frames(s, 2)
		lb = band_box(tab)
		testing.expectf(t, lb != nil, "%v: the first tab's list again", mode)
		if lb == nil { return }
	}

	// 5. the wheel's click on a file opens nothing (it scrolls)
	{
		tabs := len(current_panel(app).tabs)
		rf, _ := rect_of(s, tab, lb, index_of(tab, "notes.txt"))
		session.click_at(s, middle(rf), .Middle)
		session.click_at(s, middle(rf) + {0, 2})   // (a click ends the autoscroll it started)
		session.frames(s, 3)
		testing.expectf(t, len(current_panel(app).tabs) == tabs, "%v: the wheel's click on a file opens no tab", mode)
	}

	// 6. Escape in a rectangle: the selection there was, and nothing else starts till the release
	folder_select_none(&tab.folder)
	r1, _ := rect_of(s, tab, lb, index_of(tab, "report 2.pdf"))
	folder_pick(&tab.folder, index_of(tab, "report 2.pdf"))
	session.frames(s, 2)
	session.press(s, empty)
	session.move(s, empty + {-10, -10})
	session.move(s, middle(r0))
	session.frames(s, 2)
	testing.expectf(t, app.band.active, "%v: a rectangle", mode)
	session.key(s, .Escape)
	session.frames(s, 2)
	session.move(s, middle(r0) + {4, 4})
	session.frames(s, 2)
	testing.expectf(t, !app.band.active && tab.folder.count == 1 && folder_row_selected(&tab.folder, index_of(tab, "report 2.pdf")), "%v: Escape gives the selection back: %d", mode, tab.folder.count)
	session.release(s, middle(r0) + {4, 4})
	session.frames(s, 2)
	_ = r1

	// 7. Escape in a file drag: nothing moves
	rn, okn := rect_of(s, tab, lb, index_of(tab, "notes.txt"))
	rp, okp := rect_of(s, tab, lb, index_of(tab, "Photos"))
	testing.expectf(t, okn && okp, "%v: notes.txt and Photos shown", mode)
	folder_select_none(&tab.folder)
	session.frames(s, 2)
	from, into := middle(rn), middle(rp)
	session.press(s, from)
	session.move(s, from + {0, -12})
	session.move(s, into)
	session.frames(s, 2)
	testing.expectf(t, app.file_drag, "%v: a file drag", mode)
	session.key(s, .Escape)
	session.frames(s, 2)
	testing.expectf(t, !app.file_drag, "%v: Escape ends it", mode)
	session.release(s, into)
	session.frames(s, 2)
	wait_jobs(s)
	testing.expectf(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "%v: Escape: notes.txt stays", mode)

	// 8. notes.txt dragged onto Photos: moved there
	folder_select_none(&tab.folder)
	session.frames(s, 2)
	session.press(s, from)
	session.move(s, from + {0, -12})
	session.move(s, into)
	session.frames(s, 2)
	testing.expectf(t, strings.has_suffix(app.drop_hover, fs.SEPARATOR_STRING + "Photos"), "%v: Photos lit", mode)
	session.release(s, into)
	session.frames(s, 2)
	wait_jobs(s)
	testing.expectf(t, fs.exists(fs.join(dir, "Photos/notes.txt", context.temp_allocator)), "%v: notes.txt dragged into Photos", mode)
}

@(test) test_mouse_details :: proc(t: ^testing.T) { unwatched.run(t, proc(t: ^testing.T) { mouse_matrix(t, 0) }) }
@(test) test_mouse_list :: proc(t: ^testing.T) { unwatched.run(t, proc(t: ^testing.T) { mouse_matrix(t, 1) }) }
@(test) test_mouse_columns :: proc(t: ^testing.T) { unwatched.run(t, proc(t: ^testing.T) { mouse_matrix(t, 2) }) }
@(test) test_mouse_grid :: proc(t: ^testing.T) { unwatched.run(t, proc(t: ^testing.T) { mouse_matrix(t, ZOOM_GRID) }) }

// A column's title clicked three times: its first way, the other way, then the names' order again.
@(test)
test_sort_three_clicks :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 600})
		tab := current_tab(app)
		tab.zoom = 0
		wait_read(s)
		session.frames(s, 2)
		before := slice.clone(shown_names(tab), context.temp_allocator)
		head := session.get(s, "hd_5")
		_ = head
		testing.expect(t, head != nil, "the Size column")
		if head == nil { return }
		at := title_point(s, .Size)
		want := [3]fs.Sort{{key = .Size, descending = true}, {key = .Size, descending = false}, {key = .Name, descending = false}}
		for w, i in want {
			session.click_at(s, at)
			session.frames(s, 2)
			testing.expectf(t, tab.folder.sort.key == w.key && tab.folder.sort.descending == w.descending, "click %d: %v", i + 1, tab.folder.sort)
		}
		testing.expect(t, slice.equal(shown_names(tab), before), "the order there was")
		testing.expect_value(t, app.default_sort.key, fs.Sort_Key.Name)
		// the name's: down, then up again
		name := title_point(s, .Name)
		session.click_at(s, name)
		session.frames(s, 2)
		testing.expect(t, tab.folder.sort.key == .Name && tab.folder.sort.descending, "the names down")
		session.click_at(s, name)
		session.frames(s, 2)
		testing.expect(t, tab.folder.sort.key == .Name && !tab.folder.sort.descending, "the names up")
	})
}

// A narrow window: a tab of another window over the end of the row shows its ghost whole (the row's room shared with it).
@(test)
test_tab_ghost_narrow :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {640, 500})
		context.allocator = runtime.heap_allocator()
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		session.frames(s, 2)
		photos := fs.join(dir, "Photos", context.temp_allocator)
		data: platform.Drag_Data
		append(&data.custom, platform.Drag_Entry{TAB_MIME, tab_mime_data(1, 7, photos)})
		defer delete(data.custom)
		last := app.tab_rects_last[len(app.tab_rects_last) - 1].rect
		at := [2]f32{last.max.x - 3, (last.min.y + last.max.y) * 0.5}
		platform.drop_inject(app.main.win, .Drop_Enter, at, &data, {.Move})
		platform.drop_inject(app.main.win, .Drop_Over, at, nil, {.Move})
		session.frames(s, 3)
		ghost, row := session.get(s, "tab_land"), session.get(s, "tabs0")
		testing.expect(t, ghost != nil && row != nil, "its ghost in the row")
		if ghost != nil && row != nil {
			testing.expectf(t, ghost.rect.max.x <= row.rect.max.x + 0.5 && ghost.rect.min.x >= row.rect.min.x, "whole in the row: %v in %v", ghost.rect, row.rect)
		}
		when SHOTS { session.save_png(s, "tab_ghost_narrow.png") }
		platform.drop_inject(app.main.win, .Drop_Leave, at, nil, {.Move})
		session.frames(s, 2)
		testing.expect(t, session.find(s, "tab_land") == nil, "gone when it leaves")
	})
}

// Many writes of the session in a row, on the workers: the file holds the last one (one writer, the latest text wins).
@(test)
test_session_writes_in_order :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		dir := strings.clone(testkit.temp_folder(t, "classeur_writes"))
		defer delete(dir)
		file := fs.join(dir, ".session")
		defer delete(file)
		app := app_open({folders = {dir}, headless = true, session = file})
		testing.expect(t, app != nil)
		if app == nil { return }
		defer app_close(app)
		for i in 0 ..< 200 {
			append(&app.bookmarks, strings.clone(fmt.tprintf("/mark/%d", i)))
			session_save(app, later = true)
		}
		// (the writer done: nothing pending, none running)
		for _ in 0 ..< 2000 {
			sync.mutex_lock(&app.session_writer.mutex)
			idle := !app.session_writer.running
			sync.mutex_unlock(&app.session_writer.mutex)
			if idle { break }
			time.sleep(time.Millisecond)
		}
		data, err := os.read_entire_file(file, context.temp_allocator)
		testing.expect(t, err == nil, "written")
		testing.expect(t, strings.contains(string(data), "bookmark /mark/199\n"), "the last text")
		testing.expect_value(t, strings.count(string(data), "\nsidebar "), 1)
	})
}

// Escape ends a tab's drag (the tab stays) and closes the jobs' view, before the list takes it.
@(test)
test_escape_ends_gestures :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		session.frames(s, 2)
		p := current_panel(app)
		first_id := p.tabs[0].id
		first := app.tab_rects_last[0].rect
		last := app.tab_rects_last[1].rect
		from := (first.min + first.max) * 0.5
		session.press(s, from)
		session.move(s, from + {12, 0})
		session.move(s, {last.max.x - 3, from.y})
		session.frames(s, 2)
		testing.expect(t, app.tab_drag.active, "a tab's drag")
		session.key(s, .Escape)
		session.frames(s, 2)
		session.move(s, {last.max.x - 6, from.y})
		session.frames(s, 2)
		testing.expect(t, !app.tab_drag.active, "Escape ends it")
		session.release(s, {last.max.x - 6, from.y})
		session.frames(s, 3)
		testing.expect_value(t, p.tabs[0].id, first_id)
		// the jobs' view: Escape closes it, the selection of the list untouched
		tab := current_tab(app)
		folder_select_all(&tab.folder)
		n := tab.folder.count
		session.key(s, .J, {.Ctrl, .Alt})
		session.frames(s, 2)
		testing.expect(t, app.jobs_view.open, "the jobs' view")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.jobs_view.open, "Escape closes it")
		testing.expect_value(t, tab.folder.count, n)
	})
}

// A key of the keypad in a binding of one's own: named, kept in the preferences and read back; the tooltips and the
// menus show the person's keys.
@(test)
test_keypad_binding :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		_ = s
		for text in ([]string{"Ctrl+Num +", "Ctrl+Shift+Num -", "Alt+Page Down", "Ctrl+,", "Menu", "Ctrl+M, T"}) {
			b, ok := binding_parse(text)
			testing.expectf(t, ok, "%q is read", text)
			testing.expectf(t, binding_text(b) == text, "%q comes back: %q", text, binding_text(b))
		}
		b, _ := binding_parse("Ctrl+Num +")
		keymap_bind(app, "zoom_in", b)
		testing.expect_value(t, command_tip(app, "zoom_in"), fmt.tprintf("%s (Ctrl+Num +)", command_find("zoom_in").title))
		testing.expect_value(t, command_keys(app, command_find("zoom_in")), "Ctrl+Num +")
		saved := config.string_of(&app.prefs, "keys.custom")
		testing.expectf(t, strings.contains(saved, "zoom_in=Ctrl+Num +"), "kept: %q", saved)
	})
}

// A setting found in the palette (by one of its tags): the settings open on it alone.
@(test)
test_palette_settings :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 800})
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "corners")
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "Rounding") != nil, "the rounding, by its tag")
		session.key(s, .Return)
		session.frames(s, 3)
		testing.expect(t, !app.palette.open && app.options.open, "the settings open")
		testing.expect(t, strings.contains(ui.field_string(&app.options.page.query), "look.rounding"), "on the rounding")
		testing.expect(t, session.find_text(s, fmt.tprintf("classeur %s", APP_VERSION)) != nil, "the version at their foot")
		when SHOTS { session.save_png(s, "palette_settings.png") }
	})
}

// A point on the words of a column's title in the details' header (its middle may hold its filter's funnel): a number's
// words at its right end, the others' at its left (past its rule, the name's past the box that checks every row).
@(private = "file")
title_point :: proc(s: ^session.Session, d: Detail) -> [2]f32 {
	b := session.get(s, fmt.tprintf("hd_%d", int(d)))
	r := b.rect
	y := (r.min.y + r.max.y) * 0.5
	switch {
	case DETAIL_COLUMNS[d].number: return {r.max.x - 22, y}
	case d == .Name:               return {r.min.x + 64, y}
	}
	return {r.min.x + 22, y}
}

// The details' cells lie under their titles: each one as wide as its title and at the same place, the name's too.
@(test)
test_columns_aligned :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, _ := start(t, {dir}, size = {1600, 700})
		session.frames(s, 3)
		for d in Detail {
			k := int(d)
			title := session.get(s, fmt.tprintf("hd_%d", k))
			cell := d == .Name ? session.find(s, "name_cell") : session.find(s, fmt.tprintf("c%d", k))
			testing.expectf(t, title != nil && cell != nil, "%v: a title and a cell", d)
			if title == nil || cell == nil { continue }
			testing.expectf(t, abs(cell.rect.min.x - title.rect.min.x) < 1 && abs(cell.rect.max.x - title.rect.max.x) < 1, "%v: the cell %v under its title %v", d, cell.rect, title.rect)
		}
	})
}

// The places that are not paths (Linux: a share gvfs mounted, in a runtime folder made for the test): smb:// goes to
// its folder, the tab named by the share, the first crumb its URI, the sidebar's Network section lists it; trash:///
// is the trash's folder.
@(test)
test_locations_in_tabs :: proc(t: ^testing.T) {
	when ODIN_OS != .Linux { return }
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		run := strings.clone(testkit.temp_folder(t, "classeur_run"))
		defer delete(run)
		share := fs.join(run, "gvfs/smb-share:server=nas,share=docs")
		defer delete(share)
		_ = os.make_directory_all(fs.join(share, "Reports", context.temp_allocator))
		before := strings.clone(os.get_env("XDG_RUNTIME_DIR", context.temp_allocator))
		defer { os.set_env("XDG_RUNTIME_DIR", before); delete(before) }
		os.set_env("XDG_RUNTIME_DIR", run)
		// (the trash of a data folder of the test's)
		data := fs.join(run, "data")
		defer delete(data)
		_ = os.make_directory_all(fs.join(data, "Trash/files", context.temp_allocator))
		data_before := strings.clone(os.get_env("XDG_DATA_HOME", context.temp_allocator))
		defer { os.set_env("XDG_DATA_HOME", data_before); delete(data_before) }
		os.set_env("XDG_DATA_HOME", data)
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		tab := current_tab(app)
		tab_go(app, tab, "smb://nas/docs")
		wait_read(s)
		session.frames(s, 3)
		testing.expect_value(t, tab.path, share)
		testing.expect_value(t, tab_title(app, tab), "docs on nas")
		crumbs := home_crumbs(app, tab)
		testing.expect(t, len(crumbs) > 0 && crumbs[0].name == "smb://nas/docs", "the first crumb, the share's URI")
		testing.expect(t, session.find_text(s, "Reports") != nil, "its folders")
		testing.expect(t, session.find_text(s, "Network") != nil && session.find_text(s, "docs on nas") != nil, "the sidebar's Network section")
		when SHOTS { session.save_png(s, "share.png") }
		tab_go(app, tab, "trash:///")
		wait_read(s)
		testing.expect_value(t, tab.path, fs.join(data, "Trash/files", context.temp_allocator))
		// a new tab on a share (a second start, the command line)
		tab_open(app, current_panel(app), "smb://nas/docs/Reports")
		wait_read(s)
		testing.expect_value(t, current_tab(app).path, fs.join(share, "Reports", context.temp_allocator))
	})
}

// The system's title bar, a setting where the system can draw one (an offscreen window says it can): found by its tag
// in the palette, read into the settings.
@(test)
test_system_title_setting :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 800})
		context.allocator = runtime.heap_allocator()
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "title bar")
		session.frames(s, 2)
		testing.expect(t, session.find_text(s, "System title") != nil, "the setting, by its tag")
		session.key(s, .Escape)
		_ = config.set_from_string(&app.prefs, "look.system_title", "true", .User)
		settings_apply(app)
		testing.expect(t, app.settings.system_title, "read")
	})
}

// A rectangle over a folded group's title takes none of its files (they are not shown).
@(test)
test_band_folded_group :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		tab_group(app, .Type)
		session.frames(s, 2)
		// (the PDFs' group folded: its title row stands for its first file)
		pdf := ""
		for i in tab.folder.shown {
			e := tab.folder.listing.entries[i]
			if strings.has_suffix(e.name, ".pdf") { _, pdf = group_of(&tab.folder, e); break }
		}
		testing.expect(t, pdf != "", "a group of PDFs")
		folder_fold(&tab.folder, strings.clone(pdf, context.temp_allocator))
		session.frames(s, 3)
		lb := band_box(tab)
		from := lb.rect.max - {20, 20}
		to := lb.rect.min + {300, 4}
		session.press(s, from)
		session.move(s, from + {-10, -10})
		session.move(s, to)
		session.frames(s, 2)
		session.release(s, to)
		session.frames(s, 2)
		for i, row in tab.folder.shown {
			e := tab.folder.listing.entries[i]
			if strings.has_suffix(e.name, ".pdf") { testing.expectf(t, !folder_row_selected(&tab.folder, row), "%s, in the folded group, not taken", e.name) }
		}
		testing.expect(t, tab.folder.count > 0, "the others taken")
	})
}

// A window resized: the tabs' regions lie on their panels in the very frame of the new size (worked out as the body
// lays it out, not from the last frame's boxes).
@(test)
test_tabs_follow_a_resize :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		panel_open(app, dir)
		wait_read(s)
		session.frames(s, 3)
		for w in ([]int{1000, 1350, 900}) {
			session.resize(s, {w, 700})
			session.frames(s, 1)
			for i in 0 ..< len(app.panels) {
				region := session.get(s, fmt.tprintf("tabs%d", i))
				pb := session.get(s, fmt.tprintf("panel%d", i))
				if pb == nil { continue }
				p := pb.rect
				testing.expectf(t, region != nil, "width %d, panel %d: its tabs", w, i)
				if region == nil { continue }
				testing.expectf(t, abs(region.rect.min.x - (p.min.x - max(1, ui.scale()))) < 1, "width %d, panel %d: its tabs from its left line (%v, panel %v)", w, i, region.rect, p)
			}
		}
	})
}

// The palette forgives a slip (the toolkit's palette_match): "new foldr" still finds New folder, and Enter makes one.
@(test)
test_palette_slip :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		session.key(s, .P, {.Ctrl, .Shift})
		session.type_text(s, "new foldr")
		session.frames(s, 2)
		testing.expect_value(t, COMMANDS[palette_first(app)].id, "new_folder")
		session.key(s, .Return)
		wait_read(s)   // (made by the edits' worker)
		_, made := fs.stat(fs.join(dir, "New folder", context.temp_allocator))
		testing.expect(t, made, "Enter on the slip made the folder")
	})
}

// The header's menu (the toolkit's): the column right-clicked back to its own width and unsorted, the tab's rows by name
// again; the default columns shown again.
@(test)
test_header_menu :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1400, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		l := &app.columns
		session.click_at(s, title_point(s, .Size))
		testing.expect_value(t, tab.folder.sort.key, fs.Sort_Key.Size)
		l.width[Detail.Size] += 40
		session.frames(s, 2)
		session.click(s, fmt.tprintf("hd_%d", int(Detail.Size)), .Right)
		session.frames(s, 2)
		item := session.find_text(s, "Reset Size")
		testing.expect(t, item != nil, "the column's own item")
		if item == nil { return }
		session.click_at(s, (item.rect.min + item.rect.max) * 0.5)
		session.frames(s, 2)
		testing.expect_value(t, tab.folder.sort.key, fs.Sort_Key.Name)
		testing.expect_value(t, l.width[Detail.Size], DETAIL_COLUMNS[.Size].width)
		// a column hidden, shown again by the default columns
		l.shown[Detail.Type] = false
		session.frames(s, 2)
		session.click(s, fmt.tprintf("hd_%d", int(Detail.Modified)), .Right)
		session.frames(s, 2)
		def := session.find_text(s, "Default columns")
		testing.expect(t, def != nil, "the default columns' item")
		if def == nil { return }
		session.click_at(s, (def.rect.min + def.rect.max) * 0.5)
		session.frames(s, 2)
		testing.expect(t, l.shown[Detail.Type], "Type shown again")
		testing.expect_value(t, config.string_of(&app.prefs, "view.columns"), DETAIL_COLUMNS_DEFAULT)
	})
}

// The question before deleting for good (the toolkit's ui.confirm): what it deletes named; Enter cancels, nothing is
// deleted; its button deletes.
@(test)
test_delete_dialog :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		session.key(s, .Home)
		session.key(s, .Down, {.Shift}, repeat = 2)
		session.key(s, .Delete, {.Shift})
		session.frames(s, 3)
		testing.expect(t, app.confirm.open, "the question")
		testing.expect(t, session.find_text(s, "Delete 3 items for good?") != nil, "its title")
		testing.expect(t, session.find(s, "confirm_line_2") != nil, "the three named")
		testing.expect(t, session.find_text(s, "Cancel (Enter)") != nil, "Enter cancels")
		session.key(s, .Return)
		session.frames(s, 2)
		testing.expect(t, !app.confirm.open, "closed")
		testing.expect(t, len(app.jobs.list) == 0, "nothing deleted")
	})
}
