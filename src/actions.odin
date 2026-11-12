package classeur

// What the commands do (commands.odin). Each works on the current tab: the active tab of the focused panel.

import "core:fmt"
import "core:os"
import "core:strings"
import "gt:desktop"
import "gt:platform"
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
	// (an archive opens as a folder, File Pilot's: "Open with the system's application" gives it to its program)
	// (an archive in an archive is taken out and opened: it is not entered)
	in_archive := fs.archive_holds(fs.join(t.path, "x", context.temp_allocator))
	as_folder :: proc(e: ^fs.Entry, in_archive: bool) -> bool { return e.kind == .Directory || !in_archive && e.kind == .File && fs.is_archive_name(e.name) }
	folders := 0
	for e in targets { if as_folder(e, in_archive) { folders += 1 } }
	for e in targets {
		path := fs.join(t.path, e.name, context.temp_allocator)
		if as_folder(e, in_archive) {
			if folders == 1 && !t.locked {
				tab_go(app, t, path)
				return
			}
			tab_open(app, current_panel(app), path, current_panel(app).active + 1)
		} else {
			open_system(app, path)
		}
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
	path := fs.join(t.path, e.name, context.temp_allocator)
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
	for e in folder_targets(&t.folder) { open_system(app, fs.join(t.path, e.name, context.temp_allocator)) }
}

// The system's application for the file. Headless (the tests), nothing starts: the path is noted in `app.opened`.
open_system :: proc(app: ^App, path: string) {
	// (a file of an archive: taken out to a temporary folder on a worker, then opened from there)
	if fs.archive_holds(path) {
		Take_Out :: struct { app: ^App, path: string, out: string }
		job := new(Take_Out)
		job^ = {app = app, path = strings.clone(path)}
		pool_submit(&app.pool, proc(data: rawptr) {
			job := (^Take_Out)(data)
			job.out = strings.clone(fs.archive_take_out(job.path))
			if !ui.post(&job.app.main.state, proc(data: rawptr, word: u64) {
				job := (^Take_Out)(data)
				defer { delete(job.path); delete(job.out); free(job) }
				if job.out == "" { say(job.app, "%s cannot be taken out of its archive.", fs.base(job.path)); return }
				open_system(job.app, job.out)
			}, job) { delete(job.path); delete(job.out); free(job) }
		}, job)
		return
	}
	if app.headless {
		append(&app.opened, strings.clone(path))
		return
	}
	if !platform.open_path(path) { say(app, "No application opens %s.", fs.base(path)) }
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

act_panel_next :: proc(app: ^App) {
	if len(app.panels) > 0 { app.focus = (app.focus + 1) % len(app.panels) }
	if t := current_tab(app); t != nil { t.focus_due = .List }
}

////////////////////////////////
// Selection

act_select_all :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_select_all(&t.folder) } }
act_select_none :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_select_none(&t.folder) } }
act_select_invert :: proc(app: ^App) { if t := current_tab(app); t != nil { folder_invert_selection(&t.folder) } }

////////////////////////////////
// Changing files

// The rename in place: a field over the name of the row being renamed.
Rename :: struct {
	active:    bool,
	tab:       u64,
	name:      string,          // owned: the entry renamed ("": the entry is not there yet, see `pending`)
	field:     ui.Text_Field,
	focus_due: bool,
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
	r.active, r.tab, r.name, r.focus_due = true, t.id, strings.clone(name), true
	base := fs.base(name)
	ui.field_set(&r.field, base)
	// the name without its extension selected, as the systems' file managers do
	ext := fs.extension(base)
	r.field.mark = 0
	r.field.cursor = ext != "" ? len(base) - len(ext) - 1 : len(base)
}

rename_end :: proc(app: ^App) {
	app.rename.active = false
	if t := find_tab(app, app.rename.tab); t != nil { t.focus_due = .List }
}

// Renames the entry to what the field holds.
rename_commit :: proc(app: ^App) {
	r := &app.rename
	t := find_tab(app, r.tab)
	defer rename_end(app)
	if t == nil { return }
	to := strings.trim_space(ui.field_string(&r.field))
	if to == r.name || to == "" { return }
	if strings.contains_any(to, fs.SEPARATOR_STRING) || to == "." || to == ".." {
		say(app, "A name cannot hold %s.", fs.SEPARATOR_STRING)
		return
	}
	// (in the tree the entry's name is a path from the tab's folder: renamed in its own folder)
	from_path := fs.join(t.path, r.name, context.temp_allocator)
	to_path := fs.join(fs.parent(from_path), to, context.temp_allocator)
	if _, exists := fs.stat(to_path); exists {
		say(app, "%s is already there.", to)
		return
	}
	if err := os.rename(from_path, to_path); err != nil {
		say(app, "%s cannot be renamed: %v.", r.name, err)
		return
	}
	// (a folder or a file just made and named: its step says where it is now)
	if n := len(app.undo); n > 0 && (app.undo[n - 1].kind == .New_Folder || app.undo[n - 1].kind == .New_File) && app.undo[n - 1].pairs[0][1] == from_path {
		delete(app.undo[n - 1].pairs[0][1])
		app.undo[n - 1].pairs[0][1] = strings.clone(to_path)
	} else {
		undo_push(app, .Rename, {{from_path, to_path}})
	}
	delete(t.reveal_name)
	t.reveal_name = strings.clone(to)
	tab_load(app, t)
}

act_new_folder :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	name := "New folder"
	for n := 2; ; n += 1 {
		if _, exists := fs.stat(fs.join(t.path, name, context.temp_allocator)); !exists { break }
		name = fmt.tprintf("New folder %d", n)
	}
	if err := os.make_directory(fs.join(t.path, name, context.temp_allocator)); err != nil {
		say(app, "The folder cannot be made here: %v.", err)
		return
	}
	undo_push(app, .New_Folder, {{"", fs.join(t.path, name, context.temp_allocator)}})
	delete(t.reveal_name)
	t.reveal_name = strings.clone(name)
	tab_load(app, t)
	rename_begin(app, t, name)
}

// An empty file, then named in place.
act_new_file :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	name := "New file.txt"
	for n := 2; ; n += 1 {
		if !fs.exists(fs.join(t.path, name, context.temp_allocator)) { break }
		name = fmt.tprintf("New file %d.txt", n)
	}
	path := fs.join(t.path, name, context.temp_allocator)
	if e := fs.make_file(path); e != .None {
		say(app, "The file cannot be made here: %s.", fs.ERROR_REASON[e])
		return
	}
	undo_push(app, .New_File, {{"", path}})
	delete(t.reveal_name)
	t.reveal_name = strings.clone(name)
	tab_load(app, t)
	rename_begin(app, t, name)
}

act_terminal :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if app.headless { append(&app.opened, strings.concatenate({"terminal:", t.path})); return }
	if !desktop.open_terminal(t.path) { say(app, "No terminal was found: set $TERMINAL.") }
}

// A terminal in the folder under the cursor (the folder shown when the cursor is on a file).
act_terminal_in :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	dir := t.path
	if e := folder_cursor_entry(&t.folder); e != nil && e.kind == .Directory { dir = fs.join(t.path, e.name, context.temp_allocator) }
	if app.headless { append(&app.opened, strings.concatenate({"terminal:", dir})); return }
	if !desktop.open_terminal(dir) { say(app, "No terminal was found: set $TERMINAL.") }
}

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
	say(app, len(targets) > 1 ? "%d paths copied." : "The path is copied.", len(targets))
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
	for e, i in targets { out[i] = fs.join(t.path, e.name, allocator) }
	return out
}

@(private = "file")
clipboard_put :: proc(app: ^App, cut: bool) {
	t := current_tab(app)
	if t == nil { return }
	paths := target_paths(t)
	if len(paths) == 0 { return }
	platform.clipboard_set(app.main.win, {files = paths, files_cut = cut, text = strings.join(paths, "\n", context.temp_allocator)})
	say(app, "%d item%s %s.", len(paths), len(paths) == 1 ? "" : "s", cut ? "cut: paste them to move them" : "copied")
}

act_copy :: proc(app: ^App) { clipboard_put(app, false) }
act_cut :: proc(app: ^App) { clipboard_put(app, true) }

// What the clipboard holds goes into the current folder: a copy, or a move after a cut. Copied into the folder it
// comes from, a file keeps both ("name 2.ext").
act_paste :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	if read_only_here(app, t) { return }
	paths, ok := platform.clipboard_get_files(app.main.win, context.temp_allocator)
	if !ok || len(paths) == 0 {
		say(app, "The clipboard holds no files.")
		return
	}
	// (a cut, here or in another file manager, moves; once moved, the files are no longer where the clipboard says)
	cut := platform.clipboard_files_cut(app.main.win)
	job_add(app, cut ? .Move : .Copy, paths, t.path)
	if cut { platform.clipboard_set(app.main.win, {}) }
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
	confirm_delete(app, paths)
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
			say(app, "Bookmark removed.")
			return
		}
	}
	append(&app.bookmarks, strings.clone(path))
	say(app, "%s is bookmarked.", fs.base(path))
}

act_bookmark :: proc(app: ^App) { if t := current_tab(app); t != nil { bookmark_toggle(app, t.path) } }
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
	say(app, len(targets) > 1 ? "%d names copied." : "The name is copied.", len(targets))
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

// The tab `i` of the current panel (-1: the last).
tab_pick :: proc(app: ^App, i: int) {
	p := current_panel(app)
	if p == nil || len(p.tabs) == 0 { return }
	at := i < 0 ? len(p.tabs) - 1 : i
	if at < len(p.tabs) { p.active = at }
}

// In an archive (a folder of one, or its top): what writes is refused at once, said (no stat of its entries on this thread).
read_only_here :: proc(app: ^App, t: ^Tab) -> bool {
	if !fs.archive_holds(fs.join(t.path, "x", context.temp_allocator)) { return false }
	say(app, "%s", fs.ERROR_TEXT[.Read_Only])
	return true
}
