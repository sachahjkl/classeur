package fs

// Linux: getdents64 into a large buffer, then one statx per entry relative to the folder's descriptor (no path is
// built, no file is opened). A link costs a second statx, which follows it.

import "core:strings"
import "core:sys/linux"

@(private = "file")
DIRENT_BUFFER :: 64 * 1024

@(private = "file")
STATX_WANTED :: linux.Statx_Mask{.TYPE, .MODE, .SIZE, .MTIME}

@(private = "file")
errno_error :: proc(e: linux.Errno) -> Error {
	#partial switch e {
	case .NONE:            return .None
	case .ENOENT:          return .Not_Found
	case .EACCES, .EPERM:  return .Denied
	case .ENOTDIR:         return .Not_A_Folder
	}
	return .Other
}

@(private = "file")
statx_kind :: proc(m: linux.Mode) -> Kind {
	switch {
	case linux.S_ISDIR(m): return .Directory
	case linux.S_ISREG(m): return .File
	}
	return .Other
}

@(private = "file")
statx_time :: proc(t: linux.Statx_Timestamp) -> i64 { return t.sec * 1_000_000_000 + i64(t.nsec) }

@(private)
list_native :: proc(l: ^Listing, path: string) -> Error {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	dfd, oerr := linux.open(cpath, {.DIRECTORY, .CLOEXEC})
	if oerr != .NONE { return errno_error(oerr) }
	defer linux.close(dfd)

	buf := make([]u8, DIRENT_BUFFER, context.temp_allocator)
	for {
		n, gerr := linux.getdents(dfd, buf)
		if gerr != .NONE { return errno_error(gerr) }
		if n == 0 { break }
		offset := 0
		for d in linux.dirent_iterate_buf(buf[:n], &offset) {
			name := linux.dirent_name(d)
			if name == "." || name == ".." { continue }
			e := Entry{size = -1}
			stat_entry(dfd, cstring(raw_data(name)), &e)
			if name[0] == '.' { e.flags += {.Hidden} }
			e.name = keep_name(l, name)
			append(&l.entries, e)
		}
	}
	return .None
}

// The kind, size, time and flags of `name` in the folder `dfd` (AT_FDCWD: a path).
@(private = "file")
stat_entry :: proc(dfd: linux.Fd, name: cstring, e: ^Entry) -> bool {
	sx: linux.Statx
	if linux.statx(dfd, name, {.SYMLINK_NOFOLLOW}, STATX_WANTED, &sx) != .NONE {
		e.kind = .Other
		return false
	}
	if linux.S_ISLNK(sx.mode) {
		e.flags += {.Link}
		if linux.statx(dfd, name, {}, STATX_WANTED, &sx) != .NONE {
			e.kind = .Broken_Link
			return true
		}
	}
	e.kind = statx_kind(sx.mode)
	e.mtime = statx_time(sx.mtime)
	if e.kind == .File { e.size = i64(sx.size) }
	if e.kind == .File && (sx.mode & {.IXUSR, .IXGRP, .IXOTH}) != {} { e.flags += {.Executable} }
	if (sx.mode & {.IWUSR, .IWGRP, .IWOTH}) == {} { e.flags += {.Read_Only} }
	return true
}

stat_native :: proc(path: string) -> (info: Info, ok: bool) {
	e := Entry{size = -1}
	if !stat_entry(linux.AT_FDCWD, strings.clone_to_cstring(path, context.temp_allocator), &e) { return }
	return Info{kind = e.kind, size = e.size, mtime = e.mtime, flags = e.flags}, true
}

space :: proc(path: string) -> (s: Space, ok: bool) {
	st: linux.Stat_FS
	if linux.statfs(strings.clone_to_cstring(path, context.temp_allocator), &st) != .NONE { return }
	unit := st.frsize > 0 ? i64(st.frsize) : i64(st.bsize)
	return Space{free = i64(st.bavail) * unit, total = i64(st.blocks) * unit}, true
}
