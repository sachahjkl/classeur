package fs

// The places of the system beside the person's folders: the root (File Pilot's This PC) and the trash of the
// freedesktop.org specification, when it is there.

import "core:os"

System_Place :: struct { name, path: string }

system_places :: proc(home: string, allocator := context.allocator) -> []System_Place {
	out := make([dynamic]System_Place, allocator)
	append(&out, System_Place{"Computer", clone_string("/", allocator)})
	data := os.get_env("XDG_DATA_HOME", context.temp_allocator)
	if data == "" { data = join(home, ".local/share", context.temp_allocator) }
	trash := join(data, "Trash/files", context.temp_allocator)
	if info, ok := stat(trash); ok && info.kind == .Directory { append(&out, System_Place{"Trash", clone_string(trash, allocator)}) }
	return out[:]
}

@(private = "file")
clone_string :: proc(s: string, allocator := context.allocator) -> string {
	b := make([]u8, len(s), allocator)
	copy(b, s)
	return string(b)
}
