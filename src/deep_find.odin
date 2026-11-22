package classeur

// Deep search for GoTo (Ctrl+G), the path field (Ctrl+L), and the command palette's '/' files source
// (src/md/features/goto.md): backed by gt:filesearch (fff-search), providing typo-tolerant matching, live watching,
// and shared LMDB frecency. Every open, search, frecency update, and close runs on a worker; the interface thread
// reads only the last answer.

import "base:runtime"
import "core:strings"
import filesearch "gt:filesearch"
import "gt:platform"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

// Rows kept per answer, best first.
DEEP_ROWS :: 60
// Overfetch factor so filtering hidden entries still leaves up to DEEP_ROWS visible results.
DEEP_SEARCH_OVERFETCH :: 2
// Poll cadence (ms) while the background scan is still running.
DEEP_POLL_MS :: 100
// Initial wait on the open worker: small/medium trees finish before the first frame; large trees return early and
// stream results while scanning.
DEEP_OPEN_WAIT_MS :: 250
// Headless tests run without a watcher and wait for the fixture tree to finish scanning deterministically.
DEEP_HEADLESS_WAIT_MS :: 5000
// Shared vendor frecency folder under XDG_DATA_HOME / LocalAppData (gui_toolkit file-search.md).
FILESEARCH_FRECENCY_FOLDER :: "FromentSoftware" + platform.USER_DIR_SEPARATOR + "filesearch"

// One row of an answer: the path relative to the index's root, and the letters matched in it.
Deep_Row :: struct {
	path:   string,           // owned (heap)
	kind:   fs.Kind,
	ranges: []ui.Fuzzy_Range, // owned (heap)
	score:  int,
}

// Interface-thread state (App.deep): one open filesearch.Index for `root`, the in-flight query, and the last answer.
Deep_Search :: struct {
	root:          string,             // owned (heap): folder indexed (or being opened)
	fs_index:      filesearch.Index,   // 0 while opening or reset
	open_serial:   u64,                // monotonic serial of open requests (stale opens close themselves)
	opening:       bool,
	reading:       bool,               // initial scan still running
	done:          bool,               // initial scan finished
	read:          int,                // entries scanned so far
	serial:        u64,                // monotonic serial of search requests (stale answers are dropped)
	in_flight:     bool,
	last_match_ms: f64,                // ui.now_ms() of the last search while scanning
	asked:         string,             // owned (heap): last query sent
	asked_hidden:  bool,
	rows:          [dynamic]Deep_Row,  // owned (heap): last answer
	rows_for:      string,             // owned (heap): query that `rows` answers
}

@(private = "file")
deep_rows_free :: proc(rows: ^[dynamic]Deep_Row) {
	heap := runtime.heap_allocator()
	for r in rows { delete(r.path, heap); delete(r.ranges, heap) }
	clear(rows)
}

@(private = "file")
deep_close_async :: proc(app: ^App, idx: filesearch.Index) {
	if idx == 0 { return }
	Close_Job :: struct { idx: filesearch.Index }
	j := new(Close_Job, runtime.heap_allocator())
	j.idx = idx
	if !tasks.add(&app.pool, proc(data: rawptr) {
		j := (^Close_Job)(data)
		filesearch.close(j.idx)
		free(j, runtime.heap_allocator())
	}, j) {
		filesearch.close(j.idx)
		free(j, runtime.heap_allocator())
	}
}

// Releases the current index (closing it on a worker) and clears any cached rows.
deep_reset :: proc(app: ^App) {
	d := &app.deep
	ui.palette_files_set(&app.palette.files, 0, "")
	if d.fs_index != 0 {
		deep_close_async(app, d.fs_index)
		d.fs_index = 0
	}
	d.open_serial += 1
	d.opening, d.reading, d.done, d.read = false, false, false, 0
	d.serial += 1
	d.in_flight = false
	d.last_match_ms = 0
	deep_rows_free(&d.rows)
	heap := runtime.heap_allocator()
	delete(d.root, heap)
	delete(d.asked, heap)
	delete(d.rows_for, heap)
	d.root, d.asked, d.rows_for = "", "", ""
}

// Called during app_free after worker pools have stopped.
deep_free :: proc(app: ^App) {
	d := &app.deep
	if d.fs_index != 0 {
		filesearch.close(d.fs_index)
		d.fs_index = 0
	}
	deep_rows_free(&d.rows)
	delete(d.rows)
	heap := runtime.heap_allocator()
	delete(d.root, heap)
	delete(d.asked, heap)
	delete(d.rows_for, heap)
	app.deep = {}
}

// Ensures a gt:filesearch index is open (or opening) for `root`, shared with the palette's '/' files source.
deep_ensure_index :: proc(app: ^App, root: string) {
	if root == "" || !filesearch.available() { return }
	d := &app.deep
	if d.root == root && (d.fs_index != 0 || d.opening) { return }
	deep_reset(app)
	heap := runtime.heap_allocator()
	d.root = strings.clone(root, heap)
	d.opening = true
	d.reading = true
	d.open_serial += 1
	frecency := ""
	if !app.headless { frecency = platform.user_dir(.Data, FILESEARCH_FRECENCY_FOLDER, context.temp_allocator) }
	job := new(Deep_Open_Job, heap)
	job^ = {
		app          = app,
		serial       = d.open_serial,
		root         = strings.clone(root, heap),
		frecency_dir = frecency != "" ? strings.clone(frecency, heap) : "",
		watch        = !app.headless,
	}
	if !tasks.add(&app.pool, deep_open_run, job) {
		d.opening, d.reading, d.done = false, false, true
		deep_open_free(job)
	}
}

// Records that the user opened `path` in the shared LMDB frecency store on a background chore.
deep_note_opened :: proc(app: ^App, path: string) {
	if app.headless || app.deep.fs_index == 0 || path == "" { return }
	ui.palette_files_opened(&app.main.state, app.deep.fs_index, path)
}

// True once the index for the active query has finished its initial scan and answered `d.asked` (tests).
deep_ready :: proc(app: ^App) -> bool {
	d := &app.deep
	return d.fs_index != 0 && !d.opening && !d.in_flight && d.done && d.asked != "" && d.rows_for == d.asked
}

// Rows matching `query` below `root` from the last answer; opens the index and dispatches matches on workers.
deep_rows :: proc(app: ^App, root, query: string) -> (rows: []Deep_Row, reading: bool, read: int) {
	d := &app.deep
	if root == "" || query == "" { return nil, false, 0 }
	deep_ensure_index(app, root)
	if d.opening {
		ui.wake_within(&app.main.state, DEEP_POLL_MS)
		return d.rows[:], true, d.read
	}
	if d.fs_index == 0 { return nil, false, 0 }

	now := ui.now_ms()
	stale_query := query != d.asked || app.show_hidden != d.asked_hidden
	scan_poll := d.reading && (now - d.last_match_ms >= DEEP_POLL_MS)
	if !d.in_flight && (stale_query || scan_poll) {
		deep_match_ask(app, query, now)
	}
	if d.reading { ui.wake_within(&app.main.state, DEEP_POLL_MS) }
	return d.rows[:], d.reading, d.read
}

////////////////////////////////
// Worker: opening the index

@(private = "file")
Deep_Open_Job :: struct {
	app:          ^App,
	serial:       u64,
	root:         string,
	frecency_dir: string,
	watch:        bool,
	idx:          filesearch.Index,
	scanning:     bool,
	scanned:      int,
}

@(private = "file")
deep_open_free :: proc(j: ^Deep_Open_Job) {
	heap := runtime.heap_allocator()
	delete(j.root, heap)
	delete(j.frecency_dir, heap)
	free(j, heap)
}

@(private = "file")
deep_open_run :: proc(data: rawptr) {
	j := (^Deep_Open_Job)(data)
	idx, err := filesearch.open({
		root         = j.root,
		frecency_dir = j.frecency_dir,
		watch        = j.watch,
		allow_home   = true,
	})
	if err == .None && idx != 0 {
		j.idx = idx
		ready := filesearch.wait_ready(idx, j.watch ? DEEP_OPEN_WAIT_MS : DEEP_HEADLESS_WAIT_MS)
		st := filesearch.state(idx)
		j.scanning = !ready && st.scanning
		j.scanned = st.scanned
	}
	if !ui.post(&j.app.main.state, deep_open_done, j) {
		filesearch.close(j.idx)
		deep_open_free(j)
	}
}

@(private = "file")
deep_open_done :: proc(data: rawptr, word: u64) {
	j := (^Deep_Open_Job)(data)
	app := j.app
	d := &app.deep
	defer deep_open_free(j)
	if j.serial != d.open_serial {
		deep_close_async(app, j.idx)
		return
	}
	d.opening = false
	d.fs_index = j.idx
	d.reading = j.idx != 0 && j.scanning
	d.done = j.idx == 0 || !j.scanning
	d.read = j.scanned
	ui.palette_files_set(&app.palette.files, d.fs_index, d.root)
	app_frames(app)
}

////////////////////////////////
// Worker: querying the index

@(private = "file")
Deep_Match :: struct {
	app:      ^App,
	idx:      filesearch.Index,
	root:     string,
	query:    string,
	hidden:   bool,
	serial:   u64,
	scanning: bool,
	scanned:  int,
	rows:     [dynamic]Deep_Row,
}

@(private = "file")
deep_match_free :: proc(m: ^Deep_Match) {
	heap := runtime.heap_allocator()
	deep_rows_free(&m.rows)
	delete(m.rows)
	delete(m.root, heap)
	delete(m.query, heap)
	free(m, heap)
}

@(private = "file")
deep_match_ask :: proc(app: ^App, query: string, now: f64) {
	d := &app.deep
	heap := runtime.heap_allocator()
	delete(d.asked, heap)
	d.asked = strings.clone(query, heap)
	d.asked_hidden = app.show_hidden
	d.last_match_ms = now
	d.serial += 1
	d.in_flight = true
	m := new(Deep_Match, heap)
	m^ = {
		app    = app,
		idx    = d.fs_index,
		root   = strings.clone(d.root, heap),
		query  = strings.clone(query, heap),
		hidden = app.show_hidden,
		serial = d.serial,
	}
	if !tasks.add(&app.pool, deep_match_run, m) {
		d.in_flight = false
		deep_match_free(m)
	}
}

// Whether `rel` is hidden itself or sits inside a hidden folder (starts with '.').
@(private = "file")
deep_hidden :: proc(rel: string) -> bool {
	if strings.has_prefix(rel, ".") { return true }
	for i in 0 ..< len(rel) - 1 {
		if fs.is_separator(rel[i]) && rel[i + 1] == '.' { return true }
	}
	return false
}

@(private = "file")
deep_ranges :: proc(query, rel: string, hit_ranges: []filesearch.Match_Range, by_path: bool, allocator: runtime.Allocator) -> []ui.Fuzzy_Range {
	if len(hit_ranges) > 0 {
		out := make([]ui.Fuzzy_Range, len(hit_ranges), allocator)
		for r, i in hit_ranges { out[i] = {r[0], r[1]} }
		return out
	}
	hay := by_path ? rel : fs.base(rel)
	_, ranges, ok := ui.fuzzy_score(query, hay, allocator)
	if !ok { return nil }
	if !by_path {
		at := len(rel) - len(hay)
		for &r in ranges { r[0] += at; r[1] += at }
	}
	return ranges
}

@(private = "file")
deep_match_run :: proc(data: rawptr) {
	m := (^Deep_Match)(data)
	heap := runtime.heap_allocator()
	query := strings.trim_space(m.query)
	by_path := false
	for i in 0 ..< len(query) { if fs.is_separator(query[i]) { by_path = true; break } }
	show_hidden := m.hidden || strings.has_prefix(query, ".")

	st := filesearch.state(m.idx)
	m.scanning = st.scanning
	m.scanned = st.scanned

	// Exact relative path that exists comes first, even before the initial scan reaches it.
	exact := ""
	if by_path {
		rel := strings.trim_right(query, "/\\")
		if info, ok := fs.stat(fs.join(m.root, rel, context.temp_allocator)); ok {
			exact = fs.clean(rel, context.temp_allocator)
			_, ranges, _ := ui.fuzzy_score(query, exact, heap)
			append(&m.rows, Deep_Row{path = strings.clone(exact, heap), kind = info.kind, ranges = ranges, score = max(int)})
		}
	}

	if query != "" {
		page, err := filesearch.search(m.idx, query, {limit = DEEP_ROWS * DEEP_SEARCH_OVERFETCH, dirs = true}, context.temp_allocator)
		if err == .None {
			defer filesearch.page_destroy(&page, context.temp_allocator)
			for hit in page.hits {
				if len(m.rows) >= DEEP_ROWS { break }
				if !show_hidden && deep_hidden(hit.path) { continue }
				if exact != "" && fs.clean(hit.path, context.temp_allocator) == exact { continue }
				ranges := deep_ranges(query, hit.path, hit.ranges, by_path, heap)
				kind: fs.Kind = hit.dir ? .Directory : .File
				append(&m.rows, Deep_Row{
					path   = strings.clone(hit.path, heap),
					kind   = kind,
					ranges = ranges,
					score  = int(hit.score),
				})
			}
		}
	}
	if !ui.post(&m.app.main.state, deep_match_done, m) { deep_match_free(m) }
}

@(private = "file")
deep_match_done :: proc(data: rawptr, word: u64) {
	m := (^Deep_Match)(data)
	app := m.app
	d := &app.deep
	defer deep_match_free(m)
	if m.serial != d.serial { return }
	heap := runtime.heap_allocator()
	d.in_flight = false
	d.reading = m.scanning
	d.done = !m.scanning
	d.read = m.scanned
	deep_rows_free(&d.rows)
	d.rows, m.rows = m.rows, d.rows
	delete(d.rows_for, heap)
	d.rows_for = strings.clone(m.query, heap)
	app_frames(app)
}
