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
import "core:testing"
import "gt:platform"
import "gt:png"
import "gt:testkit"
import "gt:ui"
import "gt:testkit/session"
import "fs"

// classeurtool shots: the pictures of the README, from test_shots.
SHOTS :: #config(CLASSEUR_SHOTS, false)

@(private = "file")
FIXTURE :: [?]string{
	"Documents/", "Photos/", "Projects/", "notes.txt", "report 2.pdf", "report 10.pdf", "archive.zip", ".hidden",
	"Documents/letter.odt", "Documents/budget.xlsx",
}

@(private = "file")
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

@(private = "file")
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

// Frames until every tab has its folder.
@(private = "file")
wait_read :: proc(s: ^session.Session, loc := #caller_location) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		app := (^App)(s.user)
		for p in app.panels { for t in p.tabs { if t.loading { return false } } }
		return true
	}, "the folders read", loc = loc)
	session.frames(s, 2)
}

// The cursor on `name`, and it alone selected (as a click does).
@(private = "file")
point_at :: proc(t: ^testing.T, tab: ^Tab, name: string, loc := #caller_location) {
	testing.expect(t, folder_cursor_to_name(&tab.folder, name), loc = loc)
	folder_pick(&tab.folder, tab.folder.cursor)
}

@(private = "file")
shown_names :: proc(t: ^Tab) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for i in t.folder.shown { append(&out, t.folder.listing.entries[i].name) }
	return out[:]
}

@(test)
test_browse :: proc(t: ^testing.T) {
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
	session.click(s, "col_Size")
	testing.expect_value(t, tab.folder.sort.key, fs.Sort_Key.Size)
	testing.expect(t, tab.folder.sort.descending)
	testing.expect_value(t, folder_row_entry(&tab.folder, 3).name, "report 10.pdf")
	session.click(s, "col_Name")
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
}

@(test)
test_change_files :: proc(t: ^testing.T) {
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
}

@(test)
test_tabs_and_panels :: proc(t: ^testing.T) {
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
	session.key(s, .F6)
	testing.expect_value(t, app.focus, 0)
	session.key(s, .W, {.Ctrl, .Shift})
	testing.expect_value(t, len(app.panels), 1)
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

@(private = "file")
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
}

@(test)
test_search :: proc(t: ^testing.T) {
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
}

@(test)
test_options :: proc(t: ^testing.T) {
	files := FIXTURE
	dir := make_fixture(t, files[:])
	s, app := start(t, {dir})
	tab := current_tab(app)
	session.key(s, .Comma, {.Ctrl})
	testing.expect(t, app.options.open)
	// typed words find the option; Enter flips it
	session.type_text(s, "hidden")
	session.key(s, .Return)
	testing.expect(t, app.show_hidden)
	testing.expect(t, slice.contains(shown_names(tab), ".hidden"))
	session.key(s, .Escape)
	testing.expect(t, !app.options.open)
	// the extensions left out of the names shown
	session.key(s, .Comma, {.Ctrl})
	session.type_text(s, "extension")
	session.key(s, .Return)
	session.key(s, .Escape)
	testing.expect(t, !app.settings.show_extensions)
	session.frames(s, 2)
	testing.expect(t, session.find_text(s, "notes") != nil, "notes.txt shows as notes")
}

@(test)
test_inspector :: proc(t: ^testing.T) {
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
	session.key(s, .Space)
	testing.expect(t, !app.inspector.open)
}

// The pictures of the README (classeurtool shots): a home folder of made-up files; the grid of the pictures beside the
// details of the home folder; the palette.
@(test)
test_shots :: proc(t: ^testing.T) {
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
	session.type_text(s, "tab")
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
	session.key(s, .Down, repeat = 3)
	session.frames(s, 2)
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
}

// Frames until every job has ended and its folders are read again.
@(private = "file")
wait_jobs :: proc(s: ^session.Session, loc := #caller_location) {
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		app := (^App)(s.user)
		for job in app.jobs.list { if job.ended_ms == 0 { return false } }
		return true
	}, "the jobs ended", loc = loc)
	wait_read(s, loc)
}

@(test)
test_jobs :: proc(t: ^testing.T) {
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
	// (Linux: the freedesktop.org trash of the test; Windows: the Recycle Bin, which gives no path back to undo with)
	when ODIN_OS == .Linux {
		testing.expect(t, fs.exists(fs.join(data, "Trash/files/archive.zip", context.temp_allocator)), "into the trash")
		info, _ := os.read_entire_file(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator), context.temp_allocator)
		testing.expect(t, strings.has_prefix(string(info), "[Trash Info]\nPath=/"), "with its .trashinfo")
		testing.expect(t, strings.contains(string(info), "/archive.zip\nDeletionDate="), "where it was, and when")
	}

	// undo, step by step: the trash (Linux), the move, the second copy
	when ODIN_OS == .Linux {
		session.key(s, .Z, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "archive.zip", context.temp_allocator)), "undo: archive.zip back from the trash")
		testing.expect(t, !fs.exists(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator)), "its .trashinfo gone")
	}
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
	session.wait_box(s, "delete")
	session.click(s, "delete")
	wait_jobs(s)
	testing.expect(t, !fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "deleted")
	testing.expect(t, !slice.contains(shown_names(tab), "notes.txt"))
}

@(test)
test_watch :: proc(t: ^testing.T) {
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
}

@(test)
test_undo_names :: proc(t: ^testing.T) {
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
}

@(test)
test_session :: proc(t: ^testing.T) {
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
		app_close(app)
	}
	testing.expect(t, fs.exists(file), "the session is written")
	// the folder Projects goes: its tab opens at its parent
	testing.expect(t, fs.remove(fs.join(dir, "Projects", context.temp_allocator)) == .None)
	{
		context.allocator = runtime.heap_allocator()
		app := app_open({headless = true, session = file})
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
		testing.expect_value(t, app.panels[1].tabs[0].path, dir)
		testing.expect_value(t, app.focus, 1)
		testing.expect_value(t, len(app.bookmarks), 1)
	}
}

@(test)
test_goto :: proc(t: ^testing.T) {
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
}

@(test)
test_more_actions :: proc(t: ^testing.T) {
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
}

@(test)
test_batch_rename :: proc(t: ^testing.T) {
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
}

@(test)
test_drag_and_drop :: proc(t: ^testing.T) {
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
	platform.drag_script(app.main.win, {{to, {}}, {to, {}}})
	session.press(s, from)
	session.move(s, from + {0, 30})
	session.move(s, from + {0, 60})
	session.release(s, from + {0, 60})
	session.frames(s, 2)
	wait_jobs(s)
	testing.expect(t, fs.exists(fs.join(dir, "Photos/archive.zip", context.temp_allocator)), "dragged into Photos")

	// files of this folder dropped on its own list: nothing
	here := fs.join(dir, "notes.txt", context.temp_allocator)
	testing.expect_value(t, drop_effect_for_test(app, {here}, dir), Maybe(platform.Drop_Effect)(nil))
	testing.expect_value(t, drop_effect_for_test(app, {fs.join(dir, "Documents", context.temp_allocator)}, fs.join(dir, "Documents/Sub", context.temp_allocator)), Maybe(platform.Drop_Effect)(nil))
}

@(test)
test_band :: proc(t: ^testing.T) {
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
}

@(test)
test_types :: proc(t: ^testing.T) {
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
}

@(test)
test_tab_drag :: proc(t: ^testing.T) {
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
}

// No two commands share a key; every command has one.
@(test)
test_keys :: proc(t: ^testing.T) {
	seen := make(map[Shortcut]string, context.temp_allocator)
	for c in COMMANDS {
		testing.expectf(t, c.keys[0].key != .None, "%s has a key", c.id)
		for k in c.keys {
			if k.key == .None { continue }
			if other, taken := seen[k]; taken { testing.expectf(t, false, "%s and %s share %s", other, c.id, shortcut_text(k)) }
			seen[k] = c.id
		}
	}
}

@(test)
test_layouts :: proc(t: ^testing.T) {
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
	// read again from its file
	layouts_free(&app.layouts)
	testing.expect(t, layout_open(app, "work"))
	wait_read(s)
	testing.expect_value(t, len(app.panels), 2)
}

// classeur install, status, uninstall, on the test's own folders (never the person's desktop).
@(test)
test_install :: proc(t: ^testing.T) {
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
}
