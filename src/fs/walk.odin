package fs

// The flat view of a tree (File Pilot's search): every entry under a folder in one listing, each named by its path from
// that folder ("Projects/site/index.html"). Folders are read one after the other from a stack; links to folders are
// listed, not followed.

import "core:strings"
import "core:sync"

// Reads every entry under `root` into `l` (made empty first). `count` (atomic) grows as entries are read, for a
// progress; the walk ends early when `stop` says so (its error is then .Cancelled). A folder that cannot be read is
// skipped.
walk :: proc(l: ^Listing, root: string, count: ^int = nil, stop: proc(user: rawptr) -> bool = nil, user: rawptr = nil) -> Error {
	listing_reset(l)
	l.path = keep_name(l, root)
	pending := make([dynamic]string, context.temp_allocator)   // relative paths, in l's arena
	append(&pending, "")
	one: Listing
	defer listing_destroy(&one)
	first := true
	for len(pending) > 0 {
		if stop != nil && stop(user) { return .Cancelled }
		rel := pop(&pending)
		dir := rel == "" ? root : join(root, rel, context.temp_allocator)
		err := list(&one, dir)
		if err != .None {
			if first { l.error = err; return err }
			continue
		}
		first = false
		for e in one.entries {
			x := e
			x.name = rel == "" ? keep_name(l, e.name) : keep_name(l, strings.concatenate({rel, SEPARATOR_STRING, e.name}, context.temp_allocator))
			append(&l.entries, x)
			if e.kind == .Directory && .Link not_in e.flags { append(&pending, x.name) }
		}
		if count != nil { sync.atomic_add(count, len(one.entries)) }
	}
	return .None
}
