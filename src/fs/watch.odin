package fs

// Watching folders: a thread of the program waits in `watch_wait` until something changes in one of the folders it was
// given (`watch_set`, from any thread), and gets their paths. Changes that come close together come as one: after the
// first, the wait goes on until none came for WATCH_QUIET_MS (at most WATCH_MAX_MS), so that a copy of a thousand files
// reads the folder a few times, not a thousand. The system's part is in watch_<os>.odin.

import "core:strings"
import "core:sync"

WATCH_QUIET_MS :: 120
WATCH_MAX_MS   :: 600

Watch :: struct {
	mutex:   sync.Mutex,
	wanted:  [dynamic]string,   // owned: the folders to watch, as last set
	changed: bool,              // `wanted` changed since the watching thread applied it
	closing: bool,
	native:  Watch_Native,
}

watch_open :: proc(w: ^Watch) -> bool { return watch_open_native(w) }

// Ends the wait of the watching thread (it returns closed = true); call watch_close after that thread ended.
watch_stop :: proc(w: ^Watch) {
	sync.mutex_lock(&w.mutex)
	w.closing = true
	sync.mutex_unlock(&w.mutex)
	watch_wake_native(w)
}

watch_close :: proc(w: ^Watch) {
	watch_close_native(w)
	for p in w.wanted { delete(p) }
	delete(w.wanted)
}

// The folders to watch from now on (the others are no longer watched).
watch_set :: proc(w: ^Watch, paths: []string) {
	sync.mutex_lock(&w.mutex)
	for p in w.wanted { delete(p) }
	clear(&w.wanted)
	for p in paths { append(&w.wanted, strings.clone(p)) }
	w.changed = true
	sync.mutex_unlock(&w.mutex)
	watch_wake_native(w)
}

// The wanted folders, if they changed since the last call (the watching thread's copy, in `allocator`).
@(private)
watch_take_wanted :: proc(w: ^Watch, allocator := context.temp_allocator) -> (paths: []string, changed, closing: bool) {
	sync.mutex_lock(&w.mutex)
	defer sync.mutex_unlock(&w.mutex)
	if w.closing { return nil, false, true }
	if !w.changed { return nil, false, false }
	w.changed = false
	out := make([]string, len(w.wanted), allocator)
	for p, i in w.wanted { out[i] = strings.clone(p, allocator) }
	return out, true, false
}
