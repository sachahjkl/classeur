#+build windows
package fs

// Windows: an SMB share is read where it is, by its UNC path (\\host\share\b): smb:// and file://host/ give it; the
// shares mounted are the network's drives (Z:, its \\host\share). WebDAV over HTTPS is \\host@SSL\DavWWWRoot\b. The
// Recycle Bin is no folder (Unsupported), nor are sftp, ftp and nfs, which Windows does not reach by a path.

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"
foreign import mpr "system:Mpr.lib"

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	GetLogicalDrives :: proc() -> win.DWORD ---
	GetDriveTypeW :: proc(root: win.LPCWSTR) -> win.UINT ---
}

@(default_calling_convention = "system", private = "file")
foreign mpr {
	WNetGetConnectionW :: proc(local: win.LPCWSTR, remote: win.LPWSTR, length: ^win.DWORD) -> win.DWORD ---
}

@(private = "file") DRIVE_REMOTE :: 4

location_resolve :: proc(text: string, allocator := context.allocator) -> (r: Location, e: Location_Error) {
	t := strings.trim_space(text)
	if !is_uri(t) {
		if t == "" { return {}, .Not_A_Location }
		return {path = strings.clone(t, allocator), kind = .Path}, .None
	}
	u, _ := uri_parse(t)
	back, _ := strings.replace_all(u.path, "/", "\\", context.temp_allocator)
	switch u.scheme {
	case "file":
		// file:///C:/a -> C:\a; file://host/share/a -> \\host\share\a
		if u.host != "" && !strings.equal_fold(u.host, "localhost") {
			return {path = strings.concatenate({"\\\\", u.host, back}, allocator), kind = .Network}, .None
		}
		return {path = strings.clone(strings.trim_prefix(back, "\\"), allocator), kind = .Path}, .None
	case "smb":
		return {path = strings.concatenate({"\\\\", u.host, back}, allocator), kind = .Network, uri = strings.clone(t, allocator)}, .None
	case "davs":
		return {path = strings.concatenate({"\\\\", u.host, "@SSL\\DavWWWRoot", back}, allocator), kind = .Network, uri = strings.clone(t, allocator)}, .None
	case "dav":
		return {path = strings.concatenate({"\\\\", u.host, "\\DavWWWRoot", back}, allocator), kind = .Network, uri = strings.clone(t, allocator)}, .None
	case "trash":
		return {kind = .Trash}, .Unsupported
	}
	if is_network_scheme(u.scheme) { return {kind = .Network, uri = strings.clone(t, allocator)}, .Unsupported }
	return {}, .Not_A_Location
}

// The Recycle Bin is no folder: no tab shows it, its items are put back by an undo only.
trash_files_dir :: proc(allocator := context.temp_allocator) -> string { return "" }

// Nothing to mount: a share is read by its UNC path (Windows asks for a password itself when it wants one).
share_mount :: proc(uri: string, allocator := context.temp_allocator) -> (ok: bool, why: string) { return true, "" }

location_display :: proc(path: string, allocator := context.allocator) -> string {
	if root, uri, ok := share_root(path, context.temp_allocator); ok {
		rest, _ := strings.replace_all(strings.trim_prefix(path[len(root):], "\\"), "\\", "/", context.temp_allocator)
		if rest == "" { return strings.clone(uri, allocator) }
		return strings.concatenate({strings.trim_suffix(uri, "/"), "/", percent_encode(rest)}, allocator)
	}
	return strings.clone(path, allocator)
}

// A UNC path's share (\\host\share), or a network drive's (Z:\ and its \\host\share).
share_root :: proc(path: string, allocator := context.allocator) -> (root, uri: string, ok: bool) {
	if strings.has_prefix(path, "\\\\") {
		parts := strings.split_n(path[2:], "\\", 3, context.temp_allocator)
		if len(parts) < 2 || parts[0] == "?" || parts[0] == "." { return }
		root = strings.concatenate({"\\\\", parts[0], "\\", parts[1]}, allocator)
		uri = uri_text({scheme = "smb", host = parts[0], path = strings.concatenate({"/", parts[1]}, context.temp_allocator)}, allocator)
		return root, uri, true
	}
	if len(path) >= 2 && path[1] == ':' {
		remote := drive_remote(path[:2])
		if remote == "" { return }
		parts := strings.split_n(strings.trim_prefix(remote, "\\\\"), "\\", 2, context.temp_allocator)
		if len(parts) < 2 { return }
		root = strings.concatenate({path[:2], "\\"}, allocator)
		uri = uri_text({scheme = "smb", host = parts[0], path = strings.concatenate({"/", parts[1]}, context.temp_allocator)}, allocator)
		return root, uri, true
	}
	return
}

network_shares :: proc(allocator := context.allocator) -> []Share {
	out := make([dynamic]Share, allocator)
	mask := GetLogicalDrives()
	for i in 0 ..< 26 {
		if mask & (1 << uint(i)) == 0 { continue }
		letter := [2]u8{u8('A' + i), ':'}
		drive := string(letter[:])
		if GetDriveTypeW(win.utf8_to_wstring(strings.concatenate({drive, "\\"}, context.temp_allocator), context.temp_allocator)) != DRIVE_REMOTE { continue }
		root, uri, ok := share_root(strings.concatenate({drive, "\\"}, context.temp_allocator), context.temp_allocator)
		if !ok { continue }
		append(&out, Share{path = strings.clone(root, allocator), label = strings.concatenate({share_label(uri, context.temp_allocator), " (", drive, ")"}, allocator), uri = strings.clone(uri, allocator)})
	}
	return out[:]
}

// The share a network drive ("Z:") is connected to, "\\host\share" ("" none).
@(private = "file")
drive_remote :: proc(drive: string) -> string {
	buf: [win.MAX_PATH + 1]u16
	n := win.DWORD(len(buf))
	if WNetGetConnectionW(win.utf8_to_wstring(drive, context.temp_allocator), &buf[0], &n) != 0 { return "" }
	s, _ := win.wstring_to_utf8(cstring16(&buf[0]), -1, context.temp_allocator)
	return s
}
