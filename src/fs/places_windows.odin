package fs

// The places of the system beside the person's folders: on Windows the drives are the volumes of the sidebar already
// (volumes_windows.odin); the Recycle Bin of every drive (trash_windows.odin).

import "gt:i18n"

System_Place :: struct { name, path: string }

system_places :: proc(allocator := context.allocator) -> []System_Place {
	out := make([]System_Place, 1, allocator)
	out[0] = {i18n.tr("Recycle Bin"), RECYCLE_BIN}
	return out
}
