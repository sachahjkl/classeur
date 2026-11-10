package fs

// Windows: what changes files. CopyFileExW copies (attributes and times included) and reports its progress; a rename
// never replaces (MoveFileExW without MOVEFILE_REPLACE_EXISTING); the trash is the Recycle Bin (SHFileOperationW with
// FOF_ALLOWUNDO, which the shell's Restore reads).

import "base:runtime"
import "core:strings"
import "core:time"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"
foreign import shell32 "system:Shell32.lib"

@(private = "file")
COPY_FILE_FAIL_IF_EXISTS :: 0x1
@(private = "file")
PROGRESS_CONTINUE :: 0
@(private = "file")
PROGRESS_CANCEL :: 1
@(private = "file")
ERROR_ALREADY_EXISTS :: 183
@(private = "file")
ERROR_FILE_EXISTS :: 80
@(private = "file")
ERROR_NOT_SAME_DEVICE :: 17
@(private = "file")
ERROR_DISK_FULL :: 112
@(private = "file")
ERROR_REQUEST_ABORTED :: 1235
@(private = "file")
ERROR_DIR_NOT_EMPTY :: 145
@(private = "file")
SYMBOLIC_LINK_FLAG_DIRECTORY :: 0x1
@(private = "file")
SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE :: 0x2

@(private = "file")
Copy_Progress :: #type proc "system" (total, transferred, stream_size, stream_transferred: i64, stream: win.DWORD, reason: win.DWORD, src, dst: win.HANDLE, data: rawptr) -> win.DWORD

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	CopyFileExW :: proc(from, to: win.LPCWSTR, progress: Copy_Progress, data: rawptr, cancel: ^win.BOOL, flags: win.DWORD) -> win.BOOL ---
	CreateSymbolicLinkW :: proc(link, target: win.LPCWSTR, flags: win.DWORD) -> win.BOOLEAN ---
	GetFinalPathNameByHandleW :: proc(file: win.HANDLE, path: win.LPWSTR, size, flags: win.DWORD) -> win.DWORD ---
}

@(private = "file")
op_error :: proc(code: win.DWORD) -> Error {
	switch code {
	case 0:                                                  return .None
	case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND: return .Not_Found
	case win.ERROR_ACCESS_DENIED:                            return .Denied
	case ERROR_ALREADY_EXISTS, ERROR_FILE_EXISTS, ERROR_DIR_NOT_EMPTY: return .Exists
	case ERROR_NOT_SAME_DEVICE:                              return .Cross_Volume
	case ERROR_DISK_FULL:                                    return .No_Space
	case ERROR_REQUEST_ABORTED:                              return .Cancelled
	}
	return .Other
}

@(private = "file")
wide :: proc(path: string) -> win.LPCWSTR { return win.utf8_to_wstring(path, context.temp_allocator) }

@(private = "file")
Copy_State :: struct {
	p:    ^Progress,
	seen: i64,
	ctx:  runtime.Context,
}

@(private = "file")
copy_progress :: proc "system" (total, transferred, stream_size, stream_transferred: i64, stream: win.DWORD, reason: win.DWORD, src, dst: win.HANDLE, data: rawptr) -> win.DWORD {
	st := (^Copy_State)(data)
	context = st.ctx
	if st.p.on_bytes != nil && transferred > st.seen { st.p.on_bytes(st.p.user, transferred - st.seen) }
	st.seen = transferred
	if st.p.cancelled != nil && st.p.cancelled(st.p.user) { return PROGRESS_CANCEL }
	return PROGRESS_CONTINUE
}

copy_file_native :: proc(from, to: string, p: ^Progress = nil) -> Error {
	if p == nil {
		if !CopyFileExW(wide(from), wide(to), nil, nil, nil, COPY_FILE_FAIL_IF_EXISTS) { return op_error(win.GetLastError()) }
		return .None
	}
	st := Copy_State{p = p, ctx = context}
	if !CopyFileExW(wide(from), wide(to), copy_progress, &st, nil, COPY_FILE_FAIL_IF_EXISTS) { return op_error(win.GetLastError()) }
	return .None
}

// A symbolic link made again at `to`, with the same target (Developer Mode or the privilege: else .Denied).
copy_link :: proc(from, to: string) -> Error {
	target, ok := link_target(from)
	if !ok { return .Other }
	info, _ := stat(from)
	flags: win.DWORD = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
	if info.kind == .Directory { flags |= SYMBOLIC_LINK_FLAG_DIRECTORY }
	if !bool(CreateSymbolicLinkW(wide(to), wide(target), flags)) { return op_error(win.GetLastError()) }
	return .None
}

// What a link points to: the final path of what it opens.
@(private = "file")
link_target :: proc(path: string) -> (string, bool) {
	h := win.CreateFileW(wide(path), 0, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE, nil, win.OPEN_EXISTING, win.FILE_FLAG_BACKUP_SEMANTICS, nil)
	if h == win.INVALID_HANDLE_VALUE { return "", false }
	defer win.CloseHandle(h)
	buf: [win.MAX_PATH * 4]u16
	n := GetFinalPathNameByHandleW(h, &buf[0], len(buf), 0)
	if n == 0 || int(n) >= len(buf) { return "", false }
	s, _ := win.wstring_to_utf8(cstring16(&buf[0]), int(n), context.temp_allocator)
	return strings.trim_prefix(s, "\\\\?\\"), true
}

make_folder_native :: proc(path: string) -> Error {
	if !win.CreateDirectoryW(wide(path), nil) { return op_error(win.GetLastError()) }
	return .None
}

// An empty file at `path`, never over something (.Exists when the name is taken).
make_file_native :: proc(path: string) -> Error {
	h := win.CreateFileW(wide(path), win.GENERIC_WRITE, 0, nil, win.CREATE_NEW, win.FILE_ATTRIBUTE_NORMAL, nil)
	if h == win.INVALID_HANDLE_VALUE { return op_error(win.GetLastError()) }
	win.CloseHandle(h)
	return .None
}

// Renames `from` to `to`, never over something: .Exists when the name is taken, .Cross_Volume when it is on another
// volume.
// (a file the shell or an antivirus reads for a moment refuses to move: tried again a few times, as Explorer does)
rename_native :: proc(from, to: string) -> Error {
	for attempt in 0 ..< 10 {
		if win.MoveFileExW(wide(from), wide(to), 0) { return .None }
		e := win.GetLastError()
		if e != win.ERROR_SHARING_VIOLATION && e != win.ERROR_ACCESS_DENIED || attempt == 9 { return op_error(e) }
		time.sleep(20 * time.Millisecond)
	}
	return .Other
}

// A file, a link or an empty folder.
remove_native :: proc(path: string) -> Error {
	info, ok := stat(path)
	if !ok { return .Not_Found }
	if info.kind == .Directory {
		if !win.RemoveDirectoryW(wide(path)) { return op_error(win.GetLastError()) }
		return .None
	}
	if !win.DeleteFileW(wide(path)) { return op_error(win.GetLastError()) }
	return .None
}

exists_native :: proc(path: string) -> bool {
	return win.GetFileAttributesW(wide(path)) != win.INVALID_FILE_ATTRIBUTES
}

@(private = "file")
SHFILEOPSTRUCTW :: struct {
	hwnd:                  win.HWND,
	wFunc:                 win.UINT,
	pFrom:                 [^]u16,
	pTo:                   [^]u16,
	fFlags:                u16,
	fAnyOperationsAborted: win.BOOL,
	hNameMappings:         rawptr,
	lpszProgressTitle:     win.LPCWSTR,
}

@(default_calling_convention = "system", private = "file")
foreign shell32 {
	@(link_name = "SHFileOperationW") sh_file_operation :: proc(op: ^SHFILEOPSTRUCTW) -> i32 ---
}

@(private = "file")
FO_DELETE :: 3
@(private = "file")
FOF_SILENT :: 0x4
@(private = "file")
FOF_NOCONFIRMATION :: 0x10
@(private = "file")
FOF_ALLOWUNDO :: 0x40
@(private = "file")
FOF_NOERRORUI :: 0x400

// To the Recycle Bin. `in_trash` is "": the Recycle Bin gives no path back (untrash cannot put it back; Explorer's
// Recycle Bin can).
trash_native :: proc(path: string, allocator := context.allocator) -> (in_trash: string, e: Error) {
	if !exists(path) { return "", .Not_Found }
	// (a list of paths, each ended by a zero, the list by another)
	w := win.utf8_to_utf16(path, context.temp_allocator)
	from := make([]u16, len(w) + 2, context.temp_allocator)
	copy(from, w)
	op := SHFILEOPSTRUCTW{wFunc = FO_DELETE, pFrom = raw_data(from), fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI}
	if sh_file_operation(&op) != 0 || op.fAnyOperationsAborted { return "", .Other }
	return "", .None
}

untrash :: proc(in_trash: string, allocator := context.allocator) -> (original: string, e: Error) { return "", .Other }

// Whether `a` and `b` are on one volume (their drive or share is the same).
same_volume :: proc(a, b: string) -> bool {
	// (as on Linux: a path that is not there is on no volume)
	if !exists(a) || !exists(b) { return false }
	ra, rb := root_length(a), root_length(b)
	if ra == 0 || ra != rb { return false }
	return strings.equal_fold(a[:ra], b[:rb])
}
