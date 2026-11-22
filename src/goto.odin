package classeur

// GoTo (Ctrl+G), File Pilot's: one field, and under it where it can go (src/md/features/goto.md). The path field of a
// panel shows the same rows (goto_rows).
//   - Empty: the recent folders, the bookmarks, the places.
//   - A path (it starts with / or ~, or a drive on Windows): the entries in the folder it names so far, found by the
//     letters after its last separator (fuzzy); Tab completes the path to the row chosen.
//   - Words, or a path from the current folder: the recent folders, the bookmarks and the places found by their path,
//     then every entry below the current folder, at any depth (deep_find.odin).
// Enter goes to the row chosen; a file's path goes to its folder with the file at the cursor. The folder a path names
// is read on a worker; its entries are kept until the path names another.

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "gt:i18n"
import lucide "gt:lucide"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

GOTO_ROWS :: 12

Goto :: struct {
	field:     ui.Line_Edit,
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
	ui.line_edit_destroy(&g.field)
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
	ui.line_edit_clear(&g.field)
	g.sel, g.scroll, g.moved = 0, 0, false
	g.focus_due = true
	goto_fresh(app)
	ui.view_open(&app.views, GOTO_VIEW, app)
}

// What GoTo and the path field read is refreshed at each opening: the live-watched filesearch index stays warm in real
// runs, and resets headless (tests) where watching is off so newly created fixture files are picked up.
goto_fresh :: proc(app: ^App) {
	g := &app.goto
	delete(g.asked)
	g.asked = ""
	if app.headless { deep_reset(app) }
}

// Its width when it opens as a dialog (em), and its top in the window.
GOTO_WIDTH_EM :: 46
GOTO_TOP :: 0.12

goto_register :: proc(app: ^App) {
	// (no header: its field is its top, as the palette's)
	ui.view_register(&app.views, GOTO_VIEW, goto_view, ui.View_Options{title = i18n.later("Go to"), icon = lucide.FOLDER_SEARCH, icon_font = app.icons, no_header = true, top = GOTO_TOP, width_em = GOTO_WIDTH_EM})
}

Goto_Row :: struct {
	path:   string,
	label:  string,     // what the row shows (the fuzzy ranges are on it)
	kind:   string,     // "Recent", "Bookmark", "Place", "Folder", "File" (in the person's language: only shown)
	icon:   string,
	score:  int,
	ranges: []ui.Fuzzy_Range,
	folder: bool,
}

// What goto_rows says besides its rows: the deep search reads on (`reading`), and the entries it has read.
Goto_Rows :: struct {
	rows:    []Goto_Row,
	reading: bool,
	read:    int,
}

// "~/x" with the home folder in full (GoTo's, the palette's folders).
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
	tasks.add(&app.pool, proc(data: rawptr) {
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

// The rows of GoTo and of the path field for `text` below the folder `root` (view_panel.odin): the path typed's
// entries, or the places its letters find, then the deep search's rows. A frame goes through the places (a few dozen)
// and the rows of the last answers, never through a folder's entries.
goto_rows :: proc(app: ^App, root, text: string) -> (out: Goto_Rows) {
	g := &app.goto
	rows := make([dynamic]Goto_Row, context.temp_allocator)
	if fs.looks_like_path(text) {
		full := expand_home(app, text)
		// the folder named so far, and the letters after it
		cut := len(full)
		for cut > 0 && !fs.is_separator(full[cut - 1]) { cut -= 1 }
		dir := cut > 0 ? fs.clean(full[:cut], context.temp_allocator) : full
		rest := full[cut:]
		goto_ask(app, dir)
		if g.dir == dir {
			add :: proc(rows: ^[dynamic]Goto_Row, app: ^App, dir, rest, name: string, folder: bool) {
				if !app.show_hidden && strings.has_prefix(name, ".") && !strings.has_prefix(rest, ".") { return }
				score, ranges, ok := ui.fuzzy_score(rest, name)
				if !ok { return }
				// (a folder before a file of the same letters: a path goes on through folders)
				if folder { score += 1 }
				append(rows, Goto_Row{fs.join(dir, name, context.temp_allocator), name, folder ? i18n.tr("Folder") : i18n.tr("File"), folder ? lucide.FOLDER : lucide.FILE, score, ranges, folder})
			}
			for n in g.names { add(&rows, app, dir, rest, n, true) }
			for n in g.files { add(&rows, app, dir, rest, n, false) }
		}
		slice.stable_sort_by(rows[:], proc(a, b: Goto_Row) -> bool { return a.score > b.score })
		out.rows = rows[:]
		return
	}
	seen := make(map[string]bool, context.temp_allocator)
	add :: proc(rows: ^[dynamic]Goto_Row, seen: ^map[string]bool, app: ^App, text, path, kind, icon: string) {
		if path in seen { return }
		label := home_path(app, path)
		score, ranges, ok := ui.fuzzy_score(text, label)
		if !ok { return }
		seen[path] = true
		append(rows, Goto_Row{path, label, kind, icon, score, ranges, true})
	}
	for p in app.recents { add(&rows, &seen, app, text, p, i18n.tr("Recent"), lucide.HISTORY) }
	for p in app.bookmarks { add(&rows, &seen, app, text, p, i18n.tr("Bookmark"), lucide.BOOKMARK) }
	for p in app.places { add(&rows, &seen, app, text, p.path, i18n.tr("Place"), lucide.HOME) }
	query := strings.trim_space(text)
	if root != "" && query != "" {
		deep, reading, read := deep_rows(app, root, query)
		out.reading, out.read = reading, read
		for r in deep {
			path := fs.join(root, r.path, context.temp_allocator)
			if path in seen { continue }
			seen[path] = true
			folder := r.kind == .Directory
			append(&rows, Goto_Row{path, r.path, folder ? i18n.tr("Folder") : i18n.tr("File"), folder ? lucide.FOLDER : lucide.FILE, r.score, r.ranges, folder})
		}
	}
	// (one order for the places and what is below: a name that starts with the letters beats letters spread along a
	// recent folder's long path. A few dozen places and DEEP_ROWS rows: no pass over a folder)
	if query != "" { slice.stable_sort_by(rows[:], proc(a, b: Goto_Row) -> bool { return a.score > b.score }) }
	out.rows = rows[:]
	return
}

// What GoTo and the path field say when no row has the letters.
goto_none_text :: proc(text: string, found: Goto_Rows) -> string {
	switch {
	case fs.looks_like_path(text): return i18n.tr("Nothing there has these letters. Enter goes to the path typed.")
	case found.reading:            return i18n.tr("Searching below this folder…")
	}
	return i18n.tr("Nothing below this folder has these letters.")
}

// While the deep search reads: how far it went.
goto_reading_text :: proc(read: int) -> string {
	return fmt.tprintf(i18n.tr(read, "Searching: %d item read", "Searching: %d items read"), read)
}

// The folder GoTo searches below: the current tab's ("": none).
goto_root :: proc(app: ^App) -> string {
	t := current_tab(app)
	return t != nil ? t.path : ""
}

// Goes to `path` in the current tab (a file's path, or one that is gone: the read, on a worker, goes to the folder that
// holds it, tab.odin's load_done).
goto_path :: proc(app: ^App, path: string) -> bool {
	t := current_tab(app)
	if t == nil { return false }
	deep_note_opened(app, path)
	t.focus_due = .List
	tab_go(app, t, path)
	return true
}

// Whether Enter goes to the path as it is typed: it ends with a separator, or its last part is a name in the folder
// read in full (File Pilot's: a row is taken when the person chose one, or the letters are a part of a name).
@(private = "file")
typed_is_whole :: proc(app: ^App, text: string) -> bool {
	g := &app.goto
	if !fs.looks_like_path(text) { return false }
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

// The view: the field, the rows that match, the keys' help. As a dialog it is as wide as the window allows; elsewhere
// (floating, docked, in a window) as wide as its room.
@(private = "file")
goto_view :: proc(v: ^ui.View, app: ^App) {
	g := &app.goto
	em := ui.font_size()
	pw := v.presentation == .Dialog ? min(em * GOTO_WIDTH_EM, app.room * ui.scale() * 0.92) : ui.view_room(v).x
	text := ui.line_edit_string(&g.field)
	root := goto_root(app)
	found := goto_rows(app, root, text)
	rows := found.rows
	n := len(rows)
	mouse := ui.mouse_pos()
	moved := abs(mouse.x - g.mouse.x) + abs(mouse.y - g.mouse.y) > 0.5
	g.mouse = mouse
	go_to := ""

	{
		// (its keys read in its view: a dialog holds them; floating or docked, they are its own while it has the focus)
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
				ui.line_edit_set(&g.field, fmt.tprintf("%s%s", home_path(app, rows[g.sel].path), fs.SEPARATOR_STRING))
				g.sel, g.scroll = 0, 0
			}
		}
		if ui.style({width = ui.px(pw)}) {
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.2))})
			if ui.row(.Center, id = "###goto_head") {
				ui.space(ui.SPACE_3)
				if ui.tags("weak") { glyph(app, lucide.FOLDER_SEARCH, em * 1.8) }
				input_key := ui.key_from_string(ui.parent_box().key, "###goto_input")
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.3))})
				res: ui.Edit_Result
				if ui.tags("bare") { res = ui.line_edit("###goto_input", &g.field, {placeholder = i18n.tr("Go to: a path, or a few letters of a file or folder below"), clearable = true}) }
				if res.changed { g.sel, g.scroll, g.moved = 0, 0, false }
				if res.cancelled { ui.view_end(v, ui.VIEW_CANCELLED) }
				if res.committed {
					// (the path as typed when it is whole, else the row chosen, else the path typed as it is: from the
					// current folder when it is not absolute)
					switch {
					case typed_is_whole(app, text) && !g.moved: go_to = expand_home(app, text)
					case n > 0:                                 go_to = rows[g.sel].path
					case fs.looks_like_path(text):              go_to = expand_home(app, text)
					case root != "" && text != "":              go_to = fs.join(root, text, context.temp_allocator)
					}
				}
				// (in its first build, unseen: a dialog measured before it shows keeps the focus its builds gave, and the
				// letters typed meanwhile come into the field)
				if g.focus_due { ui.set_focus(input_key); g.focus_due = false }
				ui.space(ui.SPACE_3)
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
						ui.space(ui.SPACE_3)
						path_icon(app, r.path, r.folder, em * 1.7)
						ui.space(ui.ICON_GAP)
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.matched_label("###label", ui.text_shown(r.label), r.ranges)
						if ui.tags("weak") {
							ui.next({width = ui.text_size(em * 0.5), height = ui.pct(1), font_size = math.round(em * 0.85)})
							ui.label(fmt.tprintf("%s###kind", r.kind))
						}
						ui.space(ui.SPACE_3)
					}
					if selected { ui.pop_tags() }
					if sig.clicked { go_to = r.path }
					if sig.hovering && moved { g.sel, g.moved = at, true }
				}
			}
			if n == 0 && text != "" {
				if ui.tags("weak") {
					ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.5)), text_align = .Center})
					ui.label(fmt.tprintf("%s###goto_none", goto_none_text(text, found)))
				}
			}
			ui.hline(ui.px(pw))
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.1))})
			if ui.row(.Center, id = "###goto_foot") {
				ui.space(ui.SPACE_4)
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.85)})
					ui.label(fmt.tprintf("%s###goto_help", i18n.tr("Up, Down: choose   Tab: complete the path   Enter: go   Esc: close")))
					if found.reading {
						ui.next({width = ui.text_size(em * 0.5), height = ui.pct(1), font_size = math.round(em * 0.85)})
						ui.label(fmt.tprintf("%s###goto_reading", goto_reading_text(found.read)))
					}
				}
				ui.space(ui.SPACE_4)
			}
		}
	}
	if go_to != "" {
		path := strings.clone(go_to, context.temp_allocator)
		if goto_path(app, path) { ui.view_end(v, 0) }
	}
}
