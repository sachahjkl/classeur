package classeur

// classeur's own sources of the command palette (src/md/features/palette.md): `@` the tabs, under their panel's name;
// `/` the folders, read on the workers. The commands, the settings and the views' moves are in palette.odin.

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

// Once, with the palette (palette_start).
palette_sources_add :: proc(app: ^App) {
	p := &app.palette
	// (the tabs' ids last one run: their choices are not remembered)
	p.tabs = {
		name = "tab", title = i18n.later("Tabs"), prefix = .Go_To, plain = true, enter = i18n.later("Show"),
		read = tabs_read, mark = tabs_mark, poll = tabs_poll, user = app,
	}
	p.folders = {
		name = "folder", title = i18n.later("Folders"), prefix = .Paths, plain = true, remember = true, searches = true,
		enter = i18n.later("Go"), alternates = {ctrl = i18n.later("Open in a new tab")}, read = folders_read, user = app,
	}
	ui.palette_add(&p.pal, &p.tabs)
	ui.palette_add(&p.pal, &p.folders)
	ui.palette_files_add(&p.pal, &p.files, {
		title      = i18n.later("Files"),
		dirs       = true,
		plain      = false,
		enter      = i18n.later("Go"),
		alternates = {ctrl = i18n.later("Open in a new tab")},
	})
}

////////////////////////////////
// `@` The tabs

// Every tab of every panel, the panel its group (one panel: none), in an answer of its own: made at once, from the
// panels (a few dozen tabs).
@(private = "file")
tabs_read :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, q: ui.Palette_Question) {
	app := (^App)(src.user)
	a: ui.Palette_Answer
	al := ui.palette_answer_allocator(&a)
	items := make([dynamic]ui.Palette_Item, al)
	for panel, pi in app.panels {
		group := len(app.panels) > 1 ? fmt.tprintf(i18n.tr("Panel %d"), pi + 1) : ""
		for t in panel.tabs {
			append(&items, ui.palette_item_clone({
				id = fmt.tprintf("%d", t.id), title = tab_title(app, t), detail = home_path(app, t.path), icon = lucide.FOLDER, group = group,
			}, al))
		}
	}
	a.items = items[:]
	ui.palette_answer(q, &a)
}

// The tab shown in the panel that has the keyboard.
@(private = "file")
tabs_mark :: proc(src: ^ui.Palette_Source, id: string) -> bool {
	app := (^App)(src.user)
	t := current_tab(app)
	if t == nil { return false }
	n, ok := strconv.parse_u64(id)
	return ok && n == t.id
}

// (at each build while the palette is open) The tabs changed: their ids, their paths, the one shown in each panel, the
// panel with the keyboard. One pass over the tabs, not over a folder's entries.
@(private = "file")
tabs_poll :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source) {
	app := (^App)(src.user)
	h: u64 = 14695981039346656037   // (FNV-1a)
	mix :: proc(h: ^u64, x: u64) { h^ = (h^ ~ x) * 1099511628211 }
	mix(&h, u64(app.focus))
	for panel in app.panels {
		mix(&h, u64(panel.active) + 1)
		for t in panel.tabs {
			mix(&h, t.id)
			for i in 0 ..< len(t.path) { mix(&h, u64(t.path[i])) }
		}
	}
	if h != app.palette.tabs_sig {
		app.palette.tabs_sig = h
		src.version += 1
	}
}

// A tab chosen: its panel gets the keyboard and shows it.
palette_tab_chosen :: proc(app: ^App, id: string) {
	n, ok := strconv.parse_u64(id)
	if !ok { return }
	for panel, pi in app.panels {
		for t, i in panel.tabs {
			if t.id != n { continue }
			app.focus, panel.active = pi, i
			keys_to(app, .List)
			return
		}
	}
}

////////////////////////////////
// `/` The folders

// What a question of the folders source asks a worker: the folder a path names and the letters after its last
// separator, the words (the recent folders, the bookmarks and the places they find), and copies of what it reads. Its
// strings are in its answer's arena, which the palette takes whole.
@(private = "file")
Folders_Job :: struct {
	app:         ^App,
	q:           ui.Palette_Question,
	answer:      ui.Palette_Answer,
	dir:         string,   // "": no path typed (a plain search)
	rest:        string,
	words:       string,
	home:        string,
	places:      []Folder_Place,
	show_hidden: bool,
	failed:      fs.Error,
}

@(private = "file")
Folder_Place :: struct { path, icon: string }

// A question: the path typed and the places copied (lists of a few dozen), then the reading and the matching on a worker.
// Under `/` the text is a path (its first separator is the prefix: "/home/x"; a drive, a share or "~" as they are) and
// words; in a plain search, words only.
@(private = "file")
folders_read :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, q: ui.Palette_Question) {
	app := (^App)(src.user)
	job := new(Folders_Job)
	job.app, job.q, job.show_hidden = app, q, app.show_hidden
	al := ui.palette_answer_allocator(&job.answer)
	text := strings.trim_space(q.query)
	job.words, job.home = strings.clone(text, al), strings.clone(app.home, al)
	if q.prefix == .Paths && text != "" {
		full := fs.looks_like_path(text) ? expand_home(app, text) : fs.join(fs.SEPARATOR_STRING, text, context.temp_allocator)
		cut := len(full)
		for cut > 0 && !fs.is_separator(full[cut - 1]) { cut -= 1 }
		if cut > 0 {
			job.dir = fs.clean(full[:cut], al)
			job.rest = strings.clone(full[cut:], al)
		}
	}
	places := make([dynamic]Folder_Place, 0, len(app.recents) + len(app.bookmarks) + len(app.places), al)
	for x in app.recents { append(&places, Folder_Place{strings.clone(x, al), lucide.HISTORY}) }
	for x in app.bookmarks { append(&places, Folder_Place{strings.clone(x, al), lucide.BOOKMARK}) }
	for x in app.places { append(&places, Folder_Place{strings.clone(x.path, al), lucide.HOME}) }
	job.places = places[:]
	tasks.add(&app.pool, folders_run, job)
}

// The last folder the folders source listed: its path, its modification time when it was listed, the names of its
// folders. Typing within one folder lists it once: a chore that finds the same path and the same time takes the names
// from here. Read and written by the chores, under its mutex; in the heap (a chore's temporary memory goes).
Folders_Cache :: struct {
	mutex: sync.Mutex,
	path:  string,
	mtime: i64,
	names: [dynamic]string,
}

folders_cache_free :: proc(c: ^Folders_Cache) {
	heap := runtime.heap_allocator()   // (what the chores made it with)
	delete(c.path, heap)
	for n in c.names { delete(n, heap) }
	delete(c.names)
	c^ = {}
}

// (on a worker) The names of the folders in `dir`, in temporary memory: the cache's when the folder did not change since
// it was listed, else listed and kept.
@(private = "file")
folders_names :: proc(c: ^Folders_Cache, dir: string) -> (names: []string, err: fs.Error) {
	info, known := fs.stat(dir)
	sync.mutex_lock(&c.mutex)
	if known && c.path == dir && c.mtime == info.mtime {
		names = slice.clone(c.names[:], context.temp_allocator)   // (the strings stay the cache's until a newer listing: copied too)
		for &n in names { n = strings.clone(n, context.temp_allocator) }
		sync.mutex_unlock(&c.mutex)
		return names, .None
	}
	sync.mutex_unlock(&c.mutex)
	l: fs.Listing
	defer fs.listing_destroy(&l)
	if e := fs.list(&l, dir); e != .None { return nil, e }
	out := make([dynamic]string, 0, len(l.entries), context.temp_allocator)
	for e in l.entries { if e.kind == .Directory { append(&out, strings.clone(e.name, context.temp_allocator)) } }
	if known {
		heap := runtime.heap_allocator()
		sync.mutex_lock(&c.mutex)
		delete(c.path, heap)
		for n in c.names { delete(n, heap) }
		clear(&c.names)
		if c.names.allocator.procedure == nil { c.names.allocator = heap }
		c.path, c.mtime = strings.clone(dir, heap), info.mtime
		for n in out { append(&c.names, strings.clone(n, heap)) }
		sync.mutex_unlock(&c.mutex)
	}
	return out[:], .None
}

// (on a worker) The folders of the path's folder that the letters find, best first, then the places the words find; the
// question ended here (an end is safe from any thread).
@(private = "file")
folders_run :: proc(data: rawptr) {
	job := (^Folders_Job)(data)
	defer free(job)
	al := ui.palette_answer_allocator(&job.answer)
	items := make([dynamic]ui.Palette_Item, al)
	seen := make(map[string]bool, context.temp_allocator)
	if job.dir != "" {
		if names, err := folders_names(&job.app.palette.folders_cache, job.dir); err != .None {
			job.failed = err
		} else {
			Found :: struct { name: string, score: int }
			found := make([dynamic]Found, context.temp_allocator)
			for name in names {
				if !job.show_hidden && strings.has_prefix(name, ".") && !strings.has_prefix(job.rest, ".") { continue }
				if job.rest == "" { append(&found, Found{name, 0}); continue }
				if score, _, ok := ui.fuzzy_score(job.rest, name); ok { append(&found, Found{name, score}) }
			}
			slice.sort_by(found[:], proc(a, b: Found) -> bool { return a.score != b.score ? a.score > b.score : fs.name_compare(a.name, b.name) < 0 })
			shown := home_shown(job.home, job.dir)
			for f in found {
				path := fs.join(job.dir, f.name, al)
				seen[path] = true
				append(&items, ui.Palette_Item{id = path, title = strings.clone(f.name, al), detail = strings.clone(shown, al), icon = lucide.FOLDER, completion = folder_completion(path, al)})
			}
		}
	}
	for x in job.places {
		if x.path in seen { continue }
		label := home_shown(job.home, x.path)
		if job.words != "" {
			if _, _, ok := ui.fuzzy_score(job.words, label); !ok { continue }
		}
		seen[x.path] = true
		name := fs.base(x.path)
		if name == "" { name = x.path }
		append(&items, ui.Palette_Item{id = x.path, title = strings.clone(name, al), detail = strings.clone(label, al), icon = x.icon, completion = folder_completion(x.path, al)})
	}
	job.answer.items = items[:]
	// (the answer taken whole; a folder that could not be read, and nothing else found, says so)
	if job.failed != .None && len(job.answer.items) == 0 {
		_ = ui.palette_answer_error(job.q, i18n.tr(fs.ERROR_TEXT[job.failed]))
		ui.palette_answer_free(&job.answer)
		return
	}
	_ = ui.palette_answer(job.q, &job.answer)
}

// What Tab puts in the field for a folder: its path after the prefix, a separator at its end (the next folder's letters
// come after it). A path that starts with a separator is its own prefix.
@(private = "file")
folder_completion :: proc(path: string, allocator := context.allocator) -> string {
	if len(path) > 0 && path[0] == '/' { return strings.concatenate({path, fs.SEPARATOR_STRING}, allocator) }
	return strings.concatenate({"/", path, fs.SEPARATOR_STRING}, allocator)
}

// The path with "~" for the home folder (home_path's, for a worker: the home is the job's copy).
@(private = "file")
home_shown :: proc(home, path: string) -> string {
	if path == home { return "~" }
	if strings.has_prefix(path, home) && len(path) > len(home) && fs.is_separator(path[len(home)]) { return fmt.tprintf("~%s", path[len(home):]) }
	return path
}

// A folder chosen: the current tab goes there; with Ctrl, a new tab after it.
palette_folder_chosen :: proc(app: ^App, path: string, mods: platform.Modifiers) {
	if mods == {.Ctrl} {
		p := current_panel(app)
		if p != nil { tab_open(app, p, path, p.active + 1) }
		return
	}
	_ = goto_path(app, strings.clone(path, context.temp_allocator))
}
