#+build windows
package fs

// Windows: the computers of the network neighbourhood (WNetOpenEnum of RESOURCE_CONTEXT), each an SMB host, beside
// those multicast DNS found: a Windows computer shares its folders without announcing them that way.

import "core:strings"
import win "core:sys/windows"

foreign import mpr "system:Mpr.lib"

@(private = "file")
NETRESOURCEW :: struct {
	dwScope:       win.DWORD,
	dwType:        win.DWORD,
	dwDisplayType: win.DWORD,
	dwUsage:       win.DWORD,
	lpLocalName:   win.LPWSTR,
	lpRemoteName:  win.LPWSTR,
	lpComment:     win.LPWSTR,
	lpProvider:    win.LPWSTR,
}

@(default_calling_convention = "system", private = "file")
foreign mpr {
	WNetOpenEnumW :: proc(scope, type, usage: win.DWORD, resource: ^NETRESOURCEW, handle: ^win.HANDLE) -> win.DWORD ---
	WNetEnumResourceW :: proc(handle: win.HANDLE, count: ^win.DWORD, buffer: rawptr, size: ^win.DWORD) -> win.DWORD ---
	WNetCloseEnum :: proc(handle: win.HANDLE) -> win.DWORD ---
}

@(private = "file") RESOURCE_CONTEXT           :: 5
@(private = "file") RESOURCETYPE_ANY           :: 0
@(private = "file") RESOURCEDISPLAYTYPE_SERVER :: 2

system_devices_add :: proc(list: ^[dynamic]Network_Device, allocator := context.allocator) {
	handle: win.HANDLE
	if WNetOpenEnumW(RESOURCE_CONTEXT, RESOURCETYPE_ANY, 0, nil, &handle) != 0 { return }
	defer WNetCloseEnum(handle)
	// (u64s: the buffer holds the records' pointers aligned)
	buf: [2048]u64
	for {
		count := win.DWORD(0xFFFFFFFF)
		size := win.DWORD(size_of(buf))
		if WNetEnumResourceW(handle, &count, &buf[0], &size) != 0 { return }   // (ERROR_NO_MORE_ITEMS, or a failure)
		records := ([^]NETRESOURCEW)(rawptr(&buf[0]))[:int(count)]
		for r in records {
			if r.dwDisplayType != RESOURCEDISPLAYTYPE_SERVER || r.lpRemoteName == nil { continue }
			remote, _ := win.wstring_to_utf8(cstring16(r.lpRemoteName), -1, context.temp_allocator)
			name := strings.trim_prefix(remote, "\\\\")
			if name == "" { continue }
			uri := uri_text({scheme = "smb", host = name, path = "/"}, context.temp_allocator)
			device_add(list, name, name, "", "smb", uri, allocator)
		}
	}
}
