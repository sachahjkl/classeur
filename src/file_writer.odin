package classeur

// The files the program writes as it runs (the session, the preferences, the layouts, the Setup's answer), written on a
// worker: the interface's thread never waits for a disk. One write at a time per file, the latest text wins (two workers
// writing at once could rename an older text over a newer one): the task takes what is pending until nothing is; a new
// text replaces a pending one. The interface's thread only swaps the pending text under `mutex`, never held for a write.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"
import "fs"

File_Writer :: struct {
	mutex:   sync.Mutex,
	writing: sync.Mutex,                  // held while a text is taken and written: the writes keep their order
	write:   proc(path, text: string),    // what writes a text (nil: file_write)
	path:    string,                      // owned (heap): where the pending text goes
	text:    string,                      // owned (heap): the text to write next
	due:     bool,                        // a text is pending (an empty one is a text too: every layout deleted)
	running: bool,                        // a task is queued or writing
}

// `text` written to `path` on a worker of `pool`.
file_writer_put :: proc(w: ^File_Writer, pool: ^Pool, path, text: string) {
	sync.mutex_lock(&w.mutex)
	pending_set(w, path, text)
	start := !w.running
	w.running = true
	sync.mutex_unlock(&w.mutex)
	if start { pool_submit(pool, file_writer_run, w) }
}

// `text` written to `path` now, on this thread, in place of what is pending (the window closes: the workers stopped).
file_writer_now :: proc(w: ^File_Writer, path, text: string) {
	sync.mutex_lock(&w.mutex)
	pending_set(w, path, text)
	sync.mutex_unlock(&w.mutex)
	file_writer_flush(w)
}

// What is pending written now, on this thread (the window closes: a task queued was dropped with the workers).
file_writer_flush :: proc(w: ^File_Writer) {
	for file_writer_step(w, task = false) {}
}

file_writer_free :: proc(w: ^File_Writer) {
	heap := runtime.heap_allocator()
	delete(w.path, heap)
	delete(w.text, heap)
	w^ = {}
}

// (written beside, then renamed over: a crash while writing leaves the last text whole)
file_write :: proc(path, text: string) {
	_ = os.make_directory_all(fs.parent(path))
	tmp := strings.concatenate({path, ".new"}, context.temp_allocator)
	if os.write_entire_file(tmp, transmute([]u8)text) != nil { return }
	_ = os.rename(tmp, path)
}

// (under `mutex`)
@(private = "file")
pending_set :: proc(w: ^File_Writer, path, text: string) {
	heap := runtime.heap_allocator()
	delete(w.path, heap)
	delete(w.text, heap)
	w.path, w.text, w.due = strings.clone(path, heap), strings.clone(text, heap), true
}

@(private = "file")
file_writer_run :: proc(data: rawptr) {
	w := (^File_Writer)(data)
	for file_writer_step(w, task = true) {}
}

// Writes the pending text, if any. False: none was (`task`: the task ends, `running` cleared under the same lock).
@(private = "file")
file_writer_step :: proc(w: ^File_Writer, task: bool) -> bool {
	sync.mutex_lock(&w.writing)
	defer sync.mutex_unlock(&w.writing)
	sync.mutex_lock(&w.mutex)
	if !w.due {
		if task { w.running = false }
		sync.mutex_unlock(&w.mutex)
		return false
	}
	path, text := w.path, w.text
	w.path, w.text, w.due = "", "", false
	sync.mutex_unlock(&w.mutex)
	write := w.write
	if write == nil { write = file_write }
	write(path, text)
	heap := runtime.heap_allocator()
	delete(path, heap)
	delete(text, heap)
	return true
}
