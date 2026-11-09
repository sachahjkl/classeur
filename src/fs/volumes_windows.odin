package fs

// The drives of the system, A: to Z:, with their labels ("Local Disk" when a fixed drive has none).

import "core:fmt"
import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	GetLogicalDrives :: proc() -> win.DWORD ---
	GetDriveTypeW :: proc(root: win.LPCWSTR) -> win.UINT ---
	GetVolumeInformationW :: proc(root: win.LPCWSTR, name: win.LPWSTR, name_size: win.DWORD, serial, max_part, flags: ^win.DWORD, fs_name: win.LPWSTR, fs_name_size: win.DWORD) -> win.BOOL ---
}

@(private = "file")
DRIVE_REMOVABLE :: 2
@(private = "file")
DRIVE_REMOTE :: 4
@(private = "file")
DRIVE_CDROM :: 5

volumes :: proc(allocator := context.allocator) -> []Volume {
	out := make([dynamic]Volume, allocator)
	mask := GetLogicalDrives()
	for i in 0 ..< 26 {
		if mask & (1 << uint(i)) == 0 { continue }
		root := fmt.tprintf("%c:\\", 'A' + i)
		wroot := win.utf8_to_wstring(root, context.temp_allocator)
		kind := GetDriveTypeW(wroot)
		name: [win.MAX_PATH + 1]u16
		label := ""
		if GetVolumeInformationW(wroot, &name[0], len(name), nil, nil, nil, nil, 0) {
			label, _ = win.wstring_to_utf8(cstring16(&name[0]), -1, context.temp_allocator)
		}
		if label == "" { label = kind == DRIVE_REMOVABLE ? "Removable drive" : kind == DRIVE_REMOTE ? "Network drive" : "Local disk" }
		append(&out, Volume{
			path = strings.clone(root, allocator),
			label = fmt.aprintf("%s (%c:)", label, 'A' + i, allocator = allocator),
			removable = kind == DRIVE_REMOVABLE || kind == DRIVE_CDROM,
		})
	}
	return out[:]
}
