package fs

// Archives as folders (File Pilot's): a zip, a tar or a gzipped tar is entered as a folder, its path then going on inside
// it ("/home/me/photos.zip/2024/june"). Read only: what is in it is listed, stat'ed, copied out (the toolkit's archive
// package takes it out); every write is refused (Read_Only). The indexes read are kept (ARCHIVES_KEPT), each until its
// file changes: entering a folder of a large archive does not read it again. The workers call these at once: a lock.

import "core:os"
import "core:strings"
import "core:sync"
import archive "gt:archive"

ARCHIVES_KEPT :: 8

@(private = "file")
Kept :: struct {
	path:  string,   // owned
	mtime: i64,
	size:  i64,
	idx:   archive.Index,
	used:  u64,
}

@(private = "file")
archives: struct {
	lock: sync.Mutex,
	kept: [dynamic]Kept,
	tick: u64,
}

// Whether the name is an archive's that classeur enters (.zip, .tar, .tar.gz, .tgz).
is_archive_name :: proc(name: string) -> bool {
	_, ok := archive.kind_of(name)
	return ok
}

// The archive a path is in, and the path inside it ("" its top). ok = false: not in an archive. Only the parts of the
// path named as an archive are looked at on the disk (a file, not a folder named so).
archive_split :: proc(path: string) -> (file, inner: string, ok: bool) {
	for i := 0; i < len(path); i += 1 {
		if i + 1 < len(path) && !is_separator(path[i + 1]) { continue }
		head := path[:i + 1]
		if !is_archive_name(head) { continue }
		info, found := stat_native(head)
		if !found || info.kind != .File { continue }
		rest := path[i + 1:]
		for len(rest) > 0 && is_separator(rest[0]) { rest = rest[1:] }
		inner_name, _ := strings.replace_all(rest, "\\", "/", context.temp_allocator)
		return head, inner_name, true
	}
	return
}

// Whether a path is in an archive or is one entered as a folder (a write there is refused); the archive's own file is
// not "in" it: it can be renamed, trashed.
archive_holds :: proc(path: string) -> bool {
	_, inner, ok := archive_split(path)
	return ok && inner != ""
}

// The index of `file`, read or kept; run `body` with it under the lock.
@(private = "file")
with_index :: proc(file: string, body: proc(idx: ^archive.Index, user: rawptr) -> Error, user: rawptr) -> Error {
	info, found := stat_native(file)
	if !found { return .Not_Found }
	sync.mutex_lock(&archives.lock)
	defer sync.mutex_unlock(&archives.lock)
	archives.tick += 1
	for &k in archives.kept {
		if k.path != file { continue }
		if k.mtime == info.mtime && k.size == info.size {
			k.used = archives.tick
			return body(&k.idx, user)
		}
		// (the file changed: read again)
		archive.index_destroy(&k.idx)
		idx, err := archive.open(file)
		if err != .None { return .Other }
		k.idx, k.mtime, k.size, k.used = idx, info.mtime, info.size, archives.tick
		return body(&k.idx, user)
	}
	idx, err := archive.open(file)
	if err != .None { return err == .Unreadable ? .Denied : .Other }
	if len(archives.kept) >= ARCHIVES_KEPT {
		oldest := 0
		for k, i in archives.kept { if k.used < archives.kept[oldest].used { oldest = i } }
		delete(archives.kept[oldest].path)
		archive.index_destroy(&archives.kept[oldest].idx)
		unordered_remove(&archives.kept, oldest)
	}
	append(&archives.kept, Kept{path = strings.clone(file), mtime = info.mtime, size = info.size, idx = idx, used = archives.tick})
	return body(&archives.kept[len(archives.kept) - 1].idx, user)
}

// The folder `inner` of the archive `file`, listed into `l` (made empty first; `path` is the archive's path joined).
archive_list :: proc(l: ^Listing, path, file, inner: string) -> Error {
	listing_reset(l)
	l.path = keep_name(l, path)
	Ask :: struct { l: ^Listing, inner: string, found: bool }
	ask := Ask{l = l, inner = inner}
	err := with_index(file, proc(idx: ^archive.Index, user: rawptr) -> Error {
		a := (^Ask)(user)
		if a.inner != "" {
			e := archive.find(idx, a.inner)
			// (a folder it names only through its files is a folder too)
			is_dir := e != nil && e.dir
			if e == nil {
				prefix := strings.concatenate({a.inner, "/"}, context.temp_allocator)
				for x in idx.entries { if strings.has_prefix(x.name, prefix) { is_dir = true; break } }
				if !is_dir { return .Not_Found }
			}
			if !is_dir { return .Not_A_Folder }
		}
		list := make([dynamic]archive.Entry, context.temp_allocator)
		archive.children(idx, a.inner, &list)
		for x in list {
			name := x.name
			if slash := strings.last_index_byte(name, '/'); slash >= 0 { name = name[slash + 1:] }
			append(&a.l.entries, Entry{name = keep_name(a.l, name), kind = x.dir ? .Directory : .File, size = x.dir ? -1 : x.size, mtime = x.mtime})
		}
		return .None
	}, &ask)
	l.error = err
	return err
}

// What a path in an archive is.
archive_stat :: proc(file, inner: string) -> (info: Info, ok: bool) {
	if inner == "" { return Info{kind = .Directory, size = -1}, true }
	Ask :: struct { inner: string, info: Info, ok: bool }
	ask := Ask{inner = inner}
	_ = with_index(file, proc(idx: ^archive.Index, user: rawptr) -> Error {
		a := (^Ask)(user)
		if e := archive.find(idx, a.inner); e != nil {
			a.info = Info{kind = e.dir ? .Directory : .File, size = e.dir ? -1 : e.size, mtime = e.mtime}
			a.ok = true
			return .None
		}
		prefix := strings.concatenate({a.inner, "/"}, context.temp_allocator)
		for x in idx.entries {
			if strings.has_prefix(x.name, prefix) { a.info, a.ok = Info{kind = .Directory, size = -1}, true; break }
		}
		return .None
	}, &ask)
	return ask.info, ask.ok
}

// A file of an archive taken out to `to`.
archive_copy :: proc(file, inner, to: string) -> Error {
	Ask :: struct { inner, to: string }
	ask := Ask{inner, to}
	return with_index(file, proc(idx: ^archive.Index, user: rawptr) -> Error {
		a := (^Ask)(user)
		switch archive.extract(idx, a.inner, a.to) {
		case .None:          return .None
		case .Not_Found:     return .Not_Found
		case .Unreadable:    return .Denied
		case .Not_An_Archive, .Bad_Data, .Unsupported, .Too_Large, .Unsafe_Name: return .Other
		}
		return .Other
	}, &ask)
}

// A file of an archive taken out to a folder of the system's temporary place (to be opened by another program); its path
// there (temp memory), "" when it cannot be.
archive_take_out :: proc(path: string) -> string {
	file, inner, ok := archive_split(path)
	if !ok || inner == "" { return "" }
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	when ODIN_OS == .Windows { tmp = os.get_env("TEMP", context.temp_allocator) }
	if tmp == "" { tmp = "/tmp" }
	dir := join(join(tmp, "classeur-archives", context.temp_allocator), name_key(base(file), context.temp_allocator), context.temp_allocator)
	out := join(dir, base(inner), context.temp_allocator)
	if archive_copy(file, inner, out) != .None { return "" }
	return out
}
