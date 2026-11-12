// fs: what classeur reads of the file system, the same on every system. A folder is read in one call (`list`) into a
// `Listing`: one array of entries, their names in one arena. The system's part is in `fs_<os>.odin`; no type of the
// system crosses this interface.
package fs

import "core:mem/virtual"
import "core:strings"

Kind :: enum u8 {
	File,
	Directory,
	Other,        // a device, a pipe, a socket
	Broken_Link,  // a symbolic link whose target cannot be read
}

Flag :: enum u8 {
	Hidden,      // a dot file, or the Hidden attribute on Windows
	Link,        // a symbolic link (its kind is its target's) or a junction
	Executable,  // POSIX: an execute bit is set
	Read_Only,
	System,      // Windows: the System attribute
}
Flags :: bit_set[Flag; u8]

Entry :: struct {
	name:  string,   // in the listing's arena
	size:  i64,      // bytes; a folder: -1 (not measured)
	mtime: i64,      // nanoseconds since 1970-01-01 UTC
	kind:  Kind,
	flags: Flags,
}

Error :: enum u8 {
	None,
	Not_Found,
	Denied,
	Not_A_Folder,
	Exists,         // the name is taken
	Cross_Volume,   // a rename to another volume: copy, then delete
	No_Space,
	Cancelled,
	Read_Only,      // in an archive: what is in it is read, never written
	Other,
}

// What a listing's error says in the list.
ERROR_TEXT := [Error]string {
	.None         = "",
	.Not_Found    = "This folder does not exist.",
	.Denied       = "You do not have the permission to read this folder.",
	.Not_A_Folder = "This is not a folder.",
	.Exists       = "The name is taken.",
	.Cross_Volume = "This is on another volume.",
	.No_Space     = "The volume is full.",
	.Cancelled    = "Cancelled.",
	.Read_Only    = "An archive is read only: copy what is in it out of it.",
	.Other        = "This folder cannot be read.",
}

// What an error says after a file's name ("cannot be copied: ...").
ERROR_REASON := [Error]string {
	.None         = "",
	.Not_Found    = "it is not there",
	.Denied       = "permission denied",
	.Not_A_Folder = "it is not a folder",
	.Exists       = "the name is taken",
	.Cross_Volume = "it is on another volume",
	.No_Space     = "the volume is full",
	.Cancelled    = "cancelled",
	.Read_Only    = "an archive is read only",
	.Other        = "the system refused",
}

// What a long operation (a copy) reports as it goes, and how it is stopped. Both are called on the thread that copies.
Progress :: struct {
	user:      rawptr,
	on_bytes:  proc(user: rawptr, bytes: i64),   // bytes written since the last call
	cancelled: proc(user: rawptr) -> bool,
}

// A folder as it was read.
Listing :: struct {
	path:    string,            // in `arena`
	entries: [dynamic]Entry,
	arena:   virtual.Arena,     // the path and the names
	error:   Error,
	// per entry, when the entries are not in `path`: the Recycle Bin of Windows, whose items are listed by their
	// original names (an entry past its end, or none: in `path`)
	trashed: [dynamic]Trashed,
}

// An item of a trash listed by its original name: where it is, and the folder it was in (both in the listing's arena).
Trashed :: struct {
	item: string,
	from: string,
}

// Reads the folder at `path` into `l` (made empty first). The entries come in the system's order.
list :: proc(l: ^Listing, path: string) -> Error {
	// (an archive, or a folder of one: listed from its index)
	if file, inner, ok := archive_split(path); ok { return archive_list(l, path, file, inner) }
	listing_reset(l)
	l.path = strings.clone(path, virtual.arena_allocator(&l.arena))
	// (a trash that is no folder: its items, from wherever the system keeps them)
	if e, done := list_trash(l, path); done {
		l.error = e
		return e
	}
	l.error = list_native(l, path)
	return l.error
}

listing_reset :: proc(l: ^Listing) {
	clear(&l.entries)
	clear(&l.trashed)
	virtual.arena_destroy(&l.arena)
	l.arena = {}
	l.path = ""
	l.error = .None
}

listing_destroy :: proc(l: ^Listing) {
	delete(l.entries)
	delete(l.trashed)
	virtual.arena_destroy(&l.arena)
	l^ = {}
}

// Where an entry of `l` (a pointer into its entries) is when it is not in the listing's folder, and where it came
// from; ok = false: it is in it (join(l.path, e.name)).
entry_trashed :: proc(l: ^Listing, e: ^Entry) -> (t: Trashed, ok: bool) {
	if len(l.trashed) == 0 || len(l.entries) == 0 || e == nil { return }
	first, at := uintptr(rawptr(&l.entries[0])), uintptr(rawptr(e))
	if at < first { return }
	i := int((at - first) / size_of(Entry))
	if i >= len(l.trashed) || i >= len(l.entries) { return }
	return l.trashed[i], true
}

// A name kept in the listing's arena (a listing made of several: the tree's).
keep_name :: proc(l: ^Listing, name: string) -> string {
	return strings.clone(name, virtual.arena_allocator(&l.arena))
}

// What the inspector's properties say of a path (properties): what Info does not.
Properties :: struct {
	created:     i64,      // ns since 1970 UTC (0: the system does not say)
	accessed:    i64,
	permissions: string,   // Linux: "rwxr-xr-x (755)"; Windows: its attributes ("Read only, Hidden"); "" none
	owner:       string,   // Linux: "user:group"; "" not known
}

// What a path is, its size and its time (links followed). ok is false when it cannot be read.
Info :: struct {
	kind:  Kind,
	size:  i64,
	mtime: i64,
	flags: Flags,
}

// The free and the total bytes of the volume that holds `path`.
Space :: struct {
	free, total: i64,
}

// A volume to open from the sidebar: a drive, a mounted device or share.
Volume :: struct {
	path:      string,
	label:     string,
	removable: bool,
}

volumes_destroy :: proc(v: []Volume, allocator := context.allocator) {
	for x in v {
		delete(x.path, allocator)
		delete(x.label, allocator)
	}
	delete(v, allocator)
}
