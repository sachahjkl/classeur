package classeur

// The places that are not plain paths (fs/locations.odin): a file's URI, the trash, a share of the network. Whatever
// opens a folder (the command line, a second start, the address bar, GoTo, a bookmark) goes through tab_go and tab_open,
// which read them here. A share is found on a worker (Linux reads gvfs's folder and the mount table), and mounted there
// when it is not (Linux: gvfs, which may ask for a password through the session's agent); the tab goes there once it
// is, or the reason it is not is said.

import "core:strings"
import "gt:ui"
import "fs"

// The path `text` stands for; ok = false: a share being found or mounted (tab `tab` goes there when it is) or a place
// this system does not reach (said).
location_path :: proc(app: ^App, text: string, tab: u64) -> (path: string, ok: bool) {
	// (a share: its folder is asked of the mounts, which this thread never reads)
	if u, is_uri := fs.uri_parse(text); is_uri && fs.is_network_scheme(u.scheme) {
		share_open_start(app, strings.trim_space(text), tab)
		return "", false
	}
	r, e := fs.location_resolve(text, context.temp_allocator)
	location_say(app, text, e)
	return r.path, e == .None
}

// Why a place is not reached, said.
@(private = "file")
location_say :: proc(app: ^App, text: string, e: fs.Location_Error) {
	switch e {
	case .None, .Not_Mounted:
	case .Unsupported:
		say(app, "%s: this system reaches no such place by a path.", text)
	case .Not_A_Location:
		say(app, "%s: not a place classeur knows.", text)
	}
}

@(private = "file")
Share_Open :: struct {
	app:     ^App,
	text:    string,   // owned: the URI asked
	tab:     u64,
	path:    string,   // owned: its folder ("": not reached)
	e:       fs.Location_Error,
	mounted: bool,     // mounted by this task (the sidebar's shares read again)
	why:     string,   // owned: why the mount failed
}

// Finds a share's folder on a worker, mounting it first when it is not, then brings tab `tab` there (one task per URI
// at a time).
@(private = "file")
share_open_start :: proc(app: ^App, text: string, tab: u64) {
	for u in app.mounting { if u == text { return } }
	append(&app.mounting, strings.clone(text))
	app.answers_due += 1
	m := new(Share_Open)
	m^ = {app = app, text = strings.clone(text), tab = tab}
	pool_submit(&app.pool, proc(data: rawptr) {
		m := (^Share_Open)(data)
		r, e := fs.location_resolve(m.text, context.temp_allocator)
		if e == .Not_Mounted {
			// (the interface says it connects: a mount can take long, or wait for a password)
			_ = ui.post(&m.app.main.state, share_connecting, m, 0)
			ok, why := fs.share_mount(r.uri, context.temp_allocator)
			if ok {
				m.mounted = true
				r, e = fs.location_resolve(m.text, context.temp_allocator)
				if e == .Not_Mounted { why = "it is mounted, but classeur finds no folder for it" }
			}
			m.why = strings.clone(why)
		}
		m.path, m.e = strings.clone(r.path), e
		// (the window gone meanwhile: nobody to tell)
		if !ui.post(&m.app.main.state, share_opened, m, 0) { share_open_free(m) }
	}, m)
}

@(private = "file")
share_open_free :: proc(m: ^Share_Open) {
	delete(m.text)
	delete(m.path)
	delete(m.why)
	free(m)
}

// The share is not mounted: the worker mounts it.
@(private = "file")
share_connecting :: proc(data: rawptr, word: u64) {
	m := (^Share_Open)(data)
	say(m.app, "Connecting to %s…", m.text)
	app_frames(m.app)
}

// Back on the interface's thread: the share's folder (its tab goes there, the sidebar lists it when it was mounted) or
// why not.
@(private = "file")
share_opened :: proc(data: rawptr, word: u64) {
	m := (^Share_Open)(data)
	app := m.app
	defer share_open_free(m)
	app.answers_due -= 1
	for u, i in app.mounting {
		if u == m.text {
			delete(u)
			ordered_remove(&app.mounting, i)
			break
		}
	}
	if m.mounted { places_load(app) }
	if m.why != "" {
		say(app, "%s: %s", m.text, m.why)
		return
	}
	if m.e != .None {
		location_say(app, m.text, m.e)
		return
	}
	if t := find_tab(app, m.tab); t != nil { tab_go(app, t, m.path) }
	app_frames(app)
}
