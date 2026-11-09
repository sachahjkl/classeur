package fs

// Windows: a change notification per folder (names, sizes, times; not its subfolders), waited for with an event that
// ends a wait when the folders to watch change or the program ends. A wait takes 64 handles at most: the first 63
// folders are watched.

import "core:strings"
import win "core:sys/windows"
import "core:time"

@(private = "file")
WATCH_MAX_FOLDERS :: 63
@(private = "file")
NOTIFY_FILTER :: win.FILE_NOTIFY_CHANGE_FILE_NAME | win.FILE_NOTIFY_CHANGE_DIR_NAME | win.FILE_NOTIFY_CHANGE_SIZE | win.FILE_NOTIFY_CHANGE_LAST_WRITE | win.FILE_NOTIFY_CHANGE_ATTRIBUTES

Watch_Native :: struct {
	wake:    win.HANDLE,
	handles: [dynamic]win.HANDLE,   // owned by the watching thread
	paths:   [dynamic]string,       // the folder of each handle
}

@(private)
watch_open_native :: proc(w: ^Watch) -> bool {
	w.native.wake = win.CreateEventW(nil, false, false, nil)
	return w.native.wake != nil
}

@(private)
watch_close_native :: proc(w: ^Watch) {
	for h in w.native.handles { win.FindCloseChangeNotification(h) }
	delete(w.native.handles)
	for p in w.native.paths { delete(p) }
	delete(w.native.paths)
	win.CloseHandle(w.native.wake)
}

@(private)
watch_wake_native :: proc(w: ^Watch) { win.SetEvent(w.native.wake) }

@(private = "file")
apply :: proc(w: ^Watch, wanted: []string) {
	n := &w.native
	for h in n.handles { win.FindCloseChangeNotification(h) }
	clear(&n.handles)
	for p in n.paths { delete(p) }
	clear(&n.paths)
	for p in wanted {
		if len(n.handles) == WATCH_MAX_FOLDERS { break }
		h := win.FindFirstChangeNotificationW((^u16)(rawptr(win.utf8_to_wstring(p, context.temp_allocator))), false, NOTIFY_FILTER)
		if h == win.INVALID_HANDLE_VALUE { continue }
		append(&n.handles, h)
		append(&n.paths, strings.clone(p))
	}
}

// Waits until a watched folder changes: their paths (`allocator`). closed: watch_stop was called.
watch_wait :: proc(w: ^Watch, allocator := context.temp_allocator) -> (changed: []string, closed: bool) {
	n := &w.native
	found := make(map[string]bool, 8, context.temp_allocator)
	first: time.Tick
	for {
		if wanted, now, closing := watch_take_wanted(w); closing {
			return nil, true
		} else if now {
			apply(w, wanted)
		}
		timeout: win.DWORD = win.INFINITE
		if len(found) > 0 {
			waited := time.duration_milliseconds(time.tick_since(first))
			if waited >= WATCH_MAX_MS { break }
			timeout = win.DWORD(min(WATCH_QUIET_MS, WATCH_MAX_MS - waited))
		}
		all := make([]win.HANDLE, len(n.handles) + 1, context.temp_allocator)
		all[0] = n.wake
		copy(all[1:], n.handles[:])
		r := win.WaitForMultipleObjects(win.DWORD(len(all)), raw_data(all), false, timeout)
		if r == win.WAIT_TIMEOUT { break }
		at := int(r - win.WAIT_OBJECT_0)
		if at < 0 || at >= len(all) { return nil, true }
		if at == 0 { continue }   // (woken: the wanted folders or the end)
		if len(found) == 0 { first = time.tick_now() }
		found[n.paths[at - 1]] = true
		win.FindNextChangeNotification(n.handles[at - 1])
	}
	out := make([]string, len(found), allocator)
	i := 0
	for p in found {
		out[i] = strings.clone(p, allocator)
		i += 1
	}
	return out, false
}
