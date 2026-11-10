package classeur

// GoTo (Ctrl+G, a click on the empty part of the path), File Pilot's: one field, and under it where it can go.
//   - Empty: the recent folders, the bookmarks, the places.
//   - A path (it starts with / or ~, or a drive on Windows): the folders in the folder it names so far, found by the
//     letters after its last separator (fuzzy); Tab completes the path to the row chosen.
//   - Words: the recent folders, the bookmarks, the places and the current folder's folders, found by their path.
// Enter goes to the row chosen; a file's path goes to its folder with the file at the cursor. The folder a path names
// is read on a worker; its folders are kept until the path names another.

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

GOTO_ROWS :: 12

Goto :: struct {
	open:      bool,
	field:     ui.Text_Field,
	sel:       int,
	scroll:    int,
	focus_due: bool,
	mouse:     [2]f32,
	dir:       string,     // owned: the folder whose folders `names` holds ("": none read)
	names:     [dynamic]string,   // owned: its folders
	files:     [dynamic]string,   // owned: its other entries (a path typed in full goes there, not to a folder like it)
	moved:     bool,       // the person chose a row (Up, Down, the pointer): Enter goes there
	asked:     string,     // owned: the folder asked last (its answer alone is taken)
}

goto_free :: proc(g: ^Goto) {
	ui.field_destroy(&g.field)
	delete(g.dir)
	delete(g.asked)
	for n in g.names { delete(n) }
	delete(g.names)
	for n in g.files { delete(n) }
	delete(g.files)
	g^ = {}
}

act_goto_popup :: proc(app: ^App) {
	g := &app.goto
	g.open = true
	ui.field_clear(&g.field)
	g.sel, g.scroll, g.moved = 0, 0, false
	g.focus_due = true
	// (read again at each opening: a folder made since, a listing that failed)
	delete(g.asked)
	g.asked = ""
}

@(private = "file")
Goto_Row :: struct {
	path:   string,
	label:  string,     // what the row shows (the fuzzy ranges are on it)
	kind:   string,     // "Recent", "Bookmark", "Place", "Folder"
	icon:   string,
	score:  int,
	ranges: []ui.Fuzzy_Range,
}

// Whether the text names a path rather than words.
@(private = "file")
is_path_text :: proc(s: string) -> bool {
	if strings.has_prefix(s, "/") || strings.has_prefix(s, "~") { return true }
	when ODIN_OS == .Windows {
		if len(s) >= 2 && s[1] == ':' { return true }
		if strings.has_prefix(s, "\\") { return true }
	}
	return false
}

// "~/x" with the home folder in full.
@(private = "file")
expand_home :: proc(app: ^App, s: string) -> string {
	if s == "~" { return strings.concatenate({app.home, fs.SEPARATOR_STRING}, context.temp_allocator) }   // (its folders)
	if strings.has_prefix(s, "~/") || strings.has_prefix(s, "~\\") { return fs.join(app.home, s[2:], context.temp_allocator) }
	return s
}

@(private = "file")
Goto_Read :: struct {
	app:   ^App,
	dir:   string,
	names: [dynamic]string,
	files: [dynamic]string,
}

// Asks the folders of `dir` (once per folder).
@(private = "file")
goto_ask :: proc(app: ^App, dir: string) {
	g := &app.goto
	if dir == g.asked { return }
	delete(g.asked)
	g.asked = strings.clone(dir)
	job := new(Goto_Read)
	job^ = {app = app, dir = strings.clone(dir)}
	pool_submit(&app.pool, proc(data: rawptr) {
		job := (^Goto_Read)(data)
		l: fs.Listing
		defer fs.listing_destroy(&l)
		if fs.list(&l, job.dir) == .None {
			for e in l.entries { append(e.kind == .Directory ? &job.names : &job.files, strings.clone(e.name)) }
		}
		if !ui.post(&job.app.main.state, goto_read_done, job) { goto_read_free(job) }
	}, job)
}

@(private = "file")
goto_read_free :: proc(job: ^Goto_Read) {
	delete(job.dir)
	for n in job.names { delete(n) }
	delete(job.names)
	for n in job.files { delete(n) }
	delete(job.files)
	free(job)
}

@(private = "file")
goto_read_done :: proc(data: rawptr, word: u64) {
	job := (^Goto_Read)(data)
	g := &job.app.goto
	if job.dir != g.asked {
		goto_read_free(job)
		return
	}
	delete(g.dir)
	for n in g.names { delete(n) }
	delete(g.names)
	for n in g.files { delete(n) }
	delete(g.files)
	g.dir, g.names, g.files = job.dir, job.names, job.files
	slice.sort_by(g.names[:], proc(a, b: string) -> bool { return fs.name_compare(a, b) < 0 })
	app := job.app
	free(job)
	app_frames(app)
}

@(private = "file")
goto_rows :: proc(app: ^App, text: string) -> []Goto_Row {
	g := &app.goto
	rows := make([dynamic]Goto_Row, context.temp_allocator)
	if is_path_text(text) {
		full := expand_home(app, text)
		// the folder named so far, and the letters after it
		cut := len(full)
		for cut > 0 && !fs.is_separator(full[cut - 1]) { cut -= 1 }
		dir := cut > 0 ? fs.clean(full[:cut], context.temp_allocator) : full
		rest := full[cut:]
		goto_ask(app, dir)
		if g.dir == dir {
			for n in g.names {
				if !app.show_hidden && strings.has_prefix(n, ".") && !strings.has_prefix(rest, ".") { continue }
				score, ranges, ok := ui.fuzzy_score(rest, n)
				if ok { append(&rows, Goto_Row{fs.join(dir, n, context.temp_allocator), n, "Folder", lucide.FOLDER, score, ranges}) }
			}
		}
		slice.stable_sort_by(rows[:], proc(a, b: Goto_Row) -> bool { return a.score > b.score })
		return rows[:]
	}
	seen := make(map[string]bool, context.temp_allocator)
	add :: proc(rows: ^[dynamic]Goto_Row, seen: ^map[string]bool, app: ^App, text, path, kind, icon: string) {
		if path in seen { return }
		label := home_path(app, path)
		score, ranges, ok := ui.fuzzy_score(text, label)
		if !ok { return }
		seen[path] = true
		append(rows, Goto_Row{path, label, kind, icon, score, ranges})
	}
	for p in app.recents { add(&rows, &seen, app, text, p, "Recent", lucide.HISTORY) }
	for p in app.bookmarks { add(&rows, &seen, app, text, p, "Bookmark", lucide.BOOKMARK) }
	for p in app.places { add(&rows, &seen, app, text, p.path, "Place", lucide.HOME) }
	if t := current_tab(app); t != nil && text != "" {
		for e in t.folder.listing.entries {
			if e.kind == .Directory { add(&rows, &seen, app, text, fs.join(t.path, e.name, context.temp_allocator), "Folder", lucide.FOLDER) }
		}
	}
	if text != "" { slice.stable_sort_by(rows[:], proc(a, b: Goto_Row) -> bool { return a.score > b.score }) }
	return rows[:]
}

// Goes to `path` in the current tab (a file's path, or one that is gone: the read, on a worker, goes to the folder that
// holds it, tab.odin's load_done).
goto_path :: proc(app: ^App, path: string) -> bool {
	t := current_tab(app)
	if t == nil { return false }
	t.focus_due = .List
	tab_go(app, t, path)
	return true
}

// Whether Enter goes to the path as it is typed: it ends with a separator, or its last part is a name in the folder
// read in full (File Pilot's: a row is taken when the person chose one, or the letters are a part of a name).
@(private = "file")
typed_is_whole :: proc(app: ^App, text: string) -> bool {
	g := &app.goto
	if !is_path_text(text) { return false }
	full := expand_home(app, text)
	if len(full) > 0 && fs.is_separator(full[len(full) - 1]) { return true }
	cut := len(full)
	for cut > 0 && !fs.is_separator(full[cut - 1]) { cut -= 1 }
	rest := full[cut:]
	if g.dir != fs.clean(full[:cut], context.temp_allocator) { return false }
	for n in g.names { if n == rest { return true } }
	for n in g.files { if n == rest { return true } }
	return false
}

goto_build :: proc(app: ^App) {
	g := &app.goto
	if !g.open { return }
	em := ui.font_size()
	pw := min(em * 46, app.room * ui.scale() * 0.92)
	text := ui.field_string(&g.field)
	rows := goto_rows(app, text)
	n := len(rows)
	if n > 0 {
		if ui.key_press(.Down) { g.sel = (g.sel + 1) % n; g.moved = true }
		if ui.key_press(.Up) { g.sel = (g.sel + n - 1) % n; g.moved = true }
		if ui.key_press(.Page_Down) { g.sel = min(g.sel + GOTO_ROWS, n - 1) }
		if ui.key_press(.Page_Up) { g.sel = max(g.sel - GOTO_ROWS, 0) }
		g.sel = clamp(g.sel, 0, n - 1)
		if g.sel < g.scroll { g.scroll = g.sel }
		if g.sel >= g.scroll + GOTO_ROWS { g.scroll = g.sel - GOTO_ROWS + 1 }
		g.scroll = clamp(g.scroll, 0, max(n - GOTO_ROWS, 0))
		// Tab: the path completed to the row chosen, ready for the next folder
		if ui.key_press(.Tab) {
			ui.field_set(&g.field, fmt.tprintf("%s%s", home_path(app, rows[g.sel].path), fs.SEPARATOR_STRING))
			g.sel, g.scroll = 0, 0
		}
	}
	mouse := ui.mouse_pos()
	moved := abs(mouse.x - g.mouse.x) + abs(mouse.y - g.mouse.y) > 0.5
	g.mouse = mouse
	go_to := ""

	if ui.modal("goto", pw, &g.open, 0.12) {
		if ui.style({width = ui.px(pw)}) {
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.2))})
			if ui.row(.Center, id = "###goto_head") {
				ui.spacer(ui.px(em * 0.8))
				if ui.tags("weak") { glyph(app, lucide.FOLDER_SEARCH, em * 1.8) }
				input_key := ui.key_from_string(ui.parent_box().key, "###goto_input")
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.3))})
				res: ui.Edit_Result
				if ui.tags("bare") { res = ui.line_edit("###goto_input", &g.field, "Go to: a path, or a few letters of a folder") }
				if res.changed { g.sel, g.scroll, g.moved = 0, 0, false }
				if res.cancelled { g.open = false }
				if res.committed {
					// (the path as typed when it is whole, else the row chosen, else the path typed as it is)
					switch {
					case typed_is_whole(app, text) && !g.moved: go_to = expand_home(app, text)
					case n > 0:                                 go_to = rows[g.sel].path
					case is_path_text(text):                    go_to = expand_home(app, text)
					}
				}
				if g.focus_due { ui.set_focus(input_key); g.focus_due = false }
				ui.spacer(ui.px(em * 0.8))
			}
			ui.hline(ui.px(pw))
			ui.next({width = ui.px(pw), height = ui.children_sum()})
			if ui.column(.Center, id = "###goto_rows") {
				for vi in 0 ..< min(n, GOTO_ROWS) {
					at := g.scroll + vi
					r := rows[at]
					selected := at == g.sel
					if selected { ui.push_tags("selected") }
					ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.2)), radius = 0})
					flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects}
					if selected { flags += {.Draw_Background} }
					sig: ui.Signal
					if ui.row(.Center, flags, fmt.tprintf("###goto_row%d", vi)) {
						sig = ui.signal(ui.parent_box())
						ui.spacer(ui.px(em * 0.8))
						path_icon(app, r.path, true, em * 1.7)
						ui.spacer(ui.px(em * 0.4))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label_fuzzy(shown_text(r.label), r.ranges)
						if ui.tags("weak") {
							ui.next({width = ui.text_size(em * 0.5), height = ui.pct(1), font_size = math.round(em * 0.85)})
							ui.label(fmt.tprintf("%s###kind", r.kind))
						}
						ui.spacer(ui.px(em * 0.8))
					}
					if selected { ui.pop_tags() }
					if sig.clicked { go_to = r.path }
					if sig.hovering && moved { g.sel, g.moved = at, true }
				}
			}
			if n == 0 {
				if ui.tags("weak") {
					ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.5)), text_align = .Center})
					ui.label(is_path_text(text) ? "No folder there has these letters. Enter goes to the path typed.###goto_none" : "No folder has these letters.###goto_none")
				}
			}
			ui.hline(ui.px(pw))
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.1))})
			if ui.row(.Center, id = "###goto_foot") {
				ui.spacer(ui.px(em * 0.9))
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.85)})
					ui.label("Up, Down: choose   Tab: complete the path   Enter: go   Esc: close###goto_help")
				}
			}
		}
	}
	if go_to != "" {
		path := strings.clone(go_to, context.temp_allocator)
		if goto_path(app, path) { g.open = false }
	}
}
