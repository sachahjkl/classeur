package classeur

// The places that are not plain paths (fs/locations.odin): a file's URI, the trash, a share of the network. Whatever
// opens a folder (the command line, a second start, the address bar, GoTo, a bookmark) goes through tab_go and tab_open,
// which read them here. A share that is not mounted is mounted on a worker (Linux: gvfs, which may ask for a password
// through the session's agent); the tab goes there once it is, or the reason it is not is said.

import "core:strings"
import "gt:ui"
import "fs"

// The path `text` stands for; ok = false: a share being mounted (tab `tab` goes there when it is) or a place this
// system does not reach (said).
location_path :: proc(app: ^App, text: string, tab: u64) -> (path: string, ok: bool) {
	r, e := fs.location_resolve(text, context.temp_allocator)
	switch e {
	case .None:
		return r.path, true
	case .Not_Mounted:
		share_mount_start(app, r.uri, tab)
	case .Unsupported:
		say(app, "%s: this system reaches no such place by a path.", text)
	case .Not_A_Location:
		say(app, "%s: not a place classeur knows.", text)
	}
	return "", false
}

@(private = "file")
Mounting :: struct {
	app: ^App,
	uri: string,   // owned
	tab: u64,
	ok:  bool,
	why: string,   // owned
}

// Mounts a share on a worker, then brings tab `tab` there (one mount of a URI at a time).
@(private = "file")
share_mount_start :: proc(app: ^App, uri: string, tab: u64) {
	for u in app.mounting { if u == uri { return } }
	append(&app.mounting, strings.clone(uri))
	say(app, "Connecting to %s…", uri)
	m := new(Mounting)
	m^ = {app = app, uri = strings.clone(uri), tab = tab}
	pool_submit(&app.pool, proc(data: rawptr) {
		m := (^Mounting)(data)
		ok, why := fs.share_mount(m.uri, context.temp_allocator)
		m.ok, m.why = ok, strings.clone(why)
		// (the window gone meanwhile: nobody to tell)
		if !ui.post(&m.app.main.state, share_mounted, m, 0) {
			delete(m.uri)
			delete(m.why)
			free(m)
		}
	}, m)
}

// Back on the interface's thread: the share mounted (its tab goes there, the sidebar lists it) or why not.
@(private = "file")
share_mounted :: proc(data: rawptr, word: u64) {
	m := (^Mounting)(data)
	app := m.app
	defer {
		delete(m.uri)
		delete(m.why)
		free(m)
	}
	for u, i in app.mounting {
		if u == m.uri {
			delete(u)
			ordered_remove(&app.mounting, i)
			break
		}
	}
	if !m.ok {
		say(app, "%s: %s", m.uri, m.why)
		return
	}
	places_load(app)
	r, e := fs.location_resolve(m.uri, context.temp_allocator)
	if e != .None {
		say(app, "%s is mounted, but classeur finds no folder for it.", m.uri)
		return
	}
	if t := find_tab(app, m.tab); t != nil { tab_go(app, t, r.path) }
	app_frames(app)
}

// The name a share's folder shows (a tab's title, the first crumb): its URI's ("docs on nas"); "" when the path is
// not a share's root.
share_title :: proc(path: string) -> string {
	root, uri, ok := fs.share_root(path, context.temp_allocator)
	if !ok || root != path { return "" }
	return fs.share_label(uri, context.temp_allocator)
}
