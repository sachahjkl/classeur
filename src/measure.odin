package classeur

// What a folder holds, all the way down: its folders, its files, their bytes (File Pilot's Folders, Files and Size
// columns). The folders of the tabs shown are measured on a pool of their own (a measure of a large tree must not
// delay the reading of a folder), nearest first; a measure no tab shows any more is dropped before it starts. The
// results are kept by path and folder date: a folder whose date changed is measured again.

import "core:slice"
import "core:strings"
import "core:sync"
import "gt:ui"
import "fs"

MEASURE_THREADS :: 2

Measure :: struct {
	folders, files: i64,
	bytes:          i64,
	mtime:          i64,    // the folder's date when it was measured
	tab:            u64,    // the tab that asked it
	used:           u64,    // the frame it came or was last shown in (beyond MEASURES_MAX, the least recent go)
	done:           bool,   // false: asked, not yet come
}

// The measures kept at most: beyond, the finished ones least recently used go, down to MEASURES_KEEP.
MEASURES_MAX  :: 20_000
MEASURES_KEEP :: 15_000

// What a tab asks on its folder, shared by its measures: when the tab goes elsewhere or closes, they stop (the measures
// of the other tabs go on). Freed by the last of the app and the measures that hold it.
Measure_Ask :: struct {
	path:   string,   // owned: the tab's folder when it asked
	cancel: bool,     // atomic
	refs:   int,      // atomic
}

@(private = "file")
Measure_Job :: struct {
	app:   ^App,
	path:  string,   // owned
	mtime: i64,
	ask:   ^Measure_Ask,
	m:     Measure,
}

@(private = "file")
ask_release :: proc(a: ^Measure_Ask) {
	if sync.atomic_sub(&a.refs, 1) == 1 {
		delete(a.path)
		free(a)
	}
}

measures_free :: proc(app: ^App) {
	for k in app.measures { delete(k) }
	delete(app.measures)
	for _, a in app.measure_asks { ask_release(a) }
	delete(app.measure_asks)
}

// Every measure stops at its next folder (the app closes).
measures_cancel :: proc(app: ^App) {
	for _, a in app.measure_asks { sync.atomic_store(&a.cancel, true) }
}

// Asks the measures of the folders shown in `t` that are not known (or whose date changed).
measure_tab :: proc(app: ^App, t: ^Tab) {
	if !t.folder.loaded || t.folder.flat { return }   // (a flat listing holds its folders' content already)
	measure_forget_asked(app)   // (an ask of the tab's folder before: not this one's)
	ask := app.measure_asks[t.id]
	for i in t.folder.shown {
		e := t.folder.listing.entries[i]
		if e.kind != .Directory || .Link in e.flags { continue }
		path := fs.join(t.path, e.name, context.temp_allocator)
		if m, ok := app.measures[path]; ok && m.mtime == e.mtime { continue }
		if old_key, _ := delete_key(&app.measures, path); old_key != "" { delete(old_key) }
		app.measures[strings.clone(path)] = {mtime = e.mtime, tab = t.id, used = app.frame}
		if ask == nil {
			ask = new(Measure_Ask)
			ask^ = {path = strings.clone(t.path), refs = 1}
			app.measure_asks[t.id] = ask
		}
		sync.atomic_add(&ask.refs, 1)
		job := new(Measure_Job)
		job^ = {app = app, path = strings.clone(path), mtime = e.mtime, ask = ask}
		pool_submit(&app.measure_pool, measure_run, job)
	}
}

// The asks of the tabs gone elsewhere or closed: stopped, their measures not come yet forgotten (measure_run skips
// them, measure_done drops what they found). The other tabs' measures go on.
measure_forget_asked :: proc(app: ^App) {
	gone := make([dynamic]u64, context.temp_allocator)
	for id, a in app.measure_asks {
		t := find_tab(app, id)
		if t == nil || t.path != a.path { append(&gone, id) }
	}
	if len(gone) == 0 { return }
	for id in gone {
		_, a := delete_key(&app.measure_asks, id)
		sync.atomic_store(&a.cancel, true)
		ask_release(a)
	}
	keys := make([dynamic]string, context.temp_allocator)
	for k, m in app.measures { if !m.done && slice.contains(gone[:], m.tab) { append(&keys, k) } }
	for k in keys {
		old_key, _ := delete_key(&app.measures, k)
		delete(old_key)
	}
	// (another tab on one of those folders did not ask what this one had: asked again)
	if len(keys) > 0 { for p in app.panels { for t in p.tabs { t.measured = 0 } } }
}

// Each frame: the measures of the tabs shown, once per read of their folder.
measure_update :: proc(app: ^App) {
	measure_forget_asked(app)
	if !app.settings.measure_folders { return }
	for p in app.panels {
		t := panel_tab(p)
		if t == nil || t.loading || !t.folder.loaded || t.measured == t.serial { continue }
		t.measured = t.serial
		measure_tab(app, t)
	}
}

measure_of :: proc(app: ^App, t: ^Tab, e: fs.Entry) -> (Measure, bool) {
	m, ok := &app.measures[fs.join(t.path, e.name, context.temp_allocator)]
	if !ok || !m.done { return {}, false }
	m.used = app.frame
	return m^, true
}

@(private = "file")
measure_run :: proc(data: rawptr) {
	job := (^Measure_Job)(data)
	if sync.atomic_load(&job.ask.cancel) {
		measure_free(job)
		return
	}
	walk(job)
	job.m.done = true
	if !ui.post(&job.app.main.state, measure_done, job) { measure_free(job) }
}

// The folders under the job's, read one by one from a stack (not a recursion): the temporary memory of each is freed
// once it is read, so a large tree holds only the paths still to read.
@(private = "file")
walk :: proc(job: ^Measure_Job) {
	pending := make([dynamic]string)
	defer {
		for p in pending { delete(p) }
		delete(pending)
	}
	append(&pending, strings.clone(job.path))
	l: fs.Listing
	defer fs.listing_destroy(&l)
	for len(pending) > 0 && !sync.atomic_load(&job.ask.cancel) {
		path := pop(&pending)
		if fs.list(&l, path) == .None {
			for e in l.entries {
				if e.kind == .Directory && .Link not_in e.flags {
					job.m.folders += 1
					append(&pending, fs.join(path, e.name))
				} else {
					job.m.files += 1
					if e.size > 0 { job.m.bytes += e.size }
				}
			}
		}
		delete(path)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
measure_free :: proc(job: ^Measure_Job) {
	delete(job.path)
	ask_release(job.ask)
	free(job)
}

@(private = "file")
measure_done :: proc(data: rawptr, word: u64) {
	job := (^Measure_Job)(data)
	defer measure_free(job)
	app := job.app
	if sync.atomic_load(&job.ask.cancel) { return }   // (its tab went elsewhere: what it found may be stale)
	if m, ok := &app.measures[job.path]; ok && m.mtime == job.mtime {
		job.m.mtime, job.m.tab, job.m.used = job.mtime, m.tab, app.frame
		m^ = job.m
		app_frames(app)
		// the folder's size in its entry, in the tabs that show it: sorted by size, folders go among the sizes
		// (the listing shown, not the one a tab waits for; the entry found by its name, at the date it was measured at)
		parent, name := fs.parent(job.path), fs.base(job.path)
		for p in app.panels {
			for t in p.tabs {
				f := &t.folder
				if f.listing.path != parent { continue }
				at := folder_find_name(f, name)
				if at < 0 { continue }
				e := &f.listing.entries[at]
				if e.kind != .Directory || e.mtime != job.mtime { continue }
				e.size = job.m.bytes
				f.size_max = max(f.size_max, e.size)
				if f.sort.key == .Size { t.resort_due = true }
			}
		}
		if len(app.measures) > MEASURES_MAX { measures_trim(app) }
	}
}

// The finished measures least recently used forgotten, down to MEASURES_KEEP (once in a while: not at each measure).
// Those shown in this frame stay.
@(private = "file")
measures_trim :: proc(app: ^App) {
	Kept :: struct { key: string, used: u64 }
	old := make([dynamic]Kept, 0, len(app.measures), context.temp_allocator)
	for k, m in app.measures { if m.done { append(&old, Kept{k, m.used}) } }
	slice.sort_by(old[:], proc(a, b: Kept) -> bool { return a.used < b.used })
	for x in old {
		if len(app.measures) <= MEASURES_KEEP || x.used >= app.frame { break }
		key, _ := delete_key(&app.measures, x.key)
		delete(key)
	}
}

// A listing come: the sizes of its folders measured already, in their entries (measure_done's, for a new read).
// True when it changed one. (Nothing measured: no pass; each folder's path made in one buffer, not one allocation each.)
measures_apply :: proc(app: ^App, l: ^fs.Listing) -> (changed: bool) {
	if len(app.measures) == 0 { return }
	key := make([dynamic]u8, context.temp_allocator)
	append(&key, fs.join(l.path, "x", context.temp_allocator))
	parent := len(key) - 1   // (fs.join's own separator kept: the folder's path, then the name)
	for &e in l.entries {
		if e.kind != .Directory { continue }
		resize(&key, parent)
		append(&key, e.name)
		m, ok := app.measures[string(key[:])]
		if ok && m.done && m.mtime == e.mtime && e.size != m.bytes {
			e.size = m.bytes
			changed = true
		}
	}
	return
}

MEASURES_RESORT_MS :: 250

// Before a build: the tabs sorted by size whose folders were measured since, sorted again (once a frame, whatever
// the number of measures come).
measures_resort :: proc(app: ^App) {
	// (at most every MEASURES_RESORT_MS: measures come by hundreds, a sort of a large folder is not each frame's)
	now := ui.now_ms()
	if now - app.measures_sorted_at < MEASURES_RESORT_MS {
		for p in app.panels { for t in p.tabs { if t.resort_due { ui.wake_within(&app.main.state, int(MEASURES_RESORT_MS - (now - app.measures_sorted_at)) + 1); return } } }
		return
	}
	for p in app.panels {
		for t in p.tabs {
			if !t.resort_due { continue }
			app.measures_sorted_at = now
			t.resort_due = false
			folder_resort(&t.folder)
		}
	}
}
