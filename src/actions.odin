package classeur

// What the commands do (commands.odin). Each works on the current tab: the active tab of the focused panel.

import "core:fmt"
import "core:strings"
import "core:sync"
import "gt:desktop"
import "gt:platform"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

////////////////////////////////
// Opening

// Opens the cursor's entry or the selection: a folder in place (several: each in a tab), a file with the system's
// application.
act_open :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	targets := folder_targets(&t.folder)
	folders := 0
	for e in targets { if opens_as_folder(t, e^) { folders += 1 } }
	for e in targets {
		path := entry_path(t, e)
		switch {
		case !opens_as_folder(t, e^):
			open_system(app, path, t.in_archive)
		case folders == 1 && !t.locked:
			tab_go(app, t, path)
			return
		case:
			tab_open(app, current_panel(app), path, current_panel(app).active + 1)
		}
	}
}

// Whether `e`, of the tab's folder or of a folder in it, opens as a folder. An archive does, File Pilot's: "Open with the
// system's application" gives it to its program. An archive in an archive is taken out and opened: it is not entered.
// (Whether the folder is in an archive is the read's answer: no stat on this thread.)
opens_as_folder :: proc(t: ^Tab, e: fs.Entry) -> bool {
	return e.kind == .Directory || !t.in_archive && e.kind == .File && fs.is_archive_name(e.name)
}

// Opens one entry of the folder `dir` (the tab's or a folder in it): a folder in the tab `t` (in a new tab when `t` is
// locked), a file with the system's application.
open_entry :: proc(app: ^App, t: ^Tab, dir: string, e: fs.Entry) {
	path := fs.join(dir, e.name, context.temp_allocator)
	switch {
	case !opens_as_folder(t, e): open_system(app, path, t.in_archive)
	case t.locked:               tab_open(app, current_panel(app), path, current_panel(app).active + 1)
	case:                        tab_go(app, t, path)
	}
}

act_open_new_tab :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	p := current_panel(app)
	at := p.active
	for e in folder_targets(&t.folder) {
		if e.kind != .Directory { continue }
		at += 1
		tab_open(app, p, fs.join(t.path, e.name, context.temp_allocator), at)
	}
	p.active = clamp(p.active, 0, len(p.tabs) - 1)
}

act_open_other_panel :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	e := folder_cursor_entry(&t.folder)
	if e == nil || e.kind != .Directory { return }
	open_other_panel_at(app, fs.join(t.path, e.name, context.temp_allocator))
}

// The folder `path` in the other panel (none: a new panel), which gets the keyboard.
open_other_panel_at :: proc(app: ^App, path: string) {
	if len(app.panels) < 2 {
		panel_open(app, path)
		return
	}
	other := app.panels[(app.focus + 1) % len(app.panels)]
	if o := panel_tab(other); o != nil { tab_go(app, o, path) }
	app.focus = (app.focus + 1) % len(app.panels)
}

act_open_system :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	for e in folder_targets(&t.folder) { open_system(app, entry_path(t, e), t.in_archive) }
}

// The system's application for the file, started on a worker (launch). `in_archive`: the file is in an archive (its tab's
// in_archive). Headless (the tests), nothing starts: the path is noted in `app.opened`.
open_system :: proc(app: ^App, path: string, in_archive: bool) {
	// (a file of an archive: taken out to a temporary folder on a worker, then opened from there)
	if in_archive {
		Take_Out :: struct { app: ^App, path: string, out: string }
		job := new(Take_Out)
		job^ = {app = app, path = strings.clone(path)}
		tasks.add(&app.pool, proc(data: rawptr) {
			job := (^Take_Out)(data)
			job.out = strings.clone(fs.archive_take_out(job.path))
			if !ui.post(&job.app.main.state, proc(data: rawptr, word: u64) {
				job := (^Take_Out)(data)
				defer { delete(job.path); delete(job.out); free(job) }
				if job.out == "" { say(job.app, "%s cannot be taken out of its archive.", fs.base(job.path)); return }
				open_system(job.app, job.out, false)
			}, job) { delete(job.path); delete(job.out); free(job) }
		}, job)
		return
	}
	launch(app, .Open, path)
}

// What a worker starts: the system's application for a file, a chosen one (Open with), a terminal in a folder.
Launch_Kind :: enum u8 { Open, Open_With, Terminal }

@(private = "file")
Launch :: struct {
	app:      ^App,
	kind:     Launch_Kind,
	path:     string,   // owned: the file, or the terminal's folder
	id:       string,   // owned: Open with's application
	name:     string,   // owned: its name, said when it cannot start
	headless: bool,     // nothing starts (the tests)
}

// Starts a program on a worker: the portal is asked, or a process spawned, and either may wait. A failure comes back
// and is said. Headless (the tests), nothing starts: it is noted in `app.opened` at once, the worker runs all the same.
launch :: proc(app: ^App, kind: Launch_Kind, path: string, id := "", name := "") {
	if app.headless {
		switch kind {
		case .Open:      append(&app.opened, strings.clone(path))
		case .Open_With: append(&app.opened, strings.concatenate({id, ":", path}))
		case .Terminal:  append(&app.opened, strings.concatenate({"terminal:", path}))
		}
	}
	l := new(Launch)
	l^ = {app = app, kind = kind, path = strings.clone(path), id = strings.clone(id), name = strings.clone(name), headless = app.headless}
	tasks.add(&app.pool, launch_run, l)
}

@(private = "file")
launch_run :: proc(data: rawptr) {
	l := (^Launch)(data)
	ok := true
	if !l.headless {
		switch l.kind {
		case .Open:      ok = platform.open_path(l.path)
		case .Open_With: ok = desktop.open_with(l.path, l.id)
		case .Terminal:  ok = desktop.open_terminal(l.path)
		}
	}
	sync.atomic_store(&l.app.launched_on, sync.current_thread_id())
	if ok || !ui.post(&l.app.main.state, launch_failed, l) { launch_free(l) }
}

// On the interface's thread: why nothing started.
@(private = "file")
launch_failed :: proc(data: rawptr, word: u64) {
	l := (^Launch)(data)
	defer launch_free(l)
	switch l.kind {
	case .Open:      say(l.app, "No application opens %s.", fs.base(l.path))
	case .Open_With: say(l.app, "%s cannot start.", l.name)
	case .Terminal:  say(l.app, "No terminal was found: set $TERMINAL.")
	}
	app_frames(l.app)
}

@(private = "file")
launch_free :: proc(l: ^Launch) {
	delete(l.path)
	delete(l.id)
	delete(l.name)
	free(l)
}

act_up :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_up(app, t) } }
act_back :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_back(app, t) } }
act_forward :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_forward(app, t) } }
act_home :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_go(app, t, app.home) } }
act_refresh :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_load(app, t) } }

act_goto :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	t.address_open = true
	ui.field_set(&t.address, t.path)
	ui.field_select_all(&t.address)
	t.focus_due = .Address
}

act_filter :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	t.filter_open = true
	ui.field_select_all(&t.filter)
	t.focus_due = .Filter
}

act_palette :: proc(app: ^App) { palette_open(app) }

act_shortcuts :: proc(app: ^App) { app.shortcuts_open = true }

////////////////////////////////
// Tabs and panels

act_tab_new :: proc(app: ^App) {
	p := current_panel(app)
	t := current_tab(app)
	tab_open(app, p, t != nil ? t.path : app.home, p.active + 1)
}

act_tab_close :: proc(app: ^App) {
	p := current_panel(app)
	tab_close(app, p, p.active)
}

// Closes the tabs of the current panel whose index `keep` refuses.
@(private = "file")
tabs_close_where :: proc(app: ^App, close: proc(i, active: int) -> bool) {
	p := current_panel(app)
	active := p.active
	for i := len(p.tabs) - 1; i >= 0; i -= 1 {
		if close(i, active) { tab_close(app, p, i) }
	}
}

act_tab_close_others :: proc(app: ^App) { tabs_close_where(app, proc(i, a: int) -> bool { return i != a }) }
act_tab_close_left :: proc(app: ^App) { tabs_close_where(app, proc(i, a: int) -> bool { return i < a }) }
act_tab_close_right :: proc(app: ^App) { tabs_close_where(app, proc(i, a: int) -> bool { return i > a }) }

act_tab_reopen :: proc(app: ^App) {
	if len(app.closed_tabs) == 0 { return }
	path := pop(&app.closed_tabs)
	defer delete(path)
	p := current_panel(app)
	tab_open(app, p, path, p.active + 1)
}

act_tab_next :: proc(app: ^App) {
	p := current_panel(app)
	if len(p.tabs) > 0 { p.active = (p.active + 1) % len(p.tabs) }
}

act_tab_previous :: proc(app: ^App) {
	p := current_panel(app)
	if len(p.tabs) > 0 { p.active = (p.active + len(p.tabs) - 1) % len(p.tabs) }
}

act_tab_duplicate :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	p := current_panel(app)
	tab_open(app, p, t.path, p.active + 1)
}

act_panel_split :: proc(app: ^App) {
	t := current_tab(app)
	panel_open(app, t != nil ? t.path : app.home)
}

act_panel_split_below :: proc(app: ^App) {
	t := current_tab(app)
	panel_open(app, t != nil ? t.path : app.home, below = true)
}

act_panel_close :: proc(app: ^App) {
	if len(app.panels) < 2 { return }
	panel_close(app, current_panel(app))
}

// What has the keyboard: the list of the panel that has it, or the sidebar, or the inspector beside that list.
Keys_At :: enum u8 { List, Sidebar, Inspector }

act_panel_next :: proc(app: ^App) { keys_step(app, 1) }
act_panel_previous :: proc(app: ^App) { keys_step(app, -1) }

// The keyboard `by` stops on: the sidebar (shown), each panel's list in order, the inspector (open), round.
@(private = "file")
keys_step :: proc(app: ^App, by: int) {
	first := app.sidebar ? 1 : 0
	n := first + len(app.panels) + (app.inspector.open ? 1 : 0)
	if n == 0 { return }
	at := first + app.focus
	switch app.keys_at {
	case .List:
	case .Sidebar:   at = 0
	case .Inspector: at = n - 1
	}
	to := ((at + by) % n + n) % n
	switch {
	case app.sidebar && to == 0:            keys_to(app, .Sidebar)
	case app.inspector.open && to == n - 1: keys_to(app, .Inspector)
	case:
		app.focus = to - first
		keys_to(app, .List)
	}
}

// The keyboard to `at`: the toolkit's focus on its box, so that the list's own keys leave its cursor alone.
keys_to :: proc(app: ^App, at: Keys_At) {
	app.keys_at = at
	switch at {
	case .List:
		if t := current_tab(app); t != nil { t.focus_due = .List }
	case .Sidebar:
		ui.set_focus(app.side_keys.box)
		app.side_keys.moved = true
	case .Inspector:
		ui.set_focus(app.inspector.box)
	}
}

// The sidebar or the inspector lost the toolkit's focus (a click elsewhere, its box gone, a dialog): the keyboard is the
// list's again; given back to it when nothing else took it.
keys_follow :: proc(app: ^App) {
	switch app.keys_at {
	case .List:      return
	case .Sidebar:   if app.sidebar && app.side_keys.box != 0 && ui.focus_key() == app.side_keys.box { return }
	case .Inspector: if app.inspector.open && app.inspector.box != 0 && ui.focus_key() == app.inspector.box { return }
	}
	app.keys_at = .List
	if ui.focus_key() == 0 { if t := current_tab(app); t != nil { t.focus_due = .List } }
}

////////////////////////////////
// Selection

act_select_all :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_select_all(&t.folder) } }
act_select_none :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_select_none(&t.folder) } }
act_select_invert :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_invert_selection(&t.folder) } }

////////////////////////////////
// Changing files

// A change to files for the edits' worker (app.edit_pool: one thread, the changes done in the order they were asked).
// The task posts its answer with ui.post; the procedure the answer runs calls answer_came.
edit_submit :: proc(app: ^App, run: proc(data: rawptr), data: rawptr) {
	app.answers_due += 1
	tasks.add(&app.edit_pool, run, data)
}

answer_came :: proc(app: ^App) {
	app.answers_due -= 1
	app_frames(app)
}

// The rename in place: a field over the name of the row being renamed.
Rename :: struct {
	active:    bool,
	tab:       u64,
	name:      string,          // owned: the entry renamed ("": the entry is not there yet, see `pending`)
	field:     ui.Text_Field,
	focus_due: bool,
	refused:   bool,            // the name typed was refused (said why): the field in the colour of an error until it changes
	waiting:   u64,             // the rename the worker does (rename_done): the field stays until its answer; 0: none
	asked:     u64,             // the renames asked so far (each one's number)
}

rename_free :: proc(r: ^Rename) {
	delete(r.name)
	ui.field_destroy(&r.field)
	r^ = {}
}

act_rename :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	// (the search of every folder below: its names are paths, renamed from their own folders only)
	if t.folder.flat {
		say(app, "Rename from the item's own folder: the search lists items of several folders.")
		return
	}
	// several items: batch rename (batch.odin)
	if t.folder.count > 1 {
		batch_open(app, t)
		return
	}
	e := folder_cursor_entry(&t.folder)
	if e == nil { return }
	rename_begin(app, t, e.name)
}

rename_begin :: proc(app: ^App, t: ^Tab, name: string) {
	r := &app.rename
	delete(r.name)
	r.active, r.tab, r.name, r.focus_due, r.refused, r.waiting = true, t.id, strings.clone(name), true, false, 0
	base := fs.base(name)
	ui.field_set(&r.field, base)
	// the name without its extension selected, as the systems' file managers do
	ext := fs.extension(base)
	r.field.mark = 0
	r.field.cursor = ext != "" ? len(base) - len(ext) - 1 : len(base)
}

rename_end :: proc(app: ^App) {
	app.rename.active, app.rename.waiting = false, 0
	if t := find_tab(app, app.rename.tab); t != nil { t.focus_due = .List }
}

// Renames the entry to what the field holds. `step`: then the row after it (1) or before it (-1) is renamed, Tab and
// Shift+Tab as in Explorer. A name refused leaves the field open, what was typed selected to type another. The rename
// itself is the edits' worker's: the field stays open until its answer (rename_done).
rename_commit :: proc(app: ^App, step := 0) {
	r := &app.rename
	if r.waiting != 0 { return }   // (the worker has the name typed: its answer decides)
	t := find_tab(app, r.tab)
	if t == nil { rename_end(app); return }
	f := &t.folder
	// (the row Tab goes to, known before the read: the new name may sort elsewhere)
	next := ""
	if step != 0 {
		for i, row in f.shown {
			if f.listing.entries[i].name != r.name { continue }
			if e := folder_row_entry(f, row + step); e != nil { next = strings.clone(e.name, context.temp_allocator) }
			break
		}
	}
	to := strings.trim_space(ui.field_string(&r.field))
	if to != fs.base(r.name) && to != "" {
		if strings.contains_any(to, fs.SEPARATOR_STRING) || to == "." || to == ".." {
			say(app, "A name cannot hold %s.", fs.SEPARATOR_STRING)
			ui.field_select_all(&r.field)
			r.refused, r.focus_due = true, true
			return
		}
		rename_ask(app, t, to, next)
		return
	}
	rename_next(app, t, next, renamed = false)
}

// After a rename: the next row (Tab, Shift+Tab) has the cursor (and keeps it when the read comes) and the field; none,
// the field closes.
@(private = "file")
rename_next :: proc(app: ^App, t: ^Tab, next: string, renamed: bool) {
	if next == "" { rename_end(app); return }
	f := &t.folder
	if renamed {
		delete(t.reveal_name)
		t.reveal_name = strings.clone(next)
	}
	if folder_cursor_to_name(f, next) {
		folder_pick(f, f.cursor)
		ui.list_select(&t.vl, f.cursor)
	}
	rename_begin(app, t, next)
}

// A rename on its way to the edits' worker and back.
@(private = "file")
Rename_Ask :: struct {
	app:       ^App,
	tab:       u64,
	serial:    u64,      // Rename.asked when it was asked
	name:      string,   // owned: the entry renamed (in the tree: its path from the tab's folder)
	to:        string,   // owned: the name typed
	next:      string,   // owned: the row Tab or Shift+Tab goes to after it ("": none)
	from_path: string,   // owned
	to_path:   string,   // owned
	listed:    bool,     // the folder lists an entry of the very name typed (then not a change of case alone)
	taken:     bool,     // the answer: a name already there
	err:       fs.Error, // the answer: why the rename failed
}

// The entry being renamed named `to`, by the edits' worker; rename_done says how it went.
@(private = "file")
rename_ask :: proc(app: ^App, t: ^Tab, to, next: string) {
	r := &app.rename
	r.asked += 1
	r.waiting = r.asked
	// (in the tree the entry's name is a path from the tab's folder: renamed in its own folder)
	from_path := fs.join(t.path, r.name, context.temp_allocator)
	a := new(Rename_Ask)
	a^ = {
		app = app, tab = t.id, serial = r.asked, name = strings.clone(r.name), to = strings.clone(to), next = strings.clone(next),
		from_path = strings.clone(from_path), to_path = fs.join(fs.parent(from_path), to),
		listed = folder_find_name(&t.folder, fs.join(fs.parent(r.name), to, context.temp_allocator)) >= 0,
	}
	app.steps_due += 1
	edit_submit(app, rename_run, a)
}

@(private = "file")
rename_ask_free :: proc(a: ^Rename_Ask) {
	delete(a.name)
	delete(a.to)
	delete(a.next)
	delete(a.from_path)
	delete(a.to_path)
	free(a)
}

// On the edits' worker: the rename, never over a name.
@(private = "file")
rename_run :: proc(data: rawptr) {
	a := (^Rename_Ask)(data)
	dir := fs.parent(a.from_path)
	// a change of case alone, on a system whose names ignore it (Windows): the name "there" is the entry itself. It is
	// when the folder has no entry of that very name and the two are alike.
	case_only := false
	if there, exists := fs.stat(a.to_path); exists {
		from, _ := fs.stat(a.from_path)
		case_only = strings.equal_fold(a.to, fs.base(a.name)) && !a.listed && there == from
		a.taken = !case_only
	}
	switch {
	case a.taken:   // (said on the interface's thread)
	case case_only:
		// (through a free name: renamed straight, a system may see the new name taken by the entry itself)
		aside := fs.join(dir, fs.free_name(dir, fmt.tprintf("%s.renaming", a.to), context.temp_allocator), context.temp_allocator)
		a.err = fs.rename(a.from_path, aside)
		if a.err == .None {
			a.err = fs.rename(aside, a.to_path)
			if a.err != .None { _ = fs.rename(aside, a.from_path) }   // (its name back)
		}
	case:
		a.err = fs.rename(a.from_path, a.to_path)
	}
	if !ui.post(&a.app.main.state, rename_done, a) { rename_ask_free(a) }
}

// On the interface's thread: the rename done (its step of the undo, the folder read again, the cursor on the new name,
// the next row in the field after Tab) or refused (said why; the field stays, what was typed selected).
@(private = "file")
rename_done :: proc(data: rawptr, word: u64) {
	a := (^Rename_Ask)(data)
	app := a.app
	defer rename_ask_free(a)
	answer_came(app)
	app.steps_due -= 1
	r := &app.rename
	// (the field still waits for this answer: not closed, nor given to another row meanwhile)
	waits := r.active && r.waiting == a.serial
	if waits { r.waiting = 0 }
	if a.taken || a.err != .None {
		if a.taken {
			say(app, "%s is already there.", a.to)
		} else {
			say(app, "%s cannot be renamed: %s.", fs.base(a.name), fs.ERROR_REASON[a.err])
		}
		if waits {
			ui.field_select_all(&r.field)
			r.refused, r.focus_due = true, true
		}
		return
	}
	// (a folder or a file just made and named: its step says where it is now)
	if n := len(app.undo); n > 0 && (app.undo[n - 1].kind == .New_Folder || app.undo[n - 1].kind == .New_File) && app.undo[n - 1].pairs[0][1] == a.from_path {
		delete(app.undo[n - 1].pairs[0][1])
		app.undo[n - 1].pairs[0][1] = strings.clone(a.to_path)
	} else {
		undo_push(app, .Rename, {{a.from_path, a.to_path}})
	}
	t := find_tab(app, a.tab)
	if t == nil {
		if waits { rename_end(app) }
		return
	}
	delete(t.reveal_name)
	t.reveal_name = strings.clone(a.to)
	tab_load(app, t)
	if waits { rename_next(app, t, a.next, renamed = true) }
}

// A new folder (or an empty file) made by the edits' worker under a free name, then named in place (made_done).
@(private = "file")
Make_Ask :: struct {
	app:    ^App,
	tab:    u64,
	dir:    string,   // owned: the folder it goes in
	folder: bool,     // a folder, else an empty file
	name:   string,   // owned: the answer: the name it was made with
	err:    fs.Error, // the answer: why it was not made
}

act_new_folder :: proc(app: ^App) { make_ask(app, folder = true) }

// An empty file, then named in place.
act_new_file :: proc(app: ^App) { make_ask(app, folder = false) }

@(private = "file")
make_ask :: proc(app: ^App, folder: bool) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	a := new(Make_Ask)
	a^ = {app = app, tab = t.id, dir = strings.clone(t.path), folder = folder}
	app.steps_due += 1
	edit_submit(app, make_run, a)
}

@(private = "file")
make_ask_free :: proc(a: ^Make_Ask) {
	delete(a.dir)
	delete(a.name)
	free(a)
}

// On the edits' worker: the first free name of "New folder", "New folder 2"... (or "New file.txt"...), made.
@(private = "file")
make_run :: proc(data: rawptr) {
	a := (^Make_Ask)(data)
	name := a.folder ? "New folder" : "New file.txt"
	for n := 2; fs.exists(fs.join(a.dir, name, context.temp_allocator)); n += 1 {
		name = a.folder ? fmt.tprintf("New folder %d", n) : fmt.tprintf("New file %d.txt", n)
	}
	path := fs.join(a.dir, name, context.temp_allocator)
	a.err = a.folder ? fs.make_folder(path) : fs.make_file(path)
	a.name = strings.clone(name)
	if !ui.post(&a.app.main.state, made_done, a) { make_ask_free(a) }
}

// On the interface's thread: its step of the undo; in its tab (still on its folder), the cursor on it and its name in
// the field once the read comes.
@(private = "file")
made_done :: proc(data: rawptr, word: u64) {
	a := (^Make_Ask)(data)
	app := a.app
	defer make_ask_free(a)
	answer_came(app)
	app.steps_due -= 1
	if a.err != .None {
		say(app, a.folder ? "The folder cannot be made here: %s." : "The file cannot be made here: %s.", fs.ERROR_REASON[a.err])
		return
	}
	path := fs.join(a.dir, a.name, context.temp_allocator)
	undo_push(app, a.folder ? Undo_Kind.New_Folder : Undo_Kind.New_File, {{"", path}})
	t := find_tab(app, a.tab)
	if t == nil || t.path != a.dir { return }
	delete(t.reveal_name)
	t.reveal_name = strings.clone(a.name)
	tab_load(app, t)
	rename_begin(app, t, a.name)
}

act_terminal :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	terminal_at(app, t.path)
}

// A terminal in the folder under the cursor (the folder shown when the cursor is on a file).
act_terminal_in :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	dir := t.path
	if e := folder_cursor_entry(&t.folder); e != nil && e.kind == .Directory { dir = fs.join(t.path, e.name, context.temp_allocator) }
	terminal_at(app, dir)
}

// The system's terminal in `dir`, started on a worker (launch). Headless (the tests), nothing starts: it is noted in
// `app.opened`.
terminal_at :: proc(app: ^App, dir: string) { launch(app, .Terminal, dir) }

act_copy_path :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	b := strings.builder_make(context.temp_allocator)
	targets := folder_targets(&t.folder)
	for e, i in targets {
		if i > 0 { strings.write_byte(&b, '\n') }
		strings.write_string(&b, fs.join(t.path, e.name, context.temp_allocator))
	}
	if len(targets) == 0 { strings.write_string(&b, t.path) }
	platform.set_clipboard(app.main.win, strings.to_string(b))
	announce(app, .Good, len(targets) > 1 ? "%d paths copied." : "The path is copied.", len(targets))
}

////////////////////////////////
// The view

act_toggle_hidden :: proc(app: ^App) {
	pref_set_bool(app, "files.show_hidden", !app.show_hidden)
	say(app, app.show_hidden ? "Hidden files are shown." : "Hidden files are hidden.")
}

act_toggle_sidebar :: proc(app: ^App) { app.sidebar = !app.sidebar }

@(private = "file")
sort_by :: proc(app: ^App, key: fs.Sort_Key) {
	if t := current_tab(app); t != nil {
		folder_sort_by(&t.folder, key)
		app.default_sort = t.folder.sort
	}
}

act_sort_name :: proc(app: ^App) { sort_by(app, .Name) }
act_sort_modified :: proc(app: ^App) { sort_by(app, .Modified) }
act_sort_size :: proc(app: ^App) { sort_by(app, .Size) }
act_sort_type :: proc(app: ^App) { sort_by(app, .Type) }

act_folders_mixed :: proc(app: ^App) { pref_set_bool(app, "files.folders_first", app.default_sort.mixed) }

////////////////////////////////
// Copy, move, trash

// The paths of the selection (or of the cursor's row).
@(private = "file")
target_paths :: proc(t: ^Tab, allocator := context.temp_allocator) -> []string {
	targets := folder_targets(&t.folder)
	out := make([]string, len(targets), allocator)
	for e, i in targets { out[i] = entry_path(t, e, allocator) }
	return out
}

// The path of an entry of the tab's folder (a pointer into its listing): in the folder, or where the listing says it is
// (an item of the Recycle Bin of Windows, listed by its original name).
entry_path :: proc(t: ^Tab, e: ^fs.Entry, allocator := context.temp_allocator) -> string {
	if x, ok := fs.entry_trashed(&t.folder.listing, e); ok { return strings.clone(x.item, allocator) }
	return fs.join(t.path, e.name, allocator)
}

@(private = "file")
clipboard_put :: proc(app: ^App, cut: bool) {
	t := current_tab(app)
	if t == nil { return }
	paths := target_paths(t)
	if len(paths) == 0 { return }
	platform.clipboard_set(app.main.win, {files = paths, files_cut = cut, text = strings.join(paths, "\n", context.temp_allocator)})
	// (what is cut is drawn dimmed until it is pasted: what was cut before is not any more)
	cut_forget(app)
	if cut { for p in paths { if p not_in app.cut { app.cut[strings.clone(p)] = true } } }
	announce(app, .Good, "%d item%s %s.", len(paths), len(paths) == 1 ? "" : "s", cut ? "cut: paste them to move them" : "copied")
}

// The paths cut forgotten: none is drawn dimmed.
cut_forget :: proc(app: ^App) {
	for p in app.cut { delete(p) }
	clear(&app.cut)
}

// Whether `path` was cut and waits for its paste (its row, card or line is drawn dimmed).
row_is_cut :: proc(app: ^App, path: string) -> bool { return path in app.cut }

// row_is_cut for an entry of the tab (no path made while nothing is cut).
entry_is_cut :: proc(app: ^App, t: ^Tab, e: fs.Entry) -> bool {
	return len(app.cut) > 0 && row_is_cut(app, fs.join(t.path, e.name, context.temp_allocator))
}

act_copy :: proc(app: ^App) { clipboard_put(app, false) }
act_cut :: proc(app: ^App) { clipboard_put(app, true) }

// What the clipboard holds goes into the current folder: a copy, or a move after a cut. Copied into the folder it
// comes from, a file keeps both ("name 2.ext").
act_paste :: proc(app: ^App) {
	if t := current_tab(app); t != nil { paste_to(app, t, t.path) }
}

// The same into the folder at the cursor (a folder row's menu), not the one shown.
act_paste_into :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	e := folder_cursor_entry(&t.folder)
	if e == nil || e.kind != .Directory { return }
	paste_to(app, t, fs.join(t.path, e.name, context.temp_allocator))
}

// A paste whose files are asked of the clipboard (paste_to): where they go when they come.
Paste_Asked :: struct {
	id:  u64,      // the request (platform.clipboard_request); 0: none
	dir: string,   // owned
}

// What the clipboard holds goes into `dir`, a folder of tab `t`. The files are asked for: the clipboard's owner may be
// another program, slow or hung, and the window does not wait for it. The job starts when they come (paste_answer).
@(private = "file")
paste_to :: proc(app: ^App, t: ^Tab, dir: string) {
	if read_only_here(app, t) { return }
	delete(app.paste.dir)   // (a paste asked again: the last one's answer is not waited for)
	app.paste = {id = platform.clipboard_request(app.main.win, .Files), dir = strings.clone(dir)}
}

// An answer of the clipboard (app_input): the files of a paste, or the batch rename's names.
clipboard_answer :: proc(app: ^App, r: platform.Clipboard_Reply) {
	if r.id != 0 && r.id == app.paste.id { paste_answer(app, r) } else { batch_names_answer(app, r) }
}

// The clipboard's files came for the paste asked: a copy, or a move after a cut.
@(private = "file")
paste_answer :: proc(app: ^App, r: platform.Clipboard_Reply) {
	dir := app.paste.dir
	defer delete(dir)
	app.paste = {}
	if !r.ok || len(r.files) == 0 {
		say(app, "The clipboard holds no files.")
		return
	}
	// (a cut, here or in another file manager, moves; once moved, the files are no longer where the clipboard says)
	job_add(app, r.cut ? .Move : .Copy, r.files, dir)
	if r.cut { platform.clipboard_set(app.main.win, {}) }
	cut_forget(app)
}

@(private = "file")
to_other_panel :: proc(app: ^App, kind: Job_Kind) {
	t := current_tab(app)
	if t == nil || len(app.panels) < 2 { say(app, "There is no other panel."); return }
	other := panel_tab(app.panels[(app.focus + 1) % len(app.panels)])
	if other == nil || other.path == t.path { return }
	job_add(app, kind, target_paths(t), other.path)
}

act_copy_to_other :: proc(app: ^App) { to_other_panel(app, .Copy) }
act_move_to_other :: proc(app: ^App) { to_other_panel(app, .Move) }

act_trash :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	// (an item of the trash goes nowhere else: deleted for good, after the question, as a file manager's trash does)
	if shows_trash(t) {
		act_delete(app)
		return
	}
	paths := target_paths(t)
	if len(paths) == 0 { return }
	job_add(app, .Trash, paths)
}

// Deleting for good asks first (dialogs.odin).
act_delete :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	paths := target_paths(t)
	if len(paths) == 0 { return }
	// (named as the rows are: an item of the Recycle Bin by its original name, not its $R file's)
	targets := folder_targets(&t.folder)
	names := make([]string, len(targets), context.temp_allocator)
	for e, i in targets { names[i] = e.name }
	confirm_delete(app, paths, names = names, records = shows_trash(t))
}

// Whether the tab shows the trash itself (not a folder in it, nor its search): its items can be put back.
shows_trash :: proc(t: ^Tab) -> bool {
	dir := fs.trash_files_dir()
	return dir != "" && t.path == dir && !t.folder.flat
}

// The items of the trash selected go back where they were (each one's record says where), on the jobs' thread.
act_put_back :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if !shows_trash(t) { say(app, "Put back works in the trash (trash:///)."); return }
	paths := target_paths(t)
	if len(paths) == 0 { return }
	job_add(app, .Restore, paths)
}

// Every item of the trash deleted for good, after the question (dialogs.odin). Its items are the ones the tab read.
act_empty_trash :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if !shows_trash(t) { say(app, "Open the trash (trash:///) to empty it."); return }
	entries := t.folder.listing.entries
	if len(entries) == 0 { say(app, "The trash is empty."); return }
	paths := make([]string, len(entries), context.temp_allocator)
	names := make([]string, len(entries), context.temp_allocator)
	for i in 0 ..< len(entries) {
		paths[i] = entry_path(t, &t.folder.listing.entries[i])
		names[i] = entries[i].name
	}
	confirm_empty_trash(app, paths, names)
}

act_jobs_cancel :: proc(app: ^App) {
	for job in app.jobs.list { job_cancel(job) }
}

////////////////////////////////
// Bookmarks and the lock

bookmark_toggle :: proc(app: ^App, path: string) {
	for p, i in app.bookmarks {
		if p == path {
			delete(p)
			ordered_remove(&app.bookmarks, i)
			announce(app, .Good, "Bookmark removed.")
			return
		}
	}
	append(&app.bookmarks, strings.clone(path))
	announce(app, .Good, "%s is bookmarked.", fs.base(path))
}

act_bookmark :: proc(app: ^App) { if t := current_tab(app); t != nil { bookmark_toggle(app, t.path) } }

// The folder at the cursor bookmarked (or its bookmark removed); on a file, the folder shown.
act_bookmark_folder :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	path := t.path
	if e := folder_cursor_entry(&t.folder); e != nil && e.kind == .Directory { path = fs.join(t.path, e.name, context.temp_allocator) }
	bookmark_toggle(app, path)
}

bookmarked :: proc(app: ^App, path: string) -> bool {
	for p in app.bookmarks { if p == path { return true } }
	return false
}

act_recents_clear :: proc(app: ^App) {
	for p in app.recents { delete(p) }
	clear(&app.recents)
}

// `path` on the clipboard, as text (a place of the sidebar).
path_to_clipboard :: proc(app: ^App, path: string) {
	platform.set_clipboard(app.main.win, path)
	announce(app, .Good, "The path is copied.")
}
act_lock :: proc(app: ^App) { if t := current_tab(app); t != nil { t.locked = !t.locked } }

act_view_details :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, 0) } }
act_view_grid :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, ZOOM_GRID) } }
act_zoom_in :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, t.zoom + 1) } }
act_zoom_out :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, t.zoom - 1) } }

// The search of File Pilot: the folder flattened (every entry under it), filtered by the footer's field; again, back to
// the folder alone.
act_flat :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	t.flat = !t.flat
	tab_load(app, t)
	if t.flat { t.focus_due = .Filter }
}

act_view_list :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, 1) } }
act_view_columns :: proc(app: ^App) { if t := current_tab(app); t != nil { tab_set_zoom(app, t, 2) } }

act_types :: proc(app: ^App) { if t := current_tab(app); t != nil { types_menu_open(app, t) } }
act_files_only :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_set_kinds(&t.folder, .Files) } }
act_folders_only :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_set_kinds(&t.folder, .Folders) } }
act_every_type :: proc(app: ^App) {
	if t := current_tab(app); t != nil {
		folder_set_kinds(&t.folder, .All)
		folder_all_types(&t.folder, true)
	}
}

// The names of the selection (or of the cursor's row), one per line.
act_copy_name :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	b := strings.builder_make(context.temp_allocator)
	targets := folder_targets(&t.folder)
	for e, i in targets {
		if i > 0 { strings.write_byte(&b, '\n') }
		strings.write_string(&b, fs.base(e.name))
	}
	if len(targets) == 0 { return }
	platform.set_clipboard(app.main.win, strings.to_string(b))
	announce(app, .Good, len(targets) > 1 ? "%d names copied." : "The name is copied.", len(targets))
}

// In the search of every folder below: the folder of the item at the cursor, the item at the cursor there.
act_open_folder :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	e := folder_cursor_entry(&t.folder)
	if e == nil { return }
	full := fs.join(t.path, e.name, context.temp_allocator)
	tab_go(app, t, fs.parent(full))
	delete(t.reveal_name)
	t.reveal_name = strings.clone(fs.base(full))
}

// The network searched again for its devices; the sidebar's Network section opens to show them.
act_network_find :: proc(app: ^App) {
	app.side_open[.Network] = true
	app.devices_seen_open = true   // (the section opened here: no second search at its build)
	network_find(app)
}

// The tab `i` of the current panel (-1: the last).
tab_pick :: proc(app: ^App, i: int) {
	p := current_panel(app)
	if p == nil || len(p.tabs) == 0 { return }
	at := i < 0 ? len(p.tabs) - 1 : i
	if at < len(p.tabs) { p.active = at }
}

// In an archive (a folder of one, or its top): what writes is refused at once, said (the read's answer: no stat on this
// thread).
read_only_here :: proc(app: ^App, t: ^Tab) -> bool {
	if !t.in_archive { return false }
	say(app, "%s", fs.ERROR_TEXT[.Read_Only])
	return true
}
