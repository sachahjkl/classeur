package classeur

// The places of the sidebar: the person's folders (those that exist), then the volumes (fs.volumes).

import "core:os"
import "core:strings"
import "gt:platform"
import "fs"

Place :: struct {
	name, path: string,   // owned
}

@(private = "file")
Known :: struct { folder: platform.Known_Folder, name: string }

@(private = "file")
KNOWN :: [?]Known{
	{.Home, "Home"},
	{.Desktop, "Desktop"},
	{.Documents, "Documents"},
	{.Downloads, "Downloads"},
	{.Pictures, "Pictures"},
	{.Music, "Music"},
	{.Videos, "Videos"},
}

places_load :: proc(app: ^App) {
	places_free(app)
	known := KNOWN
	for k in known {
		path := k.folder == .Home ? strings.clone(app.home) : platform.known_folder_path(k.folder)
		info, ok := fs.stat(path)
		// (a folder the system names but that is the home itself, or missing, is left out)
		if path == "" || !ok || info.kind != .Directory || (k.folder != .Home && path == app.home) {
			delete(path)
			continue
		}
		append(&app.places, Place{name = strings.clone(k.name), path = path})
	}
	// the root of the system (File Pilot's This PC) and the trash
	when ODIN_OS != .Windows {
		append(&app.places, Place{name = strings.clone("Computer"), path = strings.clone("/")})
		data := os.get_env("XDG_DATA_HOME", context.temp_allocator)
		if data == "" { data = fs.join(app.home, ".local/share", context.temp_allocator) }
		trash := fs.join(data, "Trash/files")
		if info, ok := fs.stat(trash); ok && info.kind == .Directory {
			append(&app.places, Place{name = strings.clone("Trash"), path = trash})
		} else {
			delete(trash)
		}
	}
	app.volumes = fs.volumes()
	clear(&app.volume_space)
	for v in app.volumes {
		sp, _ := fs.space(v.path)
		append(&app.volume_space, sp)
	}
}

places_free :: proc(app: ^App) {
	for p in app.places {
		delete(p.name)
		delete(p.path)
	}
	clear(&app.places)
	if app.volumes != nil { fs.volumes_destroy(app.volumes) }
	app.volumes = nil
}
