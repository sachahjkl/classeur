package classeur

// The folders of the tabs are watched (fs.Watch, on a thread of its own): a change made by any program reads the folder
// again, with the cursor and the selection kept. Each frame the interface gives the watcher the folders of its tabs
// when they changed.

import "core:slice"
import "core:strings"
import "core:thread"
import "gt:ui"
import "fs"

Folder_Watch :: struct {
	watch:  fs.Watch,
	thread: ^thread.Thread,
	on:     bool,
	given:  [dynamic]string,   // owned: what the watcher was given last (the interface's copy)
	app:    ^App,
}

watcher_start :: proc(app: ^App) {
	w := &app.watch
	w.app = app
	if !fs.watch_open(&w.watch) { return }
	w.on = true
	w.thread = thread.create_and_start_with_data(w, watcher_work)
}

watcher_stop :: proc(app: ^App) {
	w := &app.watch
	if w.on {
		fs.watch_stop(&w.watch)
		thread.join(w.thread)
		thread.destroy(w.thread)
		fs.watch_close(&w.watch)
	}
	for p in w.given { delete(p) }
	delete(w.given)
	w^ = {}
}

// The folders of every tab, given to the watcher when they are not what it has.
watcher_update :: proc(app: ^App) {
	w := &app.watch
	if !w.on { return }
	paths := make([dynamic]string, context.temp_allocator)
	for p in app.panels {
		for t in p.tabs { if !slice.contains(paths[:], t.path) { append(&paths, t.path) } }
	}
	slice.sort(paths[:])
	if slice.equal(paths[:], w.given[:]) { return }
	for p in w.given { delete(p) }
	clear(&w.given)
	for p in paths { append(&w.given, strings.clone(p)) }
	fs.watch_set(&w.watch, paths[:])
}

@(private = "file")
watcher_work :: proc(data: rawptr) {
	w := (^Folder_Watch)(data)
	for {
		changed, closed := fs.watch_wait(&w.watch)
		if closed { return }
		for p in changed {
			c := new(Changed)
			c^ = {app = w.app, path = strings.clone(p)}
			if !ui.post(&w.app.main.state, folder_changed, c) { changed_free(c) }
		}
		free_all(context.temp_allocator)
	}
}

@(private = "file")
Changed :: struct {
	app:  ^App,
	path: string,   // owned
}

@(private = "file")
changed_free :: proc(c: ^Changed) {
	delete(c.path)
	free(c)
}

// On the interface's thread: the tabs on that folder read it again (a tab reading it: once its read comes, load_done).
@(private = "file")
folder_changed :: proc(data: rawptr, word: u64) {
	c := (^Changed)(data)
	defer changed_free(c)
	for p in c.app.panels {
		for t in p.tabs {
			if t.path != c.path { continue }
			if t.loading { t.reload_due = true } else { tab_load(c.app, t) }
		}
	}
}
