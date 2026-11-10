package classeur

// The menu of the list: a right click on a row (or the Menu key, Shift+F10) gives what can be done with the selection;
// a right click on the empty part of the list gives what can be done in the folder. Every item is a command: its keys
// are shown beside it.

import "core:fmt"
import "core:strings"
import "core:time"
import "gt:desktop"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

MENU_WIDTH_EM :: 17

Entry_Menu :: struct {
	key:      ui.Key,
	tab:      u64,
	on_entry: bool,   // opened on a row (else on the folder)
	with_path: string,             // owned: the file "Open with" was asked for
	handlers:  []desktop.Handler,  // its applications, read on a worker
	handlers_ready: bool,          // they came
}

entry_menu_free :: proc(m: ^Entry_Menu) {
	delete(m.with_path)
	desktop.handlers_destroy(m.handlers)
	m^ = {}
}

@(private = "file")
Handlers_Read :: struct {
	app:      ^App,
	path:     string,
	handlers: []desktop.Handler,
}

// The applications of the file at the cursor, asked on a worker (the system's associations are read from files).
@(private = "file")
handlers_ask :: proc(app: ^App, path: string) {
	m := &app.menu
	delete(m.with_path)
	m.with_path = strings.clone(path)
	desktop.handlers_destroy(m.handlers)
	m.handlers, m.handlers_ready = nil, false
	job := new(Handlers_Read)
	job^ = {app = app, path = strings.clone(path)}
	pool_submit(&app.pool, proc(data: rawptr) {
		job := (^Handlers_Read)(data)
		job.handlers = desktop.handlers_for_file(job.path)
		if !ui.post(&job.app.main.state, proc(data: rawptr, word: u64) {
			job := (^Handlers_Read)(data)
			m := &job.app.menu
			if m.with_path == job.path && !m.handlers_ready {
				m.handlers, m.handlers_ready = job.handlers, true
				app_frames(job.app)
			} else {
				desktop.handlers_destroy(job.handlers)
			}
			delete(job.path)
			free(job)
		}, job) {
			desktop.handlers_destroy(job.handlers)
			delete(job.path)
			free(job)
		}
	}, job)
}

entry_menu_open :: proc(app: ^App, t: ^Tab, pos: ui.Vec2, from_keyboard := false, on_entry := true) {
	m := &app.menu
	if m.key == 0 { m.key = ui.key_from_string(0, "classeur_entry_menu") }
	m.tab, m.on_entry = t.id, on_entry
	if on_entry {
		if e := folder_cursor_entry(&t.folder); e != nil && e.kind != .Directory { handlers_ask(app, fs.join(t.path, e.name, context.temp_allocator)) }
	}
	ui.ctx_menu_open(m.key, pos, from_keyboard = from_keyboard, search = true)
}

// An item that runs a command, with its first key.
menu_command :: proc(app: ^App, id: string, enabled := true, checked := false) {
	c := command_find(id)
	if c == nil { return }
	if ui.menu_item(c.title, shortcut_text(c.keys[0]), checked = checked, icon = c.icon, enabled = enabled).clicked { c.run(app) }
}

entry_menu_build :: proc(app: ^App, em: f32) {
	m := &app.menu
	if m.key == 0 { return }
	// (as wide as its longest line: no title cut)
	if ui.ctx_menu(m.key) { entry_menu_items(app, m) }
}

@(private = "file")
entry_menu_items :: proc(app: ^App, m: ^Entry_Menu) {
	t := find_tab(app, m.tab)
	if t == nil { ui.ctx_menu_close(); return }
	if m.on_entry {
		e := folder_cursor_entry(&t.folder)
		folder := e != nil && e.kind == .Directory
		menu_command(app, "open")
		menu_command(app, "open_new_tab", enabled = folder)
		menu_command(app, "open_other_panel", enabled = folder)
		menu_command(app, "open_system")
		if e != nil && !folder { open_with_menu(app, fs.join(t.path, e.name, context.temp_allocator)) }
		if folder { menu_command(app, "terminal_in") }
		ui.menu_separator()
		menu_command(app, "cut")
		menu_command(app, "copy")
		menu_command(app, "copy_path")
		ui.menu_separator()
		menu_command(app, "trash")
		menu_command(app, "delete")
		menu_command(app, "rename", enabled = t.folder.count <= 1)
		ui.menu_separator()
	} else {
		menu_command(app, "paste")
		menu_command(app, "undo", enabled = len(app.undo) > 0)
		menu_command(app, "redo", enabled = len(app.redo) > 0)
		ui.menu_separator()
	}
	menu_command(app, "new_folder")
	menu_command(app, "new_file")
	menu_command(app, "terminal")
	menu_command(app, "select_all")
	menu_command(app, "refresh")
	ui.menu_separator()
	if ui.menu_submenu("Sort by", icon = lucide.ARROW_UP_DOWN) {
		s := t.folder.sort
		menu_command(app, "sort_name", checked = s.key == .Name)
		menu_command(app, "sort_modified", checked = s.key == .Modified)
		menu_command(app, "sort_size", checked = s.key == .Size)
		menu_command(app, "sort_type", checked = s.key == .Type)
		ui.menu_separator()
		menu_command(app, "folders_mixed", checked = !s.mixed)
	}
	menu_command(app, "hidden", checked = app.show_hidden)
}

////////////////////////////////
// The panel's menus: the history (the chevron of the toolbar) and the panel's own (its "...")

Panel_Menus :: struct {
	history_key: ui.Key,
	history_tab: u64,
	panel_key:   ui.Key,
	tab_key:     ui.Key,
	types_key:   ui.Key,
	types_tab:   u64,
	ranks_key:   ui.Key,     // a column's filter: its dates or its sizes (rank_menu_open)
	ranks_tab:   u64,
	ranks_by:    Group_By,
	rank_counts: [8]int,              // the menu's counts, and what they were counted for
	rank_counts_key: Rank_Counts_Key,
}

// The types' popup (the filter's funnel): files and folders, or one of them; each extension of the folder with its
// count, ticked when shown. It stays open while types are ticked.
types_menu_open :: proc(app: ^App, t: ^Tab) {
	m := &app.panel_menus
	if m.types_key == 0 { m.types_key = ui.key_from_string(0, "classeur_types_menu") }
	m.types_tab = t.id
	ui.ctx_menu_open(m.types_key, ui.mouse_pos())
}

@(private = "file")
types_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.types_key == 0 { return }
	if ui.ctx_menu(m.types_key, em * MENU_WIDTH_EM) {
		t := find_tab(app, m.types_tab)
		if t == nil { ui.ctx_menu_close(); return }
		f := &t.folder
		// (the columns' filters light this funnel too: they are cleared here as well)
		if f.dates_off != {} || f.sizes_off != {} {
			if ui.menu_item("Every date and size###kclear", keep_open = true).clicked { folder_all_ranks(f, .Date); folder_all_ranks(f, .Size) }
			ui.menu_separator()
		}
		if ui.menu_item("Files and folders###k0", checked = f.kinds == .All, keep_open = true).clicked { folder_set_kinds(f, .All) }
		if ui.menu_item("Files only###k1", checked = f.kinds == .Files, keep_open = true).clicked { folder_set_kinds(f, .Files) }
		if ui.menu_item("Folders only###k2", checked = f.kinds == .Folders, keep_open = true).clicked { folder_set_kinds(f, .Folders) }
		ui.menu_separator()
		types := folder_types(f)
		all := len(f.types_off) == 0
		if ui.menu_item("Every type###tall", checked = all, keep_open = true).clicked { folder_all_types(f, !all) }
		for ty, i in types {
			label := ty.ext == "" ? "No extension" : strings.to_upper(ty.ext, context.temp_allocator)
			on := ty.ext not_in f.types_off
			if ui.menu_item(fmt.tprintf("%s###ty%d", label, i), fmt.tprintf("%d", ty.count), checked = on, keep_open = true).clicked {
				folder_toggle_type(f, ty.ext)
			}
		}
	}
}

// The Modified column's filter (its dates: today, this week... as the date groups) or the Size column's (folders, tiny,
// small... as the size groups): each group with its count, ticked when shown. It stays open while groups are ticked.
Rank_Counts_Key :: struct { tab: u64, by: Group_By, entries: rawptr, n: int, hidden: bool, now: i64 }

rank_menu_open :: proc(app: ^App, t: ^Tab, by: Group_By, at: ui.Vec2) {
	m := &app.panel_menus
	// (its "now": the filter's day, the menu's counts and the rows agree; a new day when it opens again)
	t.folder.filter_now, t.folder.group_tz = time.now()._nsec, app.tz
	if m.ranks_key == 0 { m.ranks_key = ui.key_from_string(0, "classeur_ranks_menu") }
	m.ranks_tab, m.ranks_by = t.id, by
	ui.ctx_menu_open(m.ranks_key, at)
}

@(private = "file", rodata)
RANK_TITLES := [Group_By][8]string{
	.None = {},
	.Type = {},
	.Date = {"Today", "Yesterday", "This week", "This month", "This year", "Older", "", "No date"},
	.Size = {"Folders", "Tiny (under 16 KB)", "Small (under 1 MB)", "Medium (under 128 MB)", "Large (under 1 GB)", "Huge (1 GB and more)", "", ""},
}

@(private = "file")
rank_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.ranks_key == 0 { return }
	if ui.ctx_menu(m.ranks_key) {
		t := find_tab(app, m.ranks_tab)
		if t == nil { ui.ctx_menu_close(); return }
		f := &t.folder
		by := m.ranks_by
		off := by == .Date ? f.dates_off : f.sizes_off
		// (the filter's "now", so that the counts and the rows agree; set when the menu opened)
		now := f.filter_now
		// the count of each group among the entries shown (not hidden), counted once per listing and "now": not at
		// each frame the menu is open (a folder of 100 000 entries)
		key := Rank_Counts_Key{t.id, by, raw_data(f.listing.entries), len(f.listing.entries), f.show_hidden, now}
		if m.rank_counts_key != key {
			m.rank_counts_key = key
			m.rank_counts = {}
			for e in f.listing.entries {
				if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { continue }
				r, _ := group_rank(f, e, by, now)
				m.rank_counts[r] += 1
			}
		}
		counts := m.rank_counts
		every := by == .Date ? "Every date###rall" : "Every size###rall"
		if ui.menu_item(every, checked = off == {}, keep_open = true).clicked { folder_all_ranks(f, by) }
		ui.menu_separator()
		for title, r in RANK_TITLES[by] {
			if title == "" || counts[r] == 0 && r not_in off { continue }
			if ui.menu_item(fmt.tprintf("%s###r%d", title, r), fmt.tprintf("%d", counts[r]), checked = r not_in off, keep_open = true).clicked {
				folder_toggle_rank(f, by, r, now, app.tz)
			}
		}
	}
}

// A tab's menu (a right click on it): what to do with it and the tabs beside it.
tab_menu_open :: proc(app: ^App) {
	m := &app.panel_menus
	if m.tab_key == 0 { m.tab_key = ui.key_from_string(0, "classeur_tab_menu") }
	ui.ctx_menu_open(m.tab_key, ui.mouse_pos())
}

@(private = "file")
tab_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.tab_key == 0 { return }
	if ui.ctx_menu(m.tab_key) {
		p := current_panel(app)
		t := current_tab(app)
		if t == nil { ui.ctx_menu_close(); return }
		menu_command(app, "tab_new")
		menu_command(app, "tab_duplicate")
		menu_command(app, "tab_window", enabled = !(len(app.panels) == 1 && len(app.panels[0].tabs) == 1))
		menu_command(app, "lock", checked = t.locked)
		menu_command(app, "bookmark")
		ui.menu_separator()
		menu_command(app, "tab_close")
		menu_command(app, "tab_close_others", enabled = len(p.tabs) > 1)
		menu_command(app, "tab_close_left", enabled = p.active > 0)
		menu_command(app, "tab_close_right", enabled = p.active < len(p.tabs) - 1)
		menu_command(app, "tab_reopen", enabled = len(app.closed_tabs) > 0)
		ui.menu_separator()
		menu_command(app, "terminal")
		menu_command(app, "copy_path")
	}
}

history_menu_open :: proc(app: ^App, t: ^Tab, at: ui.Rect) {
	m := &app.panel_menus
	if m.history_key == 0 { m.history_key = ui.key_from_string(0, "classeur_history_menu") }
	m.history_tab = t.id
	ui.ctx_menu_open(m.history_key, ui.mouse_pos())
}

panel_menu_open :: proc(app: ^App, pos: ui.Vec2) {
	m := &app.panel_menus
	if m.panel_key == 0 { m.panel_key = ui.key_from_string(0, "classeur_panel_menu") }
	ui.ctx_menu_open(m.panel_key, pos)
}

panel_menus_build :: proc(app: ^App, em: f32) {
	history_menu_build(app, em)
	panel_menu_build(app, em)
	tab_menu_build(app, em)
	types_menu_build(app, em)
	rank_menu_build(app, em)
}

@(private = "file")
history_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.history_key == 0 { return }
	if ui.ctx_menu(m.history_key, em * MENU_WIDTH_EM) {
		t := find_tab(app, m.history_tab)
		if t == nil { ui.ctx_menu_close(); return }
		// the last folder first
		#reverse for p, i in t.back {
			if ui.menu_item(fmt.tprintf("%s###h%d", shown_text(home_path(app, p)), i)).clicked {
				for len(t.back) > i + 1 { tab_back_quiet(t) }
				tab_back(app, t)
			}
		}
	}
}

@(private = "file")
panel_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.panel_key == 0 { return }
	if ui.ctx_menu(m.panel_key) {
		t := current_tab(app)
		if t == nil { ui.ctx_menu_close(); return }
		// (where every command is, and the settings, first: the menu that the "…" opens is where one looks for them)
		menu_command(app, "palette")
		menu_command(app, "options")
		ui.menu_separator()
		menu_command(app, "new_folder")
		menu_command(app, "new_file")
		menu_command(app, "refresh")
		menu_command(app, "goto_popup")
		menu_command(app, "terminal")
		ui.menu_separator()
		if ui.menu_submenu("Sort by", icon = lucide.ARROW_UP_DOWN) {
			s := t.folder.sort
			menu_command(app, "sort_name", checked = s.key == .Name)
			menu_command(app, "sort_modified", checked = s.key == .Modified)
			menu_command(app, "sort_size", checked = s.key == .Size)
			menu_command(app, "sort_type", checked = s.key == .Type)
			ui.menu_separator()
			menu_command(app, "folders_mixed", checked = !s.mixed)
		}
		if ui.menu_submenu("Group by", icon = lucide.ROWS_2) {
			g := t.group
			menu_command(app, "group_date", checked = g == .Date)
			menu_command(app, "group_type", checked = g == .Type)
			menu_command(app, "group_size", checked = g == .Size)
		}
		menu_command(app, "hidden", checked = app.show_hidden)
		ui.menu_separator()
		menu_command(app, "panel_split")
		menu_command(app, "panel_split_below")
		menu_command(app, "panel_close", enabled = len(app.panels) > 1)
	}
}

// "Open with": the applications the system knows for the file, its default first.
@(private = "file")
open_with_menu :: proc(app: ^App, path: string) {
	if ui.menu_submenu("Open with", icon = lucide.APP_WINDOW) {
		ready := app.menu.with_path == path && app.menu.handlers_ready
		hs := ready ? app.menu.handlers : nil
		if !ready { _ = ui.menu_item("Reading…", enabled = false) } else if len(hs) == 0 { _ = ui.menu_item("No application", enabled = false) }
		for h, i in hs {
			label := h.default ? fmt.tprintf("%s (default)###ow%d", shown_text(h.name), i) : fmt.tprintf("%s###ow%d", shown_text(h.name), i)
			if ui.menu_item(label).clicked {
				if app.headless {
					append(&app.opened, strings.concatenate({h.id, ":", path}))
				} else if !desktop.open_with(path, h.id) {
					say(app, "%s cannot start.", h.name)
				}
			}
		}
	}
}
