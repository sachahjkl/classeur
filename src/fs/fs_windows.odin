package fs

// Windows: FindFirstFileExW with the basic information level and large fetches. Each record already holds the size,
// the times and the attributes: a folder of any size is read with no call per file.

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(private = "file")
FIND_EX_INFO_BASIC :: 1
@(private = "file")
FIND_EX_SEARCH_NAME_MATCH :: 0
@(private = "file")
FIND_FIRST_EX_LARGE_FETCH :: 2
@(private = "file")
ERROR_DIRECTORY :: 267

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	FindFirstFileExW :: proc(name: win.LPCWSTR, info_level: i32, data: ^win.WIN32_FIND_DATAW, search_op: i32, filter: rawptr, flags: win.DWORD) -> win.HANDLE ---
}

// Windows' times count 100 ns from 1601-01-01.
@(private = "file")
EPOCH_DIFF_100NS :: 116_444_736_000_000_000

@(private = "file")
filetime_ns :: proc(t: win.FILETIME) -> i64 {
	v := i64(t.dwHighDateTime) << 32 | i64(t.dwLowDateTime)
	return (v - EPOCH_DIFF_100NS) * 100
}

@(private = "file")
win_error :: proc(code: win.DWORD) -> Error {
	switch code {
	case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND: return .Not_Found
	case win.ERROR_ACCESS_DENIED:                            return .Denied
	case ERROR_DIRECTORY:                                    return .Not_A_Folder
	}
	return .Other
}

@(private = "file")
attributes_entry :: proc(attrs: win.DWORD, size_high, size_low: win.DWORD, mtime: win.FILETIME, e: ^Entry) {
	e.kind = attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 ? .Directory : .File
	e.mtime = filetime_ns(mtime)
	if e.kind == .File { e.size = i64(size_high) << 32 | i64(size_low) }
	if attrs & win.FILE_ATTRIBUTE_HIDDEN != 0 { e.flags += {.Hidden} }
	// (a name that starts with a dot is hidden too, as on Linux: File Pilot puts dotfiles with the hidden files)
	if len(e.name) > 0 && e.name[0] == '.' { e.flags += {.Hidden} }
	if attrs & win.FILE_ATTRIBUTE_SYSTEM != 0 { e.flags += {.System} }
	if attrs & win.FILE_ATTRIBUTE_READONLY != 0 { e.flags += {.Read_Only} }
	if attrs & win.FILE_ATTRIBUTE_REPARSE_POINT != 0 { e.flags += {.Link} }
}

@(private)
list_native :: proc(l: ^Listing, path: string) -> Error {
	sep := strings.has_suffix(path, "\\") || strings.has_suffix(path, "/") ? "" : "\\"
	pattern := win.utf8_to_wstring(strings.concatenate({path, sep, "*"}, context.temp_allocator), context.temp_allocator)
	data: win.WIN32_FIND_DATAW
	h := FindFirstFileExW(pattern, FIND_EX_INFO_BASIC, &data, FIND_EX_SEARCH_NAME_MATCH, nil, FIND_FIRST_EX_LARGE_FETCH)
	if h == win.INVALID_HANDLE_VALUE {
		code := win.GetLastError()
		if code == win.ERROR_FILE_NOT_FOUND { return .None }   // (an empty root: not even "." is there)
		return win_error(code)
	}
	defer win.FindClose(h)
	for {
		name, _ := win.wstring_to_utf8(cstring16(&data.cFileName[0]), -1, context.temp_allocator)
		if name != "." && name != ".." {
			e := Entry{size = -1}
			attributes_entry(data.dwFileAttributes, data.nFileSizeHigh, data.nFileSizeLow, data.ftLastWriteTime, &e)
			e.name = keep_name(l, name)
			append(&l.entries, e)
		}
		if !win.FindNextFileW(h, &data) { break }
	}
	return .None
}

stat :: proc(path: string) -> (info: Info, ok: bool) {
	data: win.WIN32_FILE_ATTRIBUTE_DATA
	if !win.GetFileAttributesExW(win.utf8_to_wstring(path, context.temp_allocator), win.GetFileExInfoStandard, &data) { return }
	e := Entry{size = -1}
	attributes_entry(data.dwFileAttributes, data.nFileSizeHigh, data.nFileSizeLow, data.ftLastWriteTime, &e)
	return Info{kind = e.kind, size = e.size, mtime = e.mtime, flags = e.flags}, true
}

space :: proc(path: string) -> (s: Space, ok: bool) {
	free, total, all_free: win.ULARGE_INTEGER
	if !win.GetDiskFreeSpaceExW(win.utf8_to_wstring(path, context.temp_allocator), &free, &total, &all_free) { return }
	return Space{free = i64(free), total = i64(total)}, true
}
