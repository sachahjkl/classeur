package classeur

// Tabs and panels. A tab is a place in the file system with its history (back, forward) and the folder it shows; a
// panel holds tabs, one shown; the window shows its panels side by side. Reading a folder is a task of the workers
// (gt:tasks): the tab asks, the answer comes back through ui.post, and only the last answer asked counts.

import "core:strings"
import "core:sync"
import "core:time"
import "gt:i18n"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

Tab :: struct {
	resort_due:  bool,              // folders measured since its sort by size: sorted again before the next build
	walk_shown:  u64,               // the serial of the walk whose batches it shows (the first one replaced its rows)
	id:          u64,
	path:        string,             // owned, clean (fs.clean)
	folder:      Folder,
	serial:      u64,                // the read asked last; an older answer is dropped
	loading:     bool,
	load_ms:     f64,                // how long the last read took
	back:        [dynamic]Visit,
	forward:     [dynamic]Visit,
	reveal_name: string,             // owned: the row to put the cursor on when the read comes (going up: where we came from)
	select_names: [dynamic]string,   // owned: the rows selected when the read comes (what a paste made here), the cursor on the first
	reveal_scroll: Maybe(f32),       // with it, the list's scroll (Back and Forward: where the folder was left)
	vl:          ui.Virtual_List,
	filter:      ui.Line_Edit,
	filter_open: bool,
	scroll_x:    f32,      // the details' sideways scroll (the columns' layout is the panels' together)
	address:      ui.Line_Edit,     // the path typed in place of the crumbs (Ctrl+L)
	address_open: bool,
	address_sel:  int,               // the suggestion chosen under the path field
	address_moved: bool,             // the person chose one (Up, Down): Enter goes there, not to the path typed
	focus_due:    Focus_Due,         // a field to give the keyboard at the next build
	space:        fs.Space,          // the volume's free and total bytes, read with the folder
	has_space:    bool,
	share_root:   string,            // owned: the folder of the share the path is under ("": none), read with the folder
	share_uri:    string,            // owned: its URI (the first crumb)
	share_label:  string,            // owned: its name ("docs on nas": the title of a tab on its root)
	in_archive:   bool,              // the folder is an archive entered or a folder of one (read only), read with the folder
	measured:     u64,               // the read whose folders were given to the measures
	locked:       bool,
	tearing:      bool,              // its window of its own starts on a worker (tab_window): closed when that lands
	flat:         bool,              // the search of File Pilot: every entry under the folder, flattened
	tree:         bool,              // the tree view: folders opened in place (tree_open), their entries under them
	group:        Group_By,          // the rows grouped (the tab's; the folder follows it at each read)
	tree_open:    [dynamic]string,   // owned: the folders opened in the tree, by their path from the tab's folder
	walk:         ^Load_Job,         // the flat read the tab waits for (its progress), nil: none; freed on this thread alone
	reload_due:   bool,              // its folder changed while it was read: read again when the read comes
	zoom:         int,               // an index of ZOOMS: the view and the size of its items
	grid_cols:    int,               // (the columns view: the names in a column)
	grid_ids:     [dynamic]u64,      // the grid's rows' identities, made when the rows or the cards per row change
	grid_ids_version: u64,           // what they were made for (folder's ids_version, cards per row): the virtual list's
	grid_ids_made: int,              // the times they were made
	cols_key:     ui.Key,            // the columns view's box (the keyboard there)
	cols_cursor:  int,               // the cursor the columns view last brought into view
	cursor_rect:  ui.Rect,           // the cursor's row as last built (where the Menu key opens the menu)
}

// A place of the history: a folder, and where it was left (Back and Forward come back to the same row and scroll).
Visit :: struct {
	path:   string,   // owned
	name:   string,   // owned: the entry the cursor was on, "": none
	scroll: f32,      // the list's scroll
}

visit_delete :: proc(v: Visit) {
	delete(v.path)
	delete(v.name)
}

// The tab's place as it leaves it; the visit takes its path.
@(private = "file")
tab_visit :: proc(t: ^Tab) -> Visit {
	v := Visit{path = t.path}
	// (a folder still being read shows the one before it: nothing of it to keep)
	if t.folder.loaded && t.folder.listing.path == t.path {
		if e := folder_cursor_entry(&t.folder); e != nil { v.name = strings.clone(e.name) }
		if t.vl.key != 0 {
			if b := ui.box_from_key(t.vl.key); b != nil { v.scroll = b.view_target.y }
		}
	}
	return v
}

// The views, File Pilot's zoom: the details, the names alone, the names in columns, then cards ever larger.
View_Mode :: enum u8 { Details, List, Columns, Grid }

Zoom :: struct {
	percent: int,       // what the footer shows
	mode:    View_Mode,
	card_em: f32,       // a card's width (Grid)
}

@(rodata)
ZOOMS := [?]Zoom{
	{0, .Details, 0}, {10, .List, 0}, {20, .Columns, 0},
	{30, .Grid, 8.5}, {50, .Grid, 11.5}, {70, .Grid, 15}, {100, .Grid, 20},
}
ZOOM_GRID :: 4   // the grid of Ctrl+2

tab_mode :: proc(t: ^Tab) -> View_Mode { return ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)].mode }

// The items per row of the views that have several (Columns, Grid), 1 for the others.
tab_row_items :: proc(t: ^Tab) -> int { return tab_mode(t) >= .Columns ? max(t.grid_cols, 1) : 1 }

tab_set_zoom :: proc(app: ^App, t: ^Tab, zoom: int) {
	t.zoom = clamp(zoom, 0, len(ZOOMS) - 1)
	app.default_zoom = t.zoom
	ui.list_select(&t.vl, t.folder.cursor / tab_row_items(t))
}

// What the next build gives the keyboard to (it knows the boxes' keys).
Focus_Due :: enum u8 { None, List, Filter, Address }

Panel :: struct {
	tabs:     [dynamic]^Tab,
	active:   int,
	below:    bool,   // under the panel before it, in its column (File Pilot's split below); else a column of its own
	tab_seen: u64,    // the shown tab the row of tabs last brought into view (another one shown: brought into view too)
}

tab_new :: proc(app: ^App, path: string) -> ^Tab {
	app.next_tab_id += 1
	t := new(Tab)
	t.id = app.next_tab_id
	t.folder.sort = app.default_sort
	t.folder.show_hidden = app.show_hidden
	t.folder.group_tz = app.tz   // (the days kept with each listing are in it: folder_prepare)
	t.folder.cursor = -1
	t.zoom = app.default_zoom
	t.path = fs.clean(path)
	tab_load(app, t)
	return t
}

tab_destroy :: proc(t: ^Tab) {
	if t.walk != nil { sync.atomic_store(&t.walk.cancel, true) }   // (load_done frees it; no tab will take it)
	delete(t.path)
	folder_destroy(&t.folder)
	for v in t.back { visit_delete(v) }
	delete(t.back)
	for v in t.forward { visit_delete(v) }
	delete(t.forward)
	delete(t.reveal_name)
	delete(t.share_root)
	delete(t.share_uri)
	delete(t.share_label)
	tab_select_forget(t)
	delete(t.select_names)
	ui.vlist_destroy(&t.vl)
	delete(t.grid_ids)
	ui.line_edit_destroy(&t.filter)
	ui.line_edit_destroy(&t.address)
	for p in t.tree_open { delete(p) }
	delete(t.tree_open)
	free(t)
}

tab_title :: proc(app: ^App, t: ^Tab) -> string {
	if t.path == app.home { return i18n.tr("Home") }
	// (a share's root is named by its URI's label, asked with the folder's read: never here, each frame)
	if t.share_root != "" && t.share_root == t.path { return t.share_label }
	if n := fs.trash_title(t.path); n != "" { return n }
	b := fs.base(t.path)
	return b != "" ? b : t.path
}

// Goes to `path` (made clean): a path, or a place that stands for one (a file's URI, trash:///, smb://...: locations.odin;
// a share not mounted yet: the tab goes there once it is). The place left goes to the history unless `history` is false.
tab_go :: proc(app: ^App, t: ^Tab, path: string, history := true) {
	path := path
	if fs.is_uri(path) {
		p, ok := location_path(app, path, t.id)
		if !ok { return }
		path = p
	}
	clean := fs.clean(path)
	if clean == t.path {
		delete(clean)
		tab_load(app, t)
		return
	}
	if history {
		append(&t.back, tab_visit(t))
		for v in t.forward { visit_delete(v) }
		clear(&t.forward)
	} else {
		delete(t.path)
	}
	// going up: the cursor goes to the folder we came from
	delete(t.reveal_name)
	t.reveal_name = ""
	tab_select_forget(t)   // (the rows a paste made: of the folder left)
	t.reveal_scroll = nil
	old := history ? t.back[len(t.back) - 1].path : ""
	if old != "" && fs.parent(old) == clean { t.reveal_name = strings.clone(fs.base(old)) }
	t.path = clean
	t.flat = false
	for p in t.tree_open { delete(p) }
	clear(&t.tree_open)
	measure_forget_asked(app)
	ui.line_edit_clear(&t.filter)
	t.filter_open = false
	folder_set_filter(&t.folder, "")
	// (the types' popup is the folder's: another folder shows every type)
	t.folder.kinds = .All
	for k in t.folder.types_off { delete(k) }
	clear(&t.folder.types_off)
	t.folder.dates_off, t.folder.sizes_off = {}, {}   // (the columns' filters are the folder's too)
	tab_load(app, t)
}

tab_up :: proc(app: ^App, t: ^Tab) {
	p := fs.parent(t.path)
	if p != "" { tab_go(app, t, p) }
}

tab_back :: proc(app: ^App, t: ^Tab) {
	if len(t.back) == 0 { return }
	to := pop(&t.back)
	append(&t.forward, tab_visit(t))
	t.path = ""
	tab_return(app, t, to)
}

tab_forward :: proc(app: ^App, t: ^Tab) {
	if len(t.forward) == 0 { return }
	to := pop(&t.forward)
	append(&t.back, tab_visit(t))
	t.path = ""
	tab_return(app, t, to)
}

// Back to a place of the history: the read puts the cursor on the row it was on, and the list where it was.
@(private = "file")
tab_return :: proc(app: ^App, t: ^Tab, to: Visit) {
	tab_go(app, t, to.path, history = false)
	if to.name != "" {
		delete(t.reveal_name)
		t.reveal_name = strings.clone(to.name)
		t.reveal_scroll = to.scroll
	}
	visit_delete(to)
}

////////////////////////////////
// Reading the folder

Load_Job :: struct {
	app:     ^App,
	tab:     u64,
	serial:  u64,
	path:    string,
	flat:    bool,   // every entry under the folder (fs.walk), not its own
	tree:    []string,   // owned: the folders opened in the tree, read too (their entries named by their path)
	count:   int,    // atomic: the entries read so far (a flat read's progress)
	cancel:  bool,   // atomic: the tab no longer waits for it
	listing: fs.Listing,
	view:    Folder,   // the tab's settings when it asked (folder_view_copy), then the listing prepared with them
	ms:      f64,
	space:   fs.Space,
	has_space: bool,
	share_root, share_uri, share_label: string,   // owned: the share the path is under (fs.share_root reads the mounts)
	in_archive: bool,   // the path is in an archive (fs.archive_holds stats the parts named like one)
}

// Asks the workers to read the tab's folder again.
tab_load :: proc(app: ^App, t: ^Tab) {
	t.serial += 1
	t.loading = true
	t.reload_due = false   // (this read starts after the change: it sees it)
	if t.walk != nil { sync.atomic_store(&t.walk.cancel, true) }   // (a long walk the tab no longer waits for)
	job := new(Load_Job)
	job^ = {app = app, tab = t.id, serial = t.serial, path = strings.clone(t.path), flat = t.flat}
	// (the worker sorts and filters the listing as the tab will show it: load_done sets the same flat, tree and groups)
	folder_view_copy(&job.view, &t.folder)
	job.view.flat, job.view.tree = t.flat, t.tree && !t.flat
	if t.folder.group != t.group { job.view.group, job.view.group_now, job.view.group_tz = t.group, time.now()._nsec, app.tz }
	if t.tree && !t.flat {
		job.tree = make([]string, len(t.tree_open))
		for p, i in t.tree_open { job.tree[i] = strings.clone(p) }
	}
	t.walk = t.flat ? job : nil
	tasks.add(&app.pool, load_run, job)
}

// The entries a flat read has read so far.
tab_walked :: proc(t: ^Tab) -> int { return t.walk != nil ? sync.atomic_load(&t.walk.count) : 0 }

@(private = "file")
load_run :: proc(data: rawptr) {
	job := (^Load_Job)(data)
	start := time.tick_now()
	if job.flat {
		// (what it found so far goes to the tab as it reads: a search shows its results while it walks)
		fs.walk(&job.listing, job.path, &job.count, proc(user: rawptr) -> bool { return sync.atomic_load(&(^Load_Job)(user).cancel) }, job, load_progress)
	} else {
		fs.list(&job.listing, job.path)
		// the tree's open folders: their entries after the folder's own, named by their path from it
		for rel in job.tree {
			sub: fs.Listing
			if fs.list(&sub, fs.join(job.path, rel, context.temp_allocator)) == .None {
				for e in sub.entries {
					x := e
					x.name = fs.keep_name(&job.listing, fs.join(rel, e.name, context.temp_allocator))
					append(&job.listing.entries, x)
				}
			}
			fs.listing_destroy(&sub)
		}
	}
	job.ms = time.duration_milliseconds(time.tick_since(start))
	folder_prepare(&job.view, &job.listing)
	job.space, job.has_space = fs.space(job.path)
	if root, uri, ok := fs.share_root(job.path); ok {
		job.share_root, job.share_uri, job.share_label = root, uri, fs.share_label(uri)
	}
	// (an entry of the folder is in the archive when the folder is one or in one)
	job.in_archive = fs.archive_holds(fs.join(job.path, "x", context.temp_allocator))
	// (refused once the app closes, which let go of every walk first: no tab points to the job freed here)
	if !ui.post(&job.app.main.state, load_done, job) { load_free(job) }
}

// A batch of a walk, on its way to the interface's thread.
@(private = "file")
Walk_Batch :: struct {
	app:     ^App,
	tab:     u64,
	serial:  u64,
	listing: fs.Listing,
}

// On the walk's thread: the entries found since the last batch, posted to the tab.
@(private = "file")
load_progress :: proc(user: rawptr, batch: ^fs.Listing) {
	job := (^Load_Job)(user)
	b := new(Walk_Batch)
	b^ = {app = job.app, tab = job.tab, serial = job.serial, listing = batch^}
	batch^ = {}
	if !ui.post(&job.app.main.state, load_batch, b) { fs.listing_destroy(&b.listing); free(b) }
}

// On the interface's thread: a walk's batch shown in its tab, when the tab still waits for that walk. The first one
// takes the place of what the tab showed; the next ones are added (the full listing still comes at the end: load_done).
@(private = "file")
load_batch :: proc(data: rawptr, word: u64) {
	b := (^Walk_Batch)(data)
	defer { fs.listing_destroy(&b.listing); free(b) }
	t := find_tab(b.app, b.tab)
	if t == nil || t.serial != b.serial || t.walk == nil { return }
	f := &t.folder
	if t.walk_shown != b.serial {
		t.walk_shown = b.serial
		f.flat, f.tree = true, false
		folder_set_listing(f, &b.listing)
		f.cursor = len(f.shown) > 0 ? 0 : -1
		f.anchor = f.cursor
		// (a new search: at its top, its first row chosen; load_done sees the same place and keeps it)
		ui.vlist_scroll_to(&t.vl, 0)
		ui.list_select(&t.vl, f.cursor)
	} else {
		folder_add_entries(f, &b.listing)
	}
	app_frames(b.app)
}

@(private = "file")
load_free :: proc(data: rawptr) {
	job := (^Load_Job)(data)
	fs.listing_destroy(&job.listing)
	folder_destroy(&job.view)
	delete(job.path)
	delete(job.share_root)
	delete(job.share_uri)
	delete(job.share_label)
	for p in job.tree { delete(p) }
	delete(job.tree)
	free(job)
}

// On the interface's thread: the folder read, given to its tab when it is still the read the tab waits for.
@(private = "file")
load_done :: proc(data: rawptr, word: u64) {
	job := (^Load_Job)(data)
	defer load_free(job)
	t := find_tab(job.app, job.tab)
	if t != nil && t.walk == job { t.walk = nil }
	if t == nil || t.serial != job.serial { return }
	l := &job.view.listing   // (prepared on the worker: folder_prepare)
	// a path that is not a folder (asked on the worker, never on this thread): a file's path is its folder with the file
	// at the cursor; a folder that is gone (a session's tab, a folder removed) is the nearest folder above it still there
	if !job.flat && (l.error == .Not_A_Folder || l.error == .Not_Found) {
		up := fs.parent(t.path)
		if up != "" && up != t.path {
			if l.error == .Not_A_Folder {
				delete(t.reveal_name)
				t.reveal_name = strings.clone(fs.base(t.path))
			}
			t.reveal_scroll = nil   // (another folder: its rows are not where they were)
			old := t.path
			t.path = strings.clone(up)
			delete(old)
			tab_load(job.app, t)
			return
		}
	}
	t.loading = false
	t.load_ms = job.ms
	t.space, t.has_space = job.space, job.has_space
	delete(t.share_root); delete(t.share_uri); delete(t.share_label)
	t.share_root, t.share_uri, t.share_label = job.share_root, job.share_uri, job.share_label
	job.share_root, job.share_uri, job.share_label = "", "", ""
	t.in_archive = job.in_archive
	same_place := t.folder.loaded && t.folder.listing.path == l.path && t.folder.flat == job.flat
	t.folder.flat = job.flat
	t.folder.tree = t.tree && !job.flat
	if !same_place {
		folder_select_none(&t.folder)
		t.folder.cursor = -1
		if l.error == .None && !job.flat { recent_add(job.app, l.path) }
	}
	if t.folder.group != t.group { t.folder.group, t.folder.group_now, t.folder.group_tz = t.group, job.view.group_now, job.view.group_tz }
	// (the rows sorted and filtered on the worker are taken as they are: here only the selection and the cursor, by name)
	folder_take(&t.folder, &job.view)
	// the folders measured already: their sizes in their entries (sorted by size, the order again)
	if measures_apply(job.app, &t.folder.listing) {
		if t.folder.sort.key == .Size {
			folder_resort(&t.folder)
		} else {
			for i in t.folder.shown { t.folder.size_max = max(t.folder.size_max, t.folder.listing.entries[i].size) }
		}
	}
	// (a name being typed in this tab: its row may have moved, and its field with it; the keyboard goes back to it)
	if r := &job.app.rename; r.active && r.tab == t.id { r.focus_due = true }
	// the row asked for (made, renamed, the folder we came up from) has the cursor and the selection
	revealed := t.reveal_name != "" && folder_cursor_to_name(&t.folder, t.reveal_name)
	if revealed { folder_pick(&t.folder, t.folder.cursor) }
	// (Back, Forward: the list where it was left; the cursor's row is in it, the reveal below keeps it there)
	if y, ok := t.reveal_scroll.?; ok && revealed { ui.vlist_scroll_to(&t.vl, y) }
	if !same_place && !revealed {
		t.folder.cursor = len(t.folder.shown) > 0 ? 0 : -1
		t.folder.anchor = t.folder.cursor
		ui.vlist_scroll_to(&t.vl, 0)
	}
	if revealed || !same_place { ui.list_select(&t.vl, t.folder.cursor) }
	delete(t.reveal_name)
	t.reveal_name = ""
	t.reveal_scroll = nil
	if len(t.select_names) > 0 {
		if tab_select_apply(t) { ui.list_select(&t.vl, t.folder.cursor / tab_row_items(t)) }
		tab_select_forget(t)
	}
	// (a change came while it was read: what was read may not have it)
	if t.reload_due { tab_load(job.app, t) }
	app_frames(job.app)
}

// The rows of `select_names` selected alone, the cursor on the first of them found. False: none is here.
tab_select_apply :: proc(t: ^Tab) -> bool {
	f := &t.folder
	first := -1
	// (each name by the names' index: a paste of thousands is not thousands of passes over the rows)
	for name in t.select_names {
		i := folder_find_name(f, name)
		if i < 0 || i >= len(f.row_of) || f.row_of[i] < 0 { continue }
		row := int(f.row_of[i])
		if first < 0 {
			folder_select_none(f)
			first = row
		}
		folder_set_row(f, row, true)
	}
	if first < 0 { return false }
	f.cursor, f.anchor = first, first
	return true
}

tab_select_forget :: proc(t: ^Tab) {
	for s in t.select_names { delete(s) }
	clear(&t.select_names)
}

find_tab :: proc(app: ^App, id: u64) -> ^Tab {
	for p in app.panels { for t in p.tabs { if t.id == id { return t } } }
	return nil
}

panel_tab :: proc(p: ^Panel) -> ^Tab {
	if len(p.tabs) == 0 { return nil }
	return p.tabs[clamp(p.active, 0, len(p.tabs) - 1)]
}

panel_destroy :: proc(p: ^Panel) {
	for t in p.tabs { tab_destroy(t) }
	delete(p.tabs)
	free(p)
}

// The tab the keyboard works in: the active tab of the focused panel.
current_tab :: proc(app: ^App) -> ^Tab {
	if len(app.panels) == 0 { return nil }
	return panel_tab(app.panels[clamp(app.focus, 0, len(app.panels) - 1)])
}

current_panel :: proc(app: ^App) -> ^Panel {
	if len(app.panels) == 0 { return nil }
	return app.panels[clamp(app.focus, 0, len(app.panels) - 1)]
}

tab_open :: proc(app: ^App, p: ^Panel, path: string, at := -1) {
	// (a place that stands for a path: the tab opens on the home folder and goes there, once mounted for a share)
	t := tab_new(app, fs.is_uri(path) ? app.home : path)
	if fs.is_uri(path) { tab_go(app, t, path, history = false) }
	i := at < 0 ? len(p.tabs) : min(at, len(p.tabs))
	inject_at(&p.tabs, i, t)
	p.active = i
}

tab_close :: proc(app: ^App, p: ^Panel, i: int) {
	if i < 0 || i >= len(p.tabs) { return }
	t := p.tabs[i]
	// (kept to open again: Ctrl+Shift+T)
	append(&app.closed_tabs, strings.clone(t.path))
	tab_destroy(t)
	ordered_remove(&p.tabs, i)
	if p.active >= len(p.tabs) { p.active = len(p.tabs) - 1 }
	if p.active > i { p.active -= 1 }
	if len(p.tabs) == 0 {
		// the last tab of a panel closes the panel, the last panel keeps one tab at home
		if len(app.panels) > 1 {
			panel_close(app, p)
		} else {
			tab_open(app, p, app.home)
		}
	}
}

// A new panel after the focused one: beside it (a column of its own), or `below` it in its column.
panel_open :: proc(app: ^App, path: string, below := false) {
	p := new(Panel)
	p.below = below
	tab_open(app, p, path)
	at := below ? app.focus + 1 : column_end(app, app.focus)
	inject_at(&app.panels, at, p)
	app.focus = at
}

// The index after the last panel of the column of panel `i` (a new column goes there: the panels below `i` stay its).
column_end :: proc(app: ^App, i: int) -> int {
	end := clamp(i, 0, len(app.panels) - 1) + 1
	for end < len(app.panels) && app.panels[end].below { end += 1 }
	return end
}

panel_close :: proc(app: ^App, p: ^Panel) {
	for q, i in app.panels {
		if q != p { continue }
		// (the panel under it, the top of its column now)
		if !p.below && i + 1 < len(app.panels) && app.panels[i + 1].below { app.panels[i + 1].below = false }
		ordered_remove(&app.panels, i)
		panel_destroy(p)
		if app.focus >= len(app.panels) { app.focus = len(app.panels) - 1 }
		return
	}
}

RECENTS_MAX :: 12

// The folder visited goes first in the recent ones.
recent_add :: proc(app: ^App, path: string) {
	for p, i in app.recents {
		if p == path {
			ordered_remove(&app.recents, i)
			inject_at(&app.recents, 0, p)
			return
		}
	}
	inject_at(&app.recents, 0, strings.clone(path))
	if len(app.recents) > RECENTS_MAX { delete(pop(&app.recents)) }
}

// One step back with no read (several steps of the history menu: the last one reads).
tab_back_quiet :: proc(t: ^Tab) {
	if len(t.back) == 0 { return }
	to := pop(&t.back)
	append(&t.forward, tab_visit(t))
	t.path = to.path
	delete(to.name)
}

// The tree view on or off (off: the folders opened are closed).
act_tree :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { return }
	t.tree = !t.tree
	if !t.tree {
		for p in t.tree_open { delete(p) }
		clear(&t.tree_open)
	}
	tab_load(app, t)
}

// The folder `rel` (its path from the tab's folder) opened in the tree, or closed with what is open below it.
tab_tree_toggle :: proc(app: ^App, t: ^Tab, rel: string) {
	for p, i in t.tree_open {
		if p != rel { continue }
		prefix := strings.concatenate({rel, fs.SEPARATOR_STRING}, context.temp_allocator)
		for k := len(t.tree_open) - 1; k >= 0; k -= 1 {
			if t.tree_open[k] == rel || strings.has_prefix(t.tree_open[k], prefix) {
				delete(t.tree_open[k])
				ordered_remove(&t.tree_open, k)
			}
		}
		_ = i
		tab_load(app, t)
		return
	}
	t.tree = true
	append(&t.tree_open, strings.clone(rel))
	tab_load(app, t)
}

tab_tree_is_open :: proc(t: ^Tab, rel: string) -> bool {
	for p in t.tree_open { if p == rel { return true } }
	return false
}

// The rows grouped by `g` (again: no groups).
tab_group :: proc(app: ^App, g: Group_By) {
	t := current_tab(app)
	if t == nil { return }
	t.group = t.group == g ? .None : g
	folder_set_group(&t.folder, t.group, time.now()._nsec, app.tz)
}

act_group_date :: proc(app: ^App) { tab_group(app, .Date) }
act_group_type :: proc(app: ^App) { tab_group(app, .Type) }
act_group_size :: proc(app: ^App) { tab_group(app, .Size) }
