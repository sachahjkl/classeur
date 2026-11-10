package fs

// The operations as the program calls them: an archive's folder (archive.odin) is read by them as a folder is, and refuses
// every write (`Read_Only`); anything else is the system's (the *_native procedures of fs_<os>.odin and ops_<os>.odin).

// What a path is, its size and its time (links followed). ok is false when it cannot be read.
stat :: proc(path: string) -> (info: Info, ok: bool) {
	// (the archive's file is a file: only what is in it is the archive's)
	if a, inner, in_one := archive_split(path); in_one && inner != "" { return archive_stat(a, inner) }
	return stat_native(path)
}

// Copies the file `from` to `to` (a file of an archive: taken out of it).
copy_file :: proc(from, to: string, p: ^Progress = nil) -> Error {
	if archive_holds(to) { return .Read_Only }
	if a, inner, in_one := archive_split(from); in_one && inner != "" { return archive_copy(a, inner, to) }
	return copy_file_native(from, to, p)
}

make_folder :: proc(path: string) -> Error {
	if archive_holds(path) { return .Read_Only }
	return make_folder_native(path)
}

make_file :: proc(path: string) -> Error {
	if archive_holds(path) { return .Read_Only }
	return make_file_native(path)
}

rename :: proc(from, to: string) -> Error {
	if archive_holds(from) || archive_holds(to) { return .Read_Only }
	return rename_native(from, to)
}

remove :: proc(path: string) -> Error {
	if archive_holds(path) { return .Read_Only }
	return remove_native(path)
}

exists :: proc(path: string) -> bool {
	if a, inner, in_one := archive_split(path); in_one && inner != "" { _, ok := archive_stat(a, inner); return ok }
	return exists_native(path)
}

// Moves `path` to the system's trash; where it went (to put it back).
trash :: proc(path: string, allocator := context.allocator) -> (in_trash: string, e: Error) {
	if archive_holds(path) { return "", .Read_Only }
	return trash_native(path, allocator)
}
