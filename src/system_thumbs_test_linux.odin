#+build linux
package classeur

// The system's thumbnails (desktop.thumbnail): a PDF shows its first page in the inspector and on its card in the grid,
// made by a thumbnailer of the test's own (found through XDG_DATA_HOME and XDG_DATA_DIRS) and kept in a cache of the
// test's own (XDG_CACHE_HOME): never the person's thumbnailers nor their ~/.cache.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:log"
import "core:testing"
import desktop "gt:desktop"
import "gt:png"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

@(private = "file")
SYSTEM_THUMBS_ENV :: [?]string{"XDG_DATA_HOME", "XDG_DATA_DIRS", "XDG_CACHE_HOME"}

// The PNG files a folder of the cache holds (not the temporary ones, whose names start with a dot).
@(private = "file")
cached_count :: proc(dir: string) -> int {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil { return 0 }
	n := 0
	for e in entries { if strings.has_suffix(e.name, ".png") && !strings.has_prefix(e.name, ".") { n += 1 } }
	return n
}

@(private = "file")
cp_on_path :: proc() -> bool {
	for d in strings.split(os.get_env("PATH", context.temp_allocator), ":", context.temp_allocator) {
		if d != "" && os.is_file(strings.concatenate({d, "/cp"}, context.temp_allocator)) { return true }
	}
	return false
}

@(test)
test_system_thumbnails :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		if !cp_on_path() {
			log.info("cp is not on the PATH: the system's thumbnails are not checked")
			return
		}
		files := FIXTURE
		dir := make_fixture(t, files[:])
		// the test's own XDG folders: a MIME database that knows PDF files, a thumbnailer of them (cp of a red page of
		// 300 x 400 to its output), an empty cache
		data := fs.join(dir, ".xdg/data", context.temp_allocator)
		cache := fs.join(dir, ".xdg/cache", context.temp_allocator)
		_ = os.make_directory_all(fs.join(data, "mime", context.temp_allocator))
		_ = os.make_directory_all(fs.join(data, "thumbnailers", context.temp_allocator))
		_ = os.make_directory_all(cache)
		w, h := 300, 400
		px := make([]u8, w * h * 4, context.temp_allocator)
		for i := 0; i < len(px); i += 4 { px[i], px[i + 3] = 255, 255 }
		page := fs.join(dir, ".xdg/page.png", context.temp_allocator)
		testing.expect(t, os.write_entire_file(page, png.encode(px, w, h, .Fast, context.temp_allocator)) == nil)
		testing.expect(t, os.write_entire_file(fs.join(data, "mime/globs2", context.temp_allocator), "50:application/pdf:*.pdf\n") == nil)
		exec := strings.concatenate({"cp ", desktop.escape_value(desktop.quote_exec_argument(page)), " %o"}, context.temp_allocator)
		testing.expect(t, os.write_entire_file(fs.join(data, "thumbnailers/page.thumbnailer", context.temp_allocator),
			strings.concatenate({"[Thumbnailer Entry]\nTryExec=cp\nExec=", exec, "\nMimeType=application/pdf;\n"}, context.temp_allocator)) == nil)
		env := SYSTEM_THUMBS_ENV
		before: [len(SYSTEM_THUMBS_ENV)]string
		had: [len(SYSTEM_THUMBS_ENV)]bool
		for name, i in env { before[i], had[i] = os.lookup_env(name, runtime.heap_allocator()) }
		defer for name, i in env {
			if had[i] { os.set_env(name, before[i]) } else { os.unset_env(name) }
			delete(before[i], runtime.heap_allocator())
		}
		os.set_env("XDG_DATA_HOME", data)
		// (the test's folder first, the system's after it: the graphics drivers' files are found there, the renderer needs
		// them; replaced, the window opened with no adapter and every later test with it)
		dirs := os.get_env("XDG_DATA_DIRS", context.temp_allocator)
		if dirs == "" { dirs = "/usr/local/share:/usr/share" }
		os.set_env("XDG_DATA_DIRS", strings.concatenate({data, ":", dirs}, context.temp_allocator))
		os.set_env("XDG_CACHE_HOME", cache)

		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		app.system_thumbs = true   // (off headless: this test gives its own cache)
		tab := current_tab(app)

		// the inspector: the PDF's first page, as a picture, said so under it
		point_at(t, tab, "report 2.pdf")
		session.key(s, .Space)
		testing.expect(t, app.inspector.open, "the inspector is open")
		session.wait_until(s, proc(s: ^session.Session) -> bool { return (^App)(s.user).inspector.ready }, "the inspector")
		session.frames(s, 2)
		testing.expect_value(t, app.inspector.kind, Inspect_Kind.Picture)
		testing.expect_value(t, app.inspector.size, [2]int{300, 400})
		testing.expect(t, session.find(s, "insp_pic") != nil, "the picture is shown")
		testing.expect(t, session.find_text(s, "First page") != nil, "said to be the first page")
		testing.expect(t, session.find_text(s, "No preview") == nil, "not the text of no preview")
		testing.expect_value(t, cached_count(fs.join(cache, "thumbnails/xx-large", context.temp_allocator)), 1)
		session.key(s, .Space)
		testing.expect(t, !app.inspector.open, "the inspector is closed")

		// the grid: each PDF's card has its page (made at 256 pixels: the large folder), a text file has none
		session.key(s, .N2, {.Ctrl})
		testing.expect_value(t, tab_mode(tab), View_Mode.Grid)
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			app := (^App)(s.user)
			if len(app.thumbs) == 0 { return false }
			for _, th in app.thumbs { if th.state == .Asked { return false } }
			return true
		}, "the thumbnails")
		state_of :: proc(app: ^App, tab: ^Tab, name: string) -> (Thumb, bool) {
			for e in tab.folder.listing.entries {
				if e.name != name { continue }
				th, found := app.thumbs[thumb_key(fs.join(tab.path, name, context.temp_allocator), e.size, e.mtime)]
				return th, found
			}
			return {}, false
		}
		for name in ([]string{"report 2.pdf", "report 10.pdf"}) {
			th, asked := state_of(app, tab, name)
			testing.expectf(t, asked && th.state == .Ready, "%s has its thumbnail: %v", name, th.state)
			testing.expect_value(t, th.size, [2]int{192, 256})
		}
		th, asked := state_of(app, tab, "notes.txt")
		testing.expect(t, asked && th.state == .Failed, "a text file has no thumbnail: its card keeps its icon")
		testing.expect_value(t, cached_count(fs.join(cache, "thumbnails/large", context.temp_allocator)), 1)   // (report 2.pdf's came from xx-large)
	})
}
