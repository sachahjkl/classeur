package classeur

// The places of the sidebar: the person's folders (those that exist), then the volumes (fs.volumes).

import "core:os"
import "core:strings"
import lucide "gt:lucide"
import "gt:platform"
import "fs"

Place :: struct {
	name, path: string,   // owned
	icon:       string,
}

@(private = "file")
Known :: struct { folder: platform.Known_Folder, name, icon: string }

@(private = "file")
KNOWN :: [?]Known{
	{.Home, "Home", lucide.HOME},
	{.Desktop, "Desktop", lucide.MONITOR},
	{.Documents, "Documents", lucide.FILE_TEXT},
	{.Downloads, "Downloads", lucide.DOWNLOAD},
	{.Pictures, "Pictures", lucide.IMAGE},
	{.Music, "Music", lucide.MUSIC},
	{.Videos, "Videos", lucide.FILM},
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
		append(&app.places, Place{name = strings.clone(k.name), path = path, icon = k.icon})
	}
	// the root of the system (File Pilot's This PC) and the trash
	when ODIN_OS != .Windows {
		append(&app.places, Place{name = strings.clone("Computer"), path = strings.clone("/"), icon = lucide.HARD_DRIVE})
		data := os.get_env("XDG_DATA_HOME", context.temp_allocator)
		if data == "" { data = fs.join(app.home, ".local/share", context.temp_allocator) }
		trash := fs.join(data, "Trash/files")
		if info, ok := fs.stat(trash); ok && info.kind == .Directory {
			append(&app.places, Place{name = strings.clone("Trash"), path = trash, icon = lucide.TRASH_2})
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
