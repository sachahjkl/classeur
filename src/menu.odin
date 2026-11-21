package classeur

// The menu of the list: a right click on a row (or the Menu key, Shift+F10) gives what can be done with the selection;
// a right click on the empty part of the list gives what can be done in the folder. Every item is a command: its keys
// are shown beside it.

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "gt:desktop"
import "gt:i18n"
import lucide "gt:lucide"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

MENU_WIDTH_EM :: 17

// Standard Windows shell verbs already provided by classeur's own menu items.
@(private = "file")
SHELL_EXCLUDE_VERBS := [?]string{
	"open", "openas", "opennew", "explore", "cut", "copy", "paste", "link", "delete", "rename", "properties",
}

// The ids of the menus (the window's: each is open at most once)
ENTRY_MENU   :: "classeur_entry_menu"
HISTORY_MENU :: "classeur_history_menu"
PANEL_MENU   :: "classeur_panel_menu"
TAB_MENU     :: "classeur_tab_menu"
TABS_MENU    :: "classeur_tabs_menu"     // every tab of a panel (the chevron of a row too short for them)
TYPES_MENU   :: "classeur_types_menu"
RANKS_MENU   :: "classeur_ranks_menu"    // a column's filter: its dates or its sizes (rank_menu_open)
LAYOUTS_MENU :: "classeur_layouts_menu"
SIDE_MENU    :: "classeur_side_menu"     // a heading's menu: Move up, Move down...
SIDE_ROW_MENU    :: "classeur_side_row_menu"     // a row's menu: Open, Copy the path... (sidebar.odin)
SIDE_DEVICE_MENU :: "classeur_side_device_menu"  // a device's menu: each of its services (sidebar.odin)
COLUMNS_MENU     :: "classeur_columns_menu"
ZOOM_SLIDER_MENU :: "classeur_zoom_slider"       // the zoom's slider over the footer (view_panel.odin)

Entry_Menu :: struct {
	tab:            u64,
	on_entry:       bool,                   // opened on a row (else on the folder)
	was_open:       bool,                   // tracks close edge to release the held native shell session
	with_path:      string,                 // owned: the file "Open with" was asked for
	handlers:       []desktop.Handler,      // its applications, read on a worker
	handlers_ready: bool,                   // they came
	shell:          desktop.Context_Menu,   // asynchronous system shell context-menu worker (Windows STA / Linux extensions)
	shell_serial:   u64,                    // serial of the latest shell query (stale answers are dropped)
	shell_items:    []desktop.Context_Item, // owned (heap): system shell items once ready
	shell_ready:    bool,
	shell_invoked:  u32,                    // tests: last system shell item id clicked (0: none)
}

entry_menu_free :: proc(m: ^Entry_Menu) {
	desktop.context_menu_destroy(&m.shell)
	desktop.context_items_destroy(m.shell_items, runtime.heap_allocator())
	delete(m.with_path)
	desktop.handlers_destroy(m.handlers)
	m^ = {}
}

@(private = "file")
Shell_Ready :: struct {
	app:    ^App,
	serial: u64,
	items:  []desktop.Context_Item,
}

// Worker callback from desktop.Context_Menu: posts the plain items tree back to the interface thread.
@(private = "file")
shell_menu_on_ready :: proc(user: rawptr, serial: u64, items: []desktop.Context_Item) {
	app := (^App)(user)
	a := runtime.heap_allocator()
	msg := new(Shell_Ready, a)
	msg^ = {app = app, serial = serial, items = items}
	if !ui.post(&app.main.state, shell_menu_done, msg) {
		desktop.context_items_destroy(msg.items, a)
		free(msg, a)
	}
}

@(private = "file")
shell_menu_done :: proc(data: rawptr, word: u64) {
	a := runtime.heap_allocator()
	msg := (^Shell_Ready)(data)
	defer free(msg, a)
	shell_menu_apply(msg.app, msg.serial, msg.items)
}

// Applies a completed shell context-menu query if its serial is still current; otherwise frees `items`.
shell_menu_apply :: proc(app: ^App, serial: u64, items: []desktop.Context_Item) {
	a := runtime.heap_allocator()
	m := &app.menu
	if serial != m.shell_serial {
		desktop.context_items_destroy(items, a)
		return
	}
	desktop.context_items_destroy(m.shell_items, a)
	m.shell_items = items
	m.shell_ready = true
	app_frames(app)
}

@(private = "file")
shell_menu_ask :: proc(app: ^App, t: ^Tab, on_entry: bool) {
	m := &app.menu
	desktop.context_items_destroy(m.shell_items, runtime.heap_allocator())
	m.shell_items = nil
	m.shell_ready = false
	m.shell_serial = 0
	if app.headless || t.in_archive || shows_trash(t) { return }

	paths := make([dynamic]string, context.temp_allocator)
	if on_entry {
		for e in folder_targets(&t.folder) { append(&paths, entry_path(t, e)) }
	} else {
		append(&paths, t.path)
	}
	if len(paths) == 0 { return }
	excluded := SHELL_EXCLUDE_VERBS
	m.shell_serial = desktop.context_menu_query(&m.shell, {
		paths         = paths[:],
		background    = !on_entry,
		exclude_verbs = excluded[:],
	}, shell_menu_on_ready, app)
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
	tasks.add(&app.pool, proc(data: rawptr) {
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
	m.tab, m.on_entry = t.id, on_entry
	if on_entry {
		if e := folder_cursor_entry(&t.folder); e != nil && e.kind != .Directory { handlers_ask(app, entry_path(t, e)) }
	}
	shell_menu_ask(app, t, on_entry)
	ui.menu_open(ENTRY_MENU, pos, from_keyboard = from_keyboard)
}

// An item that runs a command, with its first key. `title`: what the item says in place of the command's title (what
// it acts on: "Rename 3 items…").
menu_command :: proc(app: ^App, id: string, enabled := true, checked := false, title := "") {
	c := command_find(id)
	if c == nil { return }
	text := title != "" ? fmt.tprintf("%s###%s", title, c.id) : i18n.tr(c.title)
	if ui.menu_item(text, command_keys(app, c), checked = checked, icon = c.icon, disabled = !enabled).clicked { c.run(app) }
}

entry_menu_build :: proc(app: ^App, em: f32) {
	m := &app.menu
	// (as wide as its longest line: no title cut)
	if ui.menu(ENTRY_MENU) {
		m.was_open = true
		entry_menu_items(app, m)
	} else if m.was_open {
		m.was_open = false
		desktop.context_menu_clear(&m.shell)
	}
}

@(private = "file")
entry_menu_items :: proc(app: ^App, m: ^Entry_Menu) {
	t := find_tab(app, m.tab)
	if t == nil { ui.menu_close(); return }
	trash := shows_trash(t)
	if m.on_entry {
		e := folder_cursor_entry(&t.folder)
		folder := e != nil && e.kind == .Directory
		full := e != nil ? entry_path(t, e) : t.path
		other := len(app.panels) > 1
		menu_command(app, "open")
		menu_command(app, "open_new_tab", enabled = folder)
		menu_command(app, "open_other_panel", enabled = folder)
		menu_command(app, "open_system")
		if e != nil && !folder { open_with_menu(app, full) }
		// (in a search the item's folder is not the one shown)
		menu_command(app, "open_folder", enabled = e != nil && fs.parent(full) != t.path, title = i18n.tr("Go to its folder"))
		if folder { menu_command(app, "terminal_in") }
		ui.menu_separator()
		menu_command(app, "cut")
		menu_command(app, "copy")
		menu_command(app, "paste_into", enabled = folder, title = i18n.tr("Paste into this folder"))
		menu_command(app, "copy_path")
		menu_command(app, "copy_name")
		menu_command(app, "copy_to_other", enabled = other)
		menu_command(app, "move_to_other", enabled = other)
		ui.menu_separator()
		if trash {
			menu_command(app, "put_back", title = i18n.tr("Put back"))
			menu_command(app, "empty_trash")
		} else {
			menu_command(app, "trash")
		}
		menu_command(app, "delete")
		// (several: the batch rename, as F2 opens it)
		n := len(t.folder.selected)
		menu_command(app, "rename", title = n > 1 ? fmt.tprintf(i18n.tr(n, "Rename %d item…", "Rename %d items…"), n) : "")
		ui.menu_separator()
		menu_command(app, "bookmark_folder", enabled = folder, title = folder && bookmarked(app, full) ? i18n.tr("Remove the bookmark") : i18n.tr("Bookmark this folder"))
		menu_command(app, "inspector", checked = inspector_shown(app))
		ui.menu_separator()
	} else {
		menu_command(app, "paste")
		menu_command(app, "undo", enabled = len(app.undo) > 0)
		menu_command(app, "redo", enabled = len(app.redo) > 0)
		if trash {
			menu_command(app, "put_back", enabled = len(t.folder.selected) > 0, title = i18n.tr("Put back"))
			menu_command(app, "empty_trash", enabled = len(t.folder.listing.entries) > 0)
		}
		ui.menu_separator()
	}
	menu_command(app, "new_folder")
	menu_command(app, "new_file")
	menu_command(app, "terminal")
	menu_command(app, "select_all")
	menu_command(app, "refresh")
	ui.menu_separator()
	if ui.menu_submenu(i18n.tr("Sort by"), icon = lucide.ARROW_UP_DOWN) {
		s := t.folder.sort
		menu_command(app, "sort_name", checked = s.key == .Name)
		menu_command(app, "sort_modified", checked = s.key == .Modified)
		menu_command(app, "sort_size", checked = s.key == .Size)
		menu_command(app, "sort_type", checked = s.key == .Type)
		ui.menu_separator()
		menu_command(app, "folders_mixed", checked = !s.mixed)
	}
	menu_command(app, "hidden", checked = app.show_hidden)
	// Asynchronous system shell actions (Windows shell extensions, Linux KIO/Nemo/Thunar actions) once ready.
	if m.shell_ready && len(m.shell_items) > 0 {
		ui.menu_separator()
		shell_menu_items(app, m.shell_items, "sh")
	}
	// (on an item, Properties last, as in every file manager)
	if m.on_entry {
		ui.menu_separator()
		menu_command(app, "properties", enabled = folder_cursor_entry(&t.folder) != nil)
	}
}

@(private = "file")
shell_menu_items :: proc(app: ^App, items: []desktop.Context_Item, prefix: string) {
	for it, i in items {
		if it.separator {
			ui.menu_separator()
			continue
		}
		if len(it.children) > 0 {
			sub_id := fmt.tprintf("%s_%d", prefix, i)
			if ui.menu_submenu(fmt.tprintf("%s###%s", ui.text_shown(it.label), sub_id)) {
				shell_menu_items(app, it.children, sub_id)
			}
			continue
		}
		label := fmt.tprintf("%s###%s_%d", ui.text_shown(it.label), prefix, i)
		if ui.menu_item(label, disabled = it.disabled).clicked {
			app.menu.shell_invoked = it.id
			if !app.headless { desktop.context_menu_invoke(&app.menu.shell, app.menu.shell_serial, it.id, app.main.win) }
		}
	}
}

////////////////////////////////
// The panel's menus: the history (the chevron of the toolbar) and the panel's own (its "...")

Panel_Menus :: struct {
	history_tab: u64,
	tabs_tab:    u64,        // a tab of that panel: the one shown when it opened
	types_tab:   u64,
	ranks_tab:   u64,
	ranks_by:    Group_By,
	rank_counts: [8]int,              // the menu's counts, and what they were counted for
	rank_counts_key: Rank_Counts_Key,
}

// The types' popup (the filter's funnel): files and folders, or one of them; each extension of the folder with its
// count, ticked when shown. It stays open while types are ticked.
types_menu_open :: proc(app: ^App, t: ^Tab) {
	m := &app.panel_menus
	m.types_tab = t.id
	t.folder.types_due = true   // (counted once as it opens, then kept while the rows stay the same)
	ui.menu_open(TYPES_MENU, ui.mouse_pos())
}

@(private = "file")
types_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if ui.menu(TYPES_MENU, em * MENU_WIDTH_EM) {
		t := find_tab(app, m.types_tab)
		if t == nil { ui.menu_close(); return }
		f := &t.folder
		// (the columns' filters light this funnel too: they are cleared here as well)
		if f.dates_off != {} || f.sizes_off != {} {
			if ui.menu_item(fmt.tprintf("%s###kclear", i18n.tr("Every date and size")), keep_open = true).clicked { folder_all_ranks(f, .Date); folder_all_ranks(f, .Size) }
			ui.menu_separator()
		}
		if ui.menu_item(fmt.tprintf("%s###k0", i18n.tr("Files and folders")), checked = f.kinds == .All, keep_open = true).clicked { folder_set_kinds(f, .All) }
		if ui.menu_item(fmt.tprintf("%s###k1", i18n.tr("Files only")), checked = f.kinds == .Files, keep_open = true).clicked { folder_set_kinds(f, .Files) }
		if ui.menu_item(fmt.tprintf("%s###k2", i18n.tr("Folders only")), checked = f.kinds == .Folders, keep_open = true).clicked { folder_set_kinds(f, .Folders) }
		ui.menu_separator()
		types := folder_types_kept(f)
		all := len(f.types_off) == 0
		if ui.menu_item(fmt.tprintf("%s###tall", i18n.tr("Every type")), checked = all, keep_open = true).clicked { folder_all_types(f, !all) }
		for ty, i in types {
			label := ty.ext == "" ? i18n.tr("No extension") : strings.to_upper(ty.ext, context.temp_allocator)
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
	m.ranks_tab, m.ranks_by = t.id, by
	ui.menu_open(RANKS_MENU, at)
}

// (not rodata: i18n.later marks them for the catalogue; tr where they are shown)
@(private = "file")
RANK_TITLES := [Group_By][8]string{
	.None = {},
	.Type = {},
	.Date = {i18n.later("Today"), i18n.later("Yesterday"), i18n.later("This week"), i18n.later("This month"), i18n.later("This year"), i18n.later("Older"), "", i18n.later("No date")},
	.Size = {i18n.later("Folders"), i18n.later("Tiny (under 16 KB)"), i18n.later("Small (under 1 MB)"), i18n.later("Medium (under 128 MB)"), i18n.later("Large (under 1 GB)"), i18n.later("Huge (1 GB and more)"), "", ""},
}

@(private = "file")
rank_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if ui.menu(RANKS_MENU) {
		t := find_tab(app, m.ranks_tab)
		if t == nil { ui.menu_close(); return }
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
		every := fmt.tprintf("%s###rall", by == .Date ? i18n.tr("Every date") : i18n.tr("Every size"))
		if ui.menu_item(every, checked = off == {}, keep_open = true).clicked { folder_all_ranks(f, by) }
		ui.menu_separator()
		for title, r in RANK_TITLES[by] {
			if title == "" || counts[r] == 0 && r not_in off { continue }
			if ui.menu_item(fmt.tprintf("%s###r%d", i18n.tr(title), r), fmt.tprintf("%d", counts[r]), checked = r not_in off, keep_open = true).clicked {
				folder_toggle_rank(f, by, r, now, app.tz)
			}
		}
	}
}

// A tab's menu (a right click on it): what to do with it and the tabs beside it.
tab_menu_open :: proc(app: ^App) {
	ui.menu_open(TAB_MENU, ui.mouse_pos())
}

@(private = "file")
tab_menu_build :: proc(app: ^App, em: f32) {
	if ui.menu(TAB_MENU) {
		p := current_panel(app)
		t := current_tab(app)
		if t == nil { ui.menu_close(); return }
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

// Every tab of a panel, the shown one ticked: a click shows it (a row with more tabs than it holds hides some).
tabs_menu_open :: proc(app: ^App, p: ^Panel) {
	t := panel_tab(p)
	if t == nil { return }
	m := &app.panel_menus
	m.tabs_tab = t.id
	ui.menu_open(TABS_MENU, ui.mouse_pos())
}

@(private = "file")
tabs_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if ui.menu(TABS_MENU, em * MENU_WIDTH_EM) {
		// (the panel is the one that holds the tab noted: closed meanwhile, there is none)
		for p, pi in app.panels {
			holds := false
			for t in p.tabs { if t.id == m.tabs_tab { holds = true } }
			if !holds { continue }
			for t, i in p.tabs {
				if ui.menu_item(fmt.tprintf("%s###tl%d", ui.text_shown(tab_title(app, t)), t.id), checked = i == p.active).clicked {
					p.active, app.focus = i, pi
				}
			}
			return
		}
		ui.menu_close()
	}
}

history_menu_open :: proc(app: ^App, t: ^Tab, at: ui.Rect) {
	m := &app.panel_menus
	m.history_tab = t.id
	ui.menu_open(HISTORY_MENU, ui.mouse_pos())
}

panel_menu_open :: proc(app: ^App, pos: ui.Vec2) {
	ui.menu_open(PANEL_MENU, pos)
}

panel_menus_build :: proc(app: ^App, em: f32) {
	history_menu_build(app, em)
	panel_menu_build(app, em)
	tab_menu_build(app, em)
	tabs_menu_build(app, em)
	types_menu_build(app, em)
	rank_menu_build(app, em)
}

@(private = "file")
history_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if ui.menu(HISTORY_MENU, em * MENU_WIDTH_EM) {
		t := find_tab(app, m.history_tab)
		if t == nil { ui.menu_close(); return }
		// the last folder first
		#reverse for v, i in t.back {
			if ui.menu_item(fmt.tprintf("%s###h%d", ui.text_shown(home_path(app, v.path)), i)).clicked {
				for len(t.back) > i + 1 { tab_back_quiet(t) }
				tab_back(app, t)
			}
		}
	}
}

@(private = "file")
panel_menu_build :: proc(app: ^App, em: f32) {
	if ui.menu(PANEL_MENU) {
		t := current_tab(app)
		if t == nil { ui.menu_close(); return }
		// (where every command is, and the settings, first: the menu that the "…" opens is where one looks for them)
		// (the palette's command is the toolkit's: read at the build, its keys the toolkit's)
		pc := ui.palette_command()
		if ui.menu_item(i18n.tr(pc.label), ui.command_shortcut(pc), icon = pc.icon).clicked { palette_open(app) }
		menu_command(app, "options")
		menu_command(app, "shortcuts")
		ui.menu_separator()
		menu_command(app, "new_folder")
		menu_command(app, "new_file")
		menu_command(app, "refresh")
		menu_command(app, "goto_popup")
		menu_command(app, "terminal")
		ui.menu_separator()
		if ui.menu_submenu(i18n.tr("Sort by"), icon = lucide.ARROW_UP_DOWN) {
			s := t.folder.sort
			menu_command(app, "sort_name", checked = s.key == .Name)
			menu_command(app, "sort_modified", checked = s.key == .Modified)
			menu_command(app, "sort_size", checked = s.key == .Size)
			menu_command(app, "sort_type", checked = s.key == .Type)
			ui.menu_separator()
			menu_command(app, "folders_mixed", checked = !s.mixed)
		}
		if ui.menu_submenu(i18n.tr("Group by"), icon = lucide.ROWS_2) {
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
	if ui.menu_submenu(i18n.tr("Open with"), icon = lucide.APP_WINDOW) {
		ready := app.menu.with_path == path && app.menu.handlers_ready
		hs := ready ? app.menu.handlers : nil
		if !ready { _ = ui.menu_item(i18n.tr("Reading…"), disabled = true) } else if len(hs) == 0 { _ = ui.menu_item(i18n.tr("No application"), disabled = true) }
		for h, i in hs {
			label := h.default ? fmt.tprintf("%s###ow%d", fmt.tprintf(i18n.tr("%s (default)"), ui.text_shown(h.name)), i) : fmt.tprintf("%s###ow%d", ui.text_shown(h.name), i)
			if ui.menu_item(label).clicked { launch(app, .Open_With, path, h.id, h.name) }
		}
	}
}
