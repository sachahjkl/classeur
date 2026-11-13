package fs

// The places of the system beside the person's folders: the root (File Pilot's This PC) and the trash of the
// freedesktop.org specification, when it is there.

import "gt:platform"

System_Place :: struct { name, path: string }

system_places :: proc(allocator := context.allocator) -> []System_Place {
	out := make([dynamic]System_Place, allocator)
	append(&out, System_Place{"Computer", clone_string("/", allocator)})
	trash := join(platform.user_dir(.Data, "", context.temp_allocator), "Trash/files", context.temp_allocator)
	if info, ok := stat(trash); ok && info.kind == .Directory { append(&out, System_Place{"Trash", clone_string(trash, allocator)}) }
	return out[:]
}

@(private = "file")
clone_string :: proc(s: string, allocator := context.allocator) -> string {
	b := make([]u8, len(s), allocator)
	copy(b, s)
	return string(b)
}
