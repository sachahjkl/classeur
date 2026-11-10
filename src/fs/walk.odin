package fs

// The flat view of a tree (File Pilot's search): every entry under a folder in one listing, each named by its path from
// that folder ("Projects/site/index.html"). Folders are read by several threads that share a queue of the folders still to
// read; links to folders are listed, not followed. The walk hands what it found so far to `progress` as it goes, so that
// a search shows its results while it reads.

import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// The threads that read the folders: listing a folder waits on the disk, several hide each other's waits.
WALK_THREADS :: 4

// How often `progress` gets what was found since its last call.
WALK_PROGRESS_MS :: 200

// What the walk hands to `progress`: the entries found since its last call, their names in `batch`'s arena (the caller
// takes them: the batch is the caller's, `listing_destroy` it).
Walk_Progress :: proc(user: rawptr, batch: ^Listing)

@(private = "file")
Walk :: struct {
	l:       ^Listing,
	root:    string,
	count:   ^int,
	stop:    proc(user: rawptr) -> bool,
	user:    rawptr,
	lock:    sync.Mutex,
	wake:    sync.Cond,
	pending: [dynamic]string,   // relative paths still to read, in l's arena
	busy:    int,               // threads reading a folder now
	done:    bool,              // nothing pending and nobody reading: every thread leaves
	first:   bool,              // the root is not read yet (its error is the walk's)
}

// Reads every entry under `root` into `l` (made empty first). `count` (atomic) grows as entries are read, for a
// progress; the walk ends early when `stop` says so (its error is then .Cancelled). A folder that cannot be read is
// skipped. `progress`, when given, is called on the caller's thread every WALK_PROGRESS_MS with the entries found since.
walk :: proc(l: ^Listing, root: string, count: ^int = nil, stop: proc(user: rawptr) -> bool = nil, user: rawptr = nil, progress: Walk_Progress = nil) -> Error {
	listing_reset(l)
	l.path = keep_name(l, root)
	w := Walk{l = l, root = root, count = count, stop = stop, user = user, first = true}
	w.pending = make([dynamic]string, context.allocator)
	defer delete(w.pending)
	append(&w.pending, "")
	// the root first, alone: its error is the walk's, and the threads start with its folders
	walk_one(&w)
	if l.error != .None { return l.error }
	threads: [WALK_THREADS]^thread.Thread
	// (each thread with a context of its own: its temporary memory is not the caller's)
	for &th in threads { th = thread.create_and_start_with_data(&w, walk_thread) }
	given := 0
	for {
		sync.mutex_lock(&w.lock)
		finished := w.done
		sync.mutex_unlock(&w.lock)
		if finished { break }
		time.sleep(WALK_PROGRESS_MS * time.Millisecond)
		if progress != nil { given = walk_progress(&w, given, progress) }
	}
	for th in threads {
		if th == nil { continue }
		thread.join(th)
		thread.destroy(th)
	}
	if stop != nil && stop(user) { return .Cancelled }
	return .None
}

// Hands the entries found since `given` to `progress`, copied (the listing grows meanwhile). The new `given`.
@(private = "file")
walk_progress :: proc(w: ^Walk, given: int, progress: Walk_Progress) -> int {
	batch: Listing
	sync.mutex_lock(&w.lock)
	n := len(w.l.entries)
	if n > given {
		batch.path = keep_name(&batch, w.l.path)
		reserve(&batch.entries, n - given)
		for e in w.l.entries[given:n] {
			x := e
			x.name = keep_name(&batch, e.name)
			append(&batch.entries, x)
		}
	}
	sync.mutex_unlock(&w.lock)
	if n > given { progress(w.user, &batch) } else { listing_destroy(&batch) }
	return n
}

@(private = "file")
walk_thread :: proc(data: rawptr) {
	w := (^Walk)(data)
	for walk_one(w) { free_all(context.temp_allocator) }
}

// Reads one folder of the queue (waiting for one while others are being read). False: the walk is over.
@(private = "file")
walk_one :: proc(w: ^Walk) -> bool {
	sync.mutex_lock(&w.lock)
	for len(w.pending) == 0 && w.busy > 0 && !w.done { sync.cond_wait(&w.wake, &w.lock) }
	if w.done || len(w.pending) == 0 || (w.stop != nil && w.stop(w.user)) {
		w.done = true
		sync.cond_broadcast(&w.wake)
		sync.mutex_unlock(&w.lock)
		return false
	}
	rel := pop(&w.pending)
	first := w.first
	w.first = false
	w.busy += 1
	sync.mutex_unlock(&w.lock)

	one: Listing
	defer listing_destroy(&one)
	dir := rel == "" ? w.root : join(w.root, rel, context.temp_allocator)
	err := list(&one, dir)

	sync.mutex_lock(&w.lock)
	defer sync.mutex_unlock(&w.lock)
	w.busy -= 1
	defer sync.cond_broadcast(&w.wake)
	if err != .None {
		if first { w.l.error = err; w.done = true }
		return !first
	}
	for e in one.entries {
		x := e
		x.name = rel == "" ? keep_name(w.l, e.name) : keep_name(w.l, strings.concatenate({rel, SEPARATOR_STRING, e.name}, context.temp_allocator))
		append(&w.l.entries, x)
		if e.kind == .Directory && .Link not_in e.flags { append(&w.pending, x.name) }
	}
	if w.count != nil { sync.atomic_add(w.count, len(one.entries)) }
	// (the root alone read and nothing below it: over)
	if len(w.pending) == 0 && w.busy == 0 { w.done = true }
	return true
}
