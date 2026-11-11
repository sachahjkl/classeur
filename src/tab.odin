package classeur

// Tabs and panels. A tab is a place in the file system with its history (back, forward) and the folder it shows; a
// panel holds tabs, one shown; the window shows its panels side by side. Reading a folder is a task of the workers
// (pool.odin): the tab asks, the answer comes back through ui.post, and only the last answer asked counts.

import "core:strings"
import "core:sync"
import "core:time"
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
	back:        [dynamic]string,    // owned paths
	forward:     [dynamic]string,
	reveal_name: string,             // owned: the row to put the cursor on when the read comes (going up: where we came from)
	vl:          ui.Virtual_List,
	filter:      ui.Text_Field,
	filter_open: bool,
	scroll_x:    f32,      // the details' sideways scroll (the columns' layout is the panels' together)
	address:      ui.Text_Field,     // the path typed in place of the crumbs (Ctrl+L)
	address_open: bool,
	address_sel:  int,               // the suggestion chosen under the path field
	address_moved: bool,             // the person chose one (Up, Down): Enter goes there, not to the path typed
	focus_due:    Focus_Due,         // a field to give the keyboard at the next build
	space:        fs.Space,          // the volume's free and total bytes, read with the folder
	has_space:    bool,
	measured:     u64,               // the read whose folders were given to the measures
	locked:       bool,
	flat:         bool,              // the search of File Pilot: every entry under the folder, flattened
	tree:         bool,              // the tree view: folders opened in place (tree_open), their entries under them
	group:        Group_By,          // the rows grouped (the tab's; the folder follows it at each read)
	tree_open:    [dynamic]string,   // owned: the folders opened in the tree, by their path from the tab's folder
	walk:         ^Load_Job,         // the flat read the tab waits for (its progress), nil: none
	zoom:         int,               // an index of ZOOMS: the view and the size of its items
	grid_cols:    int,               // (the columns view: the names in a column)
	cols_key:     ui.Key,            // the columns view's box (the keyboard there)
	cols_cursor:  int,               // the cursor the columns view last brought into view               // the cards per row of the grid, as last laid out              // a folder opened from it opens in a new tab (the lock of the toolbar)
	cursor_rect:  ui.Rect,           // the cursor's row as last built (where the Menu key opens the menu)
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
	tabs:   [dynamic]^Tab,
	active: int,
	below:  bool,   // under the panel before it, in its column (File Pilot's split below); else a column of its own
}

tab_new :: proc(app: ^App, path: string) -> ^Tab {
	app.next_tab_id += 1
	t := new(Tab)
	t.id = app.next_tab_id
	t.folder.sort = app.default_sort
	t.folder.show_hidden = app.show_hidden
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
	for p in t.back { delete(p) }
	delete(t.back)
	for p in t.forward { delete(p) }
	delete(t.forward)
	delete(t.reveal_name)
	ui.vlist_destroy(&t.vl)
	ui.field_destroy(&t.filter)
	ui.field_destroy(&t.address)
	for p in t.tree_open { delete(p) }
	delete(t.tree_open)
	free(t)
}

tab_title :: proc(app: ^App, t: ^Tab) -> string {
	if t.path == app.home { return "Home" }
	b := fs.base(t.path)
	return b != "" ? b : t.path
}

// Goes to `path` (made clean). The place left goes to the history unless `history` is false.
tab_go :: proc(app: ^App, t: ^Tab, path: string, history := true) {
	clean := fs.clean(path)
	if clean == t.path {
		delete(clean)
		tab_load(app, t)
		return
	}
	if history {
		append(&t.back, t.path)
		for p in t.forward { delete(p) }
		clear(&t.forward)
	} else {
		delete(t.path)
	}
	// going up: the cursor goes to the folder we came from
	delete(t.reveal_name)
	t.reveal_name = ""
	old := history ? t.back[len(t.back) - 1] : ""
	if old != "" && fs.parent(old) == clean { t.reveal_name = strings.clone(fs.base(old)) }
	t.path = clean
	t.flat = false
	for p in t.tree_open { delete(p) }
	clear(&t.tree_open)
	measure_forget_asked(app)
	ui.field_clear(&t.filter)
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
	append(&t.forward, t.path)
	t.path = ""
	tab_go(app, t, to, history = false)
	delete(to)
}

tab_forward :: proc(app: ^App, t: ^Tab) {
	if len(t.forward) == 0 { return }
	to := pop(&t.forward)
	append(&t.back, t.path)
	t.path = ""
	tab_go(app, t, to, history = false)
	delete(to)
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
	ms:      f64,
	space:   fs.Space,
	has_space: bool,
}

// Asks the workers to read the tab's folder again.
tab_load :: proc(app: ^App, t: ^Tab) {
	t.serial += 1
	t.loading = true
	if t.walk != nil { sync.atomic_store(&t.walk.cancel, true) }   // (a long walk the tab no longer waits for)
	job := new(Load_Job)
	job^ = {app = app, tab = t.id, serial = t.serial, path = strings.clone(t.path), flat = t.flat}
	if t.tree && !t.flat {
		job.tree = make([]string, len(t.tree_open))
		for p, i in t.tree_open { job.tree[i] = strings.clone(p) }
	}
	t.walk = t.flat ? job : nil
	pool_submit(&app.pool, load_run, job)
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
	job.space, job.has_space = fs.space(job.path)
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
	delete(job.path)
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
	// a path that is not a folder (asked on the worker, never on this thread): a file's path is its folder with the file
	// at the cursor; a folder that is gone (a session's tab, a folder removed) is the nearest folder above it still there
	if !job.flat && (job.listing.error == .Not_A_Folder || job.listing.error == .Not_Found) {
		up := fs.parent(t.path)
		if up != "" && up != t.path {
			if job.listing.error == .Not_A_Folder {
				delete(t.reveal_name)
				t.reveal_name = strings.clone(fs.base(t.path))
			}
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
	same_place := t.folder.loaded && t.folder.listing.path == job.listing.path && t.folder.flat == job.flat
	t.folder.flat = job.flat
	t.folder.tree = t.tree && !job.flat
	if !same_place {
		folder_select_none(&t.folder)
		t.folder.cursor = -1
		if job.listing.error == .None && !job.flat { recent_add(job.app, job.listing.path) }
	}
	if t.folder.group != t.group { t.folder.group, t.folder.group_now, t.folder.group_tz = t.group, time.now()._nsec, job.app.tz }
	measures_apply(job.app, &job.listing)
	folder_set_listing(&t.folder, &job.listing)
	// the row asked for (made, renamed, the folder we came up from) has the cursor and the selection
	revealed := t.reveal_name != "" && folder_cursor_to_name(&t.folder, t.reveal_name)
	if revealed { folder_pick(&t.folder, t.folder.cursor) }
	if !same_place && !revealed {
		t.folder.cursor = len(t.folder.shown) > 0 ? 0 : -1
		t.folder.anchor = t.folder.cursor
		ui.vlist_scroll_to(&t.vl, 0)
	}
	if revealed || !same_place { ui.list_select(&t.vl, t.folder.cursor) }
	delete(t.reveal_name)
	t.reveal_name = ""
	app_frames(job.app)
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
	t := tab_new(app, path)
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
	append(&t.forward, t.path)
	t.path = to
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
