package fs

// Linux: what changes files. A file is copied in the kernel (copy_file_range, which also lets a file system share the
// blocks: btrfs, XFS) in steps that report their progress; read and write when the kernel refuses. The mode and the
// modification time go with it. Renames never replace (renameat2 NOREPLACE): a name taken is the caller's decision.

import "core:strings"
import "core:sys/linux"

@(private = "file")
COPY_STEP :: 8 * 1024 * 1024
@(private = "file")
COPY_BUFFER :: 1024 * 1024

@(private = "file")
op_error :: proc(e: linux.Errno) -> Error {
	#partial switch e {
	case .NONE:                    return .None
	case .ENOENT:                  return .Not_Found
	case .EACCES, .EPERM, .EROFS:  return .Denied
	case .ENOTDIR:                 return .Not_A_Folder
	case .EEXIST, .ENOTEMPTY:      return .Exists
	case .EXDEV:                   return .Cross_Volume
	case .ENOSPC, .EDQUOT:         return .No_Space
	}
	return .Other
}

@(private = "file")
cpath :: proc(path: string) -> cstring { return strings.clone_to_cstring(path, context.temp_allocator) }

copy_file :: proc(from, to: string, p: ^Progress = nil) -> Error {
	src, oerr := linux.open(cpath(from), {.CLOEXEC})
	if oerr != .NONE { return op_error(oerr) }
	defer linux.close(src)
	st: linux.Stat
	if e := linux.fstat(src, &st); e != .NONE { return op_error(e) }
	mode := st.mode & {.IRUSR, .IWUSR, .IXUSR, .IRGRP, .IWGRP, .IXGRP, .IROTH, .IWOTH, .IXOTH, .ISUID, .ISGID, .ISVTX}
	dst, cerr := linux.open(cpath(to), {.WRONLY, .CREAT, .EXCL, .CLOEXEC}, mode | {.IWUSR})
	if cerr != .NONE { return op_error(cerr) }
	ok := false
	defer if !ok { linux.close(dst); linux.unlink(cpath(to)) }

	in_kernel := true
	for {
		if p != nil && p.cancelled != nil && p.cancelled(p.user) { return .Cancelled }
		n: int
		if in_kernel {
			ret := linux.syscall(linux.SYS_copy_file_range, src, uintptr(0), dst, uintptr(0), uintptr(COPY_STEP), uintptr(0))
			if ret < 0 {
				e := linux.Errno(-ret)
				// (another file system, an old kernel, a special file: the bytes through this process)
				if e == .EXDEV || e == .ENOSYS || e == .EINVAL || e == .EOPNOTSUPP {
					in_kernel = false
					continue
				}
				return op_error(e)
			}
			n = int(ret)
		} else {
			buf := make([]u8, COPY_BUFFER, context.temp_allocator)
			r, rerr := linux.read(src, buf)
			if rerr != .NONE { return op_error(rerr) }
			n = r
			for off := 0; off < r; {
				w, werr := linux.write(dst, buf[off:r])
				if werr != .NONE { return op_error(werr) }
				off += w
			}
		}
		if n == 0 { break }
		if p != nil && p.on_bytes != nil { p.on_bytes(p.user, i64(n)) }
	}
	if mode & {.IWUSR} == {} { linux.fchmod(dst, mode) }   // (written with the owner's write bit, given back as it was)
	times := [2]linux.Time_Spec{st.atime, st.mtime}
	linux.utimensat(dst, nil, &times[0], {})
	if e := linux.close(dst); e != .NONE { return op_error(e) }
	ok = true
	return .None
}

// A symbolic link made again at `to`, with the same target.
copy_link :: proc(from, to: string) -> Error {
	buf: [4096]u8
	n, err := linux.readlink(cpath(from), buf[:])
	if err != .NONE { return op_error(err) }
	return op_error(linux.symlink(cpath(string(buf[:n])), cpath(to)))
}

make_folder :: proc(path: string) -> Error {
	return op_error(linux.mkdir(cpath(path), {.IRUSR, .IWUSR, .IXUSR, .IRGRP, .IWGRP, .IXGRP, .IROTH, .IWOTH, .IXOTH}))
}

// An empty file at `path`, never over something (.Exists when the name is taken).
make_file :: proc(path: string) -> Error {
	fd, err := linux.open(cpath(path), {.WRONLY, .CREAT, .EXCL, .CLOEXEC}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
	if err != .NONE { return op_error(err) }
	linux.close(fd)
	return .None
}

// Renames `from` to `to`, never over something: .Exists when the name is taken, .Cross_Volume when it is on another
// volume.
rename :: proc(from, to: string) -> Error {
	return op_error(linux.renameat2(linux.AT_FDCWD, cpath(from), linux.AT_FDCWD, cpath(to), {.NOREPLACE}))
}

// A file, a link or an empty folder.
remove :: proc(path: string) -> Error {
	e := linux.unlink(cpath(path))
	if e == .EISDIR { e = linux.rmdir(cpath(path)) }
	return op_error(e)
}

// Whether something is at `path` (a broken link counts).
exists :: proc(path: string) -> bool {
	sx: linux.Statx
	return linux.statx(linux.AT_FDCWD, cpath(path), {.SYMLINK_NOFOLLOW}, {.TYPE}, &sx) == .NONE
}

// The device of `path` itself (links not followed).
@(private)
device_of :: proc(path: string) -> (dev: u64, ok: bool) {
	sx: linux.Statx
	if linux.statx(linux.AT_FDCWD, cpath(path), {.SYMLINK_NOFOLLOW}, {.TYPE}, &sx) != .NONE { return }
	return u64(sx.dev_major) << 32 | u64(sx.dev_minor), true
}

// Whether `a` and `b` are on one volume (a move between them is a rename).
// (a link is followed: a bookmark that links to another volume is that volume)
same_volume :: proc(a, b: string) -> bool {
	sa, sb: linux.Statx
	if linux.statx(linux.AT_FDCWD, cpath(a), {}, {.TYPE}, &sa) != .NONE { return false }
	if linux.statx(linux.AT_FDCWD, cpath(b), {}, {.TYPE}, &sb) != .NONE { return false }
	return sa.dev_major == sb.dev_major && sa.dev_minor == sb.dev_minor
}
