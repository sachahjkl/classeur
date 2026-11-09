package classeur

// classeur as a person meets it, with no window of the system (gui_toolkit's testkit/session): a folder made for the
// test, read, sorted, filtered, entered and left; a folder made and renamed; the palette; tabs and panels.
// Run with -define:ODIN_TEST_THREADS=1 (one interface at a time).

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import "gt:testkit"
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
	dir := testkit.temp_folder(t, "classeur")
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
	testing.expect_value(t, fmt.tprint(shown_names(tab)), `["report 2.pdf", "report 10.pdf"]`)
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

// The pictures of the README (classeurtool shots): a home folder of made-up files, two panels, the palette.
@(test)
test_shots :: proc(t: ^testing.T) {
	when !SHOTS { return }
	home := []string{
		"Desktop/", "Documents/", "Downloads/", "Music/", "Pictures/", "Projects/", "Videos/",
		"Projects/classeur/", "Projects/website/", "Projects/notes.md",
		"Documents/Invoices/", "Documents/Taxes 2025/", "Documents/contract.pdf", "Documents/budget 2026.xlsx", "Documents/letter.odt",
		"Pictures/Holidays 2026/", "Pictures/harbour.jpg", "Pictures/mountain 2.png", "Pictures/mountain 10.png",
		"Downloads/odin-linux-amd64.tar.gz", "Downloads/fonts.zip", "Downloads/manual.pdf", "Downloads/setup.exe",
		"Music/album/", "Music/track 01.flac", "Music/track 02.flac", "Videos/talk.mp4",
		"todo.txt", "photo.jpg", "build.sh", "README.md", "archive.zip", "notes 2.txt", "notes 10.txt",
	}
	dir := make_fixture(t, home)
	s, app := start(t, {dir}, size = {1400, 820}, home = dir)
	session.save_png(s, "main.png")

	session.key(s, .D, {.Ctrl, .Shift})
	wait_read(s)
	other := current_tab(app)
	context.allocator = runtime.heap_allocator()   // (what the application keeps is its allocator's)
	tab_go(app, other, fs.join(dir, "Pictures", context.temp_allocator))
	wait_read(s)
	session.key(s, .Down, {.Shift}, repeat = 2)
	session.frames(s, 2)
	session.save_png(s, "panels.png")

	session.key(s, .P, {.Ctrl, .Shift})
	session.type_text(s, "tab")
	session.frames(s, 2)
	session.save_png(s, "palette.png")
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
	testing.expect(t, fs.exists(fs.join(data, "Trash/files/archive.zip", context.temp_allocator)), "into the trash")
	info, _ := os.read_entire_file(fs.join(data, "Trash/info/archive.zip.trashinfo", context.temp_allocator), context.temp_allocator)
	testing.expect(t, strings.has_prefix(string(info), "[Trash Info]\nPath=/"), "with its .trashinfo")
	testing.expect(t, strings.contains(string(info), "/archive.zip\nDeletionDate="), "where it was, and when")

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
