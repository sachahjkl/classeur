package classeur

// classeur's state and acts in the toolkit's debug window (gui_toolkit docs/debug.md; Ctrl+Alt+Shift+D in a debug build,
// in the tools through the devtools): one panel per part of the program that keeps state, each with what it holds and
// acts that do the program's own work (a read, a cache dropped, a check), never a second path. The panels read only
// what the interface's thread owns; the jobs' counters are read as the jobs' view reads them (atomics). A release build
// compiles them away (debug.ENABLED).

import "core:fmt"
import "core:sync"
import "gt:debug"
import update "gt:update"
import "gt:ui"

// Once, as the window opens: the panels' procedures on its State, in the order of the window's tabs (a test gives a
// bare State).
debug_panels_register :: proc(s: ^ui.State, app: ^App) {
	debug.panel(s, "Tabs", debug_tabs, app)
	debug.panel(s, "Selection", debug_selection, app)
	debug.panel(s, "Thumbnails", debug_thumbnails, app)
	debug.panel(s, "Watcher", debug_watcher, app)
	debug.panel(s, "Undo", debug_undo, app)
	debug.panel(s, "File search", debug_file_search, app)
	debug.panel(s, "Jobs", debug_jobs, app)
	debug.panel(s, "Updates", debug_updates, app)
	debug.panel(s, "Look", debug_look, app)
}

// The tab shown: its folder, its read, its view; acts that read it again, or make it fail as a refused folder does.
@(private = "file")
debug_tabs :: proc(app: ^App) {
	debug.watch("panels", len(app.panels))
	debug.watch("tabs closed", len(app.closed_tabs))
	t := current_tab(app)
	if t == nil { debug.note("no tab"); return }
	f := &t.folder
	if debug.section("Folder") {
		debug.watch("path", t.path)
		debug.watch("loaded", f.loaded)
		debug.watch("loading", t.loading)
		debug.watch("error", f.listing.error)
		debug.watch("read ms", t.load_ms)
		debug.watch("serial", t.serial)
		debug.watch("entries", len(f.listing.entries))
		debug.watch("rows", len(f.shown))
		debug.watch("folders", f.folders)
		debug.watch("files", f.files)
		debug.watch("flat read", t.walk != nil)
		debug.watch("reload due", t.reload_due)
	}
	if debug.section("View") {
		debug.number("zoom", &t.zoom, lo = 0, hi = f64(len(ZOOMS) - 1))
		debug.watch("mode", tab_mode(t))
		debug.toggle("flat", &t.flat)
		debug.toggle("tree", &t.tree)
		if debug.choice("group", &t.group) { tab_load(app, t) }   // (the folder takes the tab's grouping at its read)
		debug.toggle("locked", &t.locked)
	}
	if debug.act("Read again") { tab_load(app, t) }
	if debug.act("Read every tab") { act_app_reload_all(app) }
	// (what a folder the system refuses shows: its empty state and its buttons; Try again reads it for real)
	if debug.act("Simulate a refused folder") {
		f.loaded = true
		f.listing.error = .Denied
	}
}

// The selection of the tab shown, its bytes, and the rectangle.
@(private = "file")
debug_selection :: proc(app: ^App) {
	t := current_tab(app)
	if t == nil { debug.note("no tab"); return }
	f := &t.folder
	debug.watch("selected", len(f.selected))
	debug.watch("cursor", f.sel)
	debug.watch("version", f.version)
	debug.watch("bytes", f.sel_bytes)
	debug.watch("bytes known", f.bytes_known && f.bytes_of == f.version)
	if debug.section("Rectangle") {
		debug.watch("active", app.band.active)
		debug.watch("waiting for a drag", app.band.pending)
		debug.watch("tab", app.band.tab)
	}
	if debug.act("Select all") { folder_select_all(f) }
	if debug.act("Select none") { folder_select_none(f) }
	if debug.act("Invert") { folder_invert_selection(f) }
}

// The grid's thumbnails: what the cache holds and asks; the system's thumbnails on or off, live.
@(private = "file")
debug_thumbnails :: proc(app: ^App) {
	c := &app.thumbs
	debug.watch("entries", len(c.entries))
	debug.watch("asked", len(c.by_ticket))
	debug.watch("waiting", len(c.waiting))
	debug.watch("bytes held", c.held)
	debug.watch("sent", c.sent)
	debug.watch("dropped as stale", c.skipped)
	debug.watch("system icons", len(app.icons_cache))
	// (the system's cache and thumbnailers: off in the tests; on, a card of any type asks the system)
	debug.toggle("system thumbnails", &app.system_thumbs)
	if debug.act("Clear") { act_app_thumbs_clear(app) }
}

// The folders the watcher follows; acts that give them again, or tell the tab shown that its folder changed.
@(private = "file")
debug_watcher :: proc(app: ^App) {
	w := &app.watch
	debug.watch("on", w.on)
	debug.watch("folders", len(w.given))
	for p, i in w.given { debug.watch(fmt.tprintf("%d", i), p) }
	// (the list compared empty: the next frame gives the watcher every folder again, as at the start)
	if debug.act("Give the folders again") {
		for p in w.given { delete(p) }
		clear(&w.given)
	}
	// (what a change the watcher saw does: the tab reads its folder, or again once its read comes)
	if debug.act("Simulate a change here") {
		if t := current_tab(app); t != nil {
			if t.loading { t.reload_due = true } else { tab_load(app, t) }
		}
	}
}

// What can be undone and done again, and the changes whose answer has not come.
@(private = "file")
debug_undo :: proc(app: ^App) {
	debug.watch("steps", len(app.undo))
	debug.watch("to do again", len(app.redo))
	debug.watch("answers due", app.answers_due)
	debug.watch("steps due", app.steps_due)
	if len(app.undo) > 0 { debug.watch("last", app.undo[len(app.undo) - 1].kind) }
	if debug.act("Undo") { act_undo(app) }
	if debug.act("Redo") { act_redo(app) }
}

// GoTo's index of the folder (gt:filesearch): what it reads and what it answered last.
@(private = "file")
debug_file_search :: proc(app: ^App) {
	d := &app.deep
	debug.watch("root", d.root)
	debug.watch("index", d.fs_index)
	debug.watch("opening", d.opening)
	debug.watch("scanning", d.reading)
	debug.watch("scanned", d.done)
	debug.watch("entries read", d.read)
	debug.watch("asked", d.asked)
	debug.watch("in flight", d.in_flight)
	debug.watch("rows", len(d.rows))
	if debug.act("Index the folder shown") {
		if t := current_tab(app); t != nil { deep_ensure_index(app, t.path) }
	}
	if debug.act("Drop the index") { deep_reset(app) }
}

// Copies, moves and the trash: each job as the jobs' view reads it.
@(private = "file")
debug_jobs :: proc(app: ^App) {
	debug.watch("jobs", len(app.jobs.list))
	for job in app.jobs.list {
		if debug.section(fmt.tprintf("%d %v", job.id, job.kind)) {
			debug.watch("state", Job_State(sync.atomic_load(&job.state)))
			debug.watch("files", fmt.tprintf("%d of %d", sync.atomic_load(&job.files_done), sync.atomic_load(&job.files_total)))
			debug.watch("bytes", fmt.tprintf("%d of %d", sync.atomic_load(&job.bytes_done), sync.atomic_load(&job.bytes_total)))
			debug.watch("to", job.dest)
		}
	}
	if debug.act("Cancel every job") { for job in app.jobs.list { job_cancel(job) } }
}

// The updater (none headless, nor in a window torn off): its phase and what it found.
@(private = "file")
debug_updates :: proc(app: ^App) {
	u := app.updates.updater
	if u == nil { debug.note("no updater in this window"); return }
	st := update.status(u)
	debug.watch("phase", st.phase)
	debug.watch("version", st.version)
	debug.watch("result", st.result)
	debug.watch("failed", st.failed)
	debug.watch("this version", APP_VERSION)
	if debug.act("Check now") { update.check_now(u) }
}

// What the program draws in its own way, tuned live.
@(private = "file")
debug_look :: proc(app: ^App) {
	debug.number("check ms", &app.check_ms, lo = 0, hi = 2000, step = 5)
	debug.watch("check ms default", CHECK_ANIM_MS)
	debug.watch("animations", ui.animations_on())
	debug.watch("frames", app.frame)
}
