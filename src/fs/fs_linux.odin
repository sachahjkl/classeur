package fs

// Linux: getdents64 into a large buffer, then one statx per entry relative to the folder's descriptor (no path is
// built, no file is opened). A link costs a second statx, which follows it.

import "core:fmt"
import "core:os"
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

// Its birth and access times, its permissions, its owner (the names of /etc/passwd and /etc/group, else the numbers).
properties_native :: proc(path: string) -> (p: Properties, ok: bool) {
	sx: linux.Statx
	if linux.statx(linux.AT_FDCWD, strings.clone_to_cstring(path, context.temp_allocator), {}, {.MODE, .UID, .GID, .ATIME, .BTIME}, &sx) != .NONE { return }
	if .BTIME in sx.mask { p.created = statx_time(sx.btime) }
	p.accessed = statx_time(sx.atime)
	bits := transmute(u32)sx.mode & 0o777
	b := strings.builder_make(context.temp_allocator)
	letters := "rwx"
	for i in 0 ..< 9 {
		on := bits & (1 << u32(8 - i)) != 0
		strings.write_byte(&b, on ? letters[i % 3] : '-')
	}
	p.permissions = fmt.tprintf("%s (%o)", strings.to_string(b), bits)
	p.owner = fmt.tprintf("%s:%s", id_name("/etc/passwd", u32(sx.uid)), id_name("/etc/group", u32(sx.gid)))
	return p, true
}

// The name of a number in /etc/passwd or /etc/group ("name:x:number:..."), else the number.
@(private = "file")
id_name :: proc(file: string, id: u32) -> string {
	data, err := os.read_entire_file(file, context.temp_allocator)
	if err == nil {
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			parts := strings.split_n(line, ":", 4, context.temp_allocator)
			if len(parts) >= 3 && parts[2] == fmt.tprintf("%d", id) { return parts[0] }
		}
	}
	return fmt.tprintf("%d", id)
}
