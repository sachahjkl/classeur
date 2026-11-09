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
}

// Reads the folder at `path` into `l` (made empty first). The entries come in the system's order.
list :: proc(l: ^Listing, path: string) -> Error {
	listing_reset(l)
	l.path = strings.clone(path, virtual.arena_allocator(&l.arena))
	l.error = list_native(l, path)
	return l.error
}

listing_reset :: proc(l: ^Listing) {
	clear(&l.entries)
	virtual.arena_destroy(&l.arena)
	l.arena = {}
	l.path = ""
	l.error = .None
}

listing_destroy :: proc(l: ^Listing) {
	delete(l.entries)
	virtual.arena_destroy(&l.arena)
	l^ = {}
}

// A name kept in the listing's arena.
@(private)
keep_name :: proc(l: ^Listing, name: string) -> string {
	return strings.clone(name, virtual.arena_allocator(&l.arena))
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
