package classeur

// What a folder holds, all the way down: its folders, its files, their bytes (File Pilot's Folders, Files and Size
// columns). The folders of the tabs shown are measured on a pool of their own (a measure of a large tree must not
// delay the reading of a folder), nearest first; a measure no tab shows any more is dropped before it starts. The
// results are kept by path and folder date: a folder whose date changed is measured again.

import "core:strings"
import "core:sync"
import "gt:ui"
import "fs"

MEASURE_THREADS :: 2

Measure :: struct {
	folders, files: i64,
	bytes:          i64,
	mtime:          i64,    // the folder's date when it was measured
	done:           bool,   // false: asked, not yet come
}

@(private = "file")
Measure_Job :: struct {
	app:   ^App,
	path:  string,   // owned
	mtime: i64,
	gen:   u64,      // the generation it was asked in
	m:     Measure,
}

measures_free :: proc(app: ^App) {
	for k in app.measures { delete(k) }
	delete(app.measures)
}

// Asks the measures of the folders shown in `t` that are not known (or whose date changed).
measure_tab :: proc(app: ^App, t: ^Tab) {
	if !t.folder.loaded || t.folder.flat { return }   // (a flat listing holds its folders' content already)
	for i in t.folder.shown {
		e := t.folder.listing.entries[i]
		if e.kind != .Directory || .Link in e.flags { continue }
		path := fs.join(t.path, e.name, context.temp_allocator)
		if m, ok := app.measures[path]; ok && m.mtime == e.mtime { continue }
		if old_key, _ := delete_key(&app.measures, path); old_key != "" { delete(old_key) }
		app.measures[strings.clone(path)] = {mtime = e.mtime}
		job := new(Measure_Job)
		job^ = {app = app, path = strings.clone(path), mtime = e.mtime, gen = sync.atomic_load(&app.measure_gen)}
		pool_submit(&app.measure_pool, measure_run, job)
	}
}

// The tabs shown changed: the measures asked before and not started are dropped (measure_run sees the generation).
measure_forget_asked :: proc(app: ^App) {
	sync.atomic_add(&app.measure_gen, 1)
	gone := make([dynamic]string, context.temp_allocator)
	for k, m in app.measures { if !m.done { append(&gone, k) } }
	for k in gone {
		old_key, _ := delete_key(&app.measures, k)
		delete(old_key)
	}
	for p in app.panels { for t in p.tabs { t.measured = 0 } }
}

// Each frame: the measures of the tabs shown, once per read of their folder.
measure_update :: proc(app: ^App) {
	if !app.settings.measure_folders { return }
	for p in app.panels {
		t := panel_tab(p)
		if t == nil || t.loading || !t.folder.loaded || t.measured == t.serial { continue }
		t.measured = t.serial
		measure_tab(app, t)
	}
}

measure_of :: proc(app: ^App, t: ^Tab, e: fs.Entry) -> (Measure, bool) {
	m, ok := app.measures[fs.join(t.path, e.name, context.temp_allocator)]
	return m, ok && m.done
}

@(private = "file")
measure_run :: proc(data: rawptr) {
	job := (^Measure_Job)(data)
	if job.gen != sync.atomic_load(&job.app.measure_gen) {
		measure_free(job)
		return
	}
	walk(job, job.path)
	job.m.done = true
	if !ui.post(&job.app.main.state, measure_done, job) { measure_free(job) }
}

@(private = "file")
walk :: proc(job: ^Measure_Job, path: string) {
	if job.gen != sync.atomic_load(&job.app.measure_gen) { return }
	l: fs.Listing
	defer fs.listing_destroy(&l)
	if fs.list(&l, path) != .None { return }
	for e in l.entries {
		if e.kind == .Directory && .Link not_in e.flags {
			job.m.folders += 1
			walk(job, fs.join(path, e.name, context.temp_allocator))
		} else {
			job.m.files += 1
			if e.size > 0 { job.m.bytes += e.size }
		}
	}
}

@(private = "file")
measure_free :: proc(job: ^Measure_Job) {
	delete(job.path)
	free(job)
}

@(private = "file")
measure_done :: proc(data: rawptr, word: u64) {
	job := (^Measure_Job)(data)
	defer measure_free(job)
	app := job.app
	if job.gen != app.measure_gen { return }   // (an old ask: what it found may be stale)
	if m, ok := &app.measures[job.path]; ok && m.mtime == job.mtime {
		job.m.mtime = job.mtime
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
	}
}

// A listing come: the sizes of its folders measured already, in their entries (measure_done's, for a new read).
measures_apply :: proc(app: ^App, l: ^fs.Listing) {
	for &e in l.entries {
		if e.kind != .Directory { continue }
		m, ok := app.measures[fs.join(l.path, e.name, context.temp_allocator)]
		if ok && m.done && m.mtime == e.mtime { e.size = m.bytes }
	}
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
