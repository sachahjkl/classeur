package fs

// The places of the system beside the person's folders: on Windows the drives are the volumes of the sidebar already
// (volumes_windows.odin), the Recycle Bin is the shell's: nothing more here.

System_Place :: struct { name, path: string }

system_places :: proc(home: string, allocator := context.allocator) -> []System_Place {
	return make([]System_Place, 0, allocator)
}
