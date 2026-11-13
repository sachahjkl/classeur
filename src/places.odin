package classeur

// The places of the sidebar: the person's folders (those that exist), then the volumes (fs.volumes). They are read on a
// worker (a stat per folder, the mount table, statfs per volume, the shares): the sidebar keeps the list it has until
// the new one comes.

import "core:strings"
import "gt:i18n"
import "gt:platform"
import tasks "gt:tasks"
import "gt:ui"
import "fs"

Place :: struct {
	name, path: string,   // owned
}

@(private = "file")
Known :: struct { folder: platform.Known_Folder, name: string }

// (a variable: i18n.later marks the names for the catalogue; tr as the worker names the places)
@(private = "file")
KNOWN := [?]Known{
	{.Home, i18n.later("Home")},
	{.Desktop, i18n.later("Desktop")},
	{.Documents, i18n.later("Documents")},
	{.Downloads, i18n.later("Downloads")},
	{.Pictures, i18n.later("Pictures")},
	{.Music, i18n.later("Music")},
	{.Videos, i18n.later("Videos")},
}

// The places as a worker read them, on their way to the interface's thread.
@(private = "file")
Places_Read :: struct {
	app:     ^App,
	serial:  u64,
	home:    string,   // owned
	places:  [dynamic]Place,
	volumes: []fs.Volume,
	shares:  []fs.Share,
	space:   [dynamic]fs.Space,
}

// Asks a worker to read the places again.
places_load :: proc(app: ^App) {
	app.places_asked += 1
	app.answers_due += 1
	r := new(Places_Read)
	r^ = {app = app, serial = app.places_asked, home = strings.clone(app.home)}
	tasks.add(&app.pool, places_run, r)
}

@(private = "file")
places_run :: proc(data: rawptr) {
	r := (^Places_Read)(data)
	known := KNOWN
	for k in known {
		path := k.folder == .Home ? strings.clone(r.home) : platform.known_folder_path(k.folder)
		info, ok := fs.stat(path)
		// (a folder the system names but that is the home itself, or missing, is left out)
		if path == "" || !ok || info.kind != .Directory || (k.folder != .Home && path == r.home) {
			delete(path)
			continue
		}
		append(&r.places, Place{name = strings.clone(i18n.tr(k.name)), path = path})
	}
	// the root of the system (File Pilot's This PC) and the trash, as the system has them
	for sp in fs.system_places(context.temp_allocator) {
		append(&r.places, Place{name = strings.clone(sp.name), path = strings.clone(sp.path)})
	}
	r.volumes = fs.volumes()
	r.shares = fs.network_shares()
	for v in r.volumes {
		sp, _ := fs.space(v.path)
		append(&r.space, sp)
	}
	if !ui.post(&r.app.main.state, places_done, r) { places_read_free(r) }
}

// On the interface's thread: the new places take the place of the old ones, when they are the last asked.
@(private = "file")
places_done :: proc(data: rawptr, word: u64) {
	r := (^Places_Read)(data)
	app := r.app
	defer places_read_free(r)
	app.answers_due -= 1
	if r.serial != app.places_asked { return }
	places_free(app)
	app.places, r.places = r.places, app.places
	app.volumes, r.volumes = r.volumes, nil
	app.shares, r.shares = r.shares, nil
	app.volume_space, r.space = r.space, app.volume_space
	app_frames(app)
}

@(private = "file")
places_read_free :: proc(r: ^Places_Read) {
	for p in r.places {
		delete(p.name)
		delete(p.path)
	}
	delete(r.places)
	if r.volumes != nil { fs.volumes_destroy(r.volumes) }
	if r.shares != nil { fs.shares_destroy(r.shares) }
	delete(r.space)
	delete(r.home)
	free(r)
}

places_free :: proc(app: ^App) {
	for p in app.places {
		delete(p.name)
		delete(p.path)
	}
	clear(&app.places)
	if app.volumes != nil { fs.volumes_destroy(app.volumes) }
	app.volumes = nil
	if app.shares != nil { fs.shares_destroy(app.shares) }
	app.shares = nil
}
