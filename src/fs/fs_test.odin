package fs

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

@(test)
test_name_compare :: proc(t: ^testing.T) {
	testing.expect(t, name_compare("file 2", "file 10") < 0)
	testing.expect(t, name_compare("file 10", "file 2") > 0)
	testing.expect(t, name_compare("File", "file") != 0)          // (never equal unless the same bytes)
	testing.expect(t, name_compare("apple", "Banana") < 0)        // (the case ignored first)
	testing.expect(t, name_compare("a007", "a7") != 0)
	testing.expect(t, name_compare("a07b", "a7c") < 0)            // (07 and 7 equal by value: b before c)
	testing.expect(t, name_compare("été", "Étude") < 0)
	testing.expect(t, name_compare("abc", "abcd") < 0)
	testing.expect(t, name_compare("x", "x") == 0)
}

@(test)
test_sort_order :: proc(t: ^testing.T) {
	entries := []Entry{
		{name = "b.txt", size = 30, mtime = 1, kind = .File},
		{name = "Zeta", size = -1, mtime = 5, kind = .Directory},
		{name = "a10.png", size = 10, mtime = 3, kind = .File},
		{name = "a9.png", size = 20, mtime = 2, kind = .File},
		{name = "alpha", size = -1, mtime = 4, kind = .Directory},
	}
	order := []u32{0, 1, 2, 3, 4}
	sort_order(entries, order, {})
	testing.expect_value(t, fmt.tprint(order), "[4, 1, 3, 2, 0]")
	sort_order(entries, order, {key = .Size, descending = true})
	testing.expect_value(t, fmt.tprint(order), "[1, 4, 0, 3, 2]")
	sort_order(entries, order, {key = .Modified, mixed = true})
	testing.expect_value(t, fmt.tprint(order), "[0, 3, 2, 4, 1]")
	sort_order(entries, order, {key = .Type})
	testing.expect_value(t, fmt.tprint(order), "[4, 1, 3, 2, 0]")

	// a larger run: the merge, against the insertion sort of each half
	many := make([]Entry, 500, context.temp_allocator)
	idx := make([]u32, 500, context.temp_allocator)
	for i in 0 ..< 500 {
		many[i] = {name = fmt.tprintf("n%d", (i * 7919) % 500), kind = .File}
		idx[i] = u32(i)
	}
	sort_order(many, idx, {})
	for i in 1 ..< 500 { testing.expect(t, name_compare(many[idx[i - 1]].name, many[idx[i]].name) < 0) }
}

@(test)
test_paths :: proc(t: ^testing.T) {
	when ODIN_OS != .Windows {
		testing.expect_value(t, clean("/a//b/./c/../d/", context.temp_allocator), "/a/b/d")
		testing.expect_value(t, clean("/..", context.temp_allocator), "/")
		testing.expect_value(t, parent("/a/b"), "/a")
		testing.expect_value(t, parent("/a"), "/")
		testing.expect_value(t, parent("/"), "")
		testing.expect_value(t, base("/a/b"), "b")
		testing.expect_value(t, base("/"), "/")
		testing.expect_value(t, join("/", "a", context.temp_allocator), "/a")
		testing.expect_value(t, join("/a", "b", context.temp_allocator), "/a/b")
		c := crumbs("/home/me")
		testing.expect_value(t, len(c), 3)
		testing.expect_value(t, c[0].path, "/")
		testing.expect_value(t, c[2].path, "/home/me")
		testing.expect_value(t, c[2].name, "me")
	} else {
		testing.expect_value(t, clean("c:/Users//me/", context.temp_allocator), "c:\\Users\\me")
		testing.expect_value(t, clean("D:", context.temp_allocator), "D:\\")
		testing.expect_value(t, parent("C:\\a"), "C:\\")
		testing.expect_value(t, parent("C:\\"), "")
		c := crumbs("C:\\Users\\me")
		testing.expect_value(t, len(c), 3)
		testing.expect_value(t, c[0].path, "C:\\")
	}
	testing.expect_value(t, extension("photo.JPG"), "JPG")
	testing.expect_value(t, extension(".bashrc"), "")
	testing.expect_value(t, extension("archive.tar.gz"), "gz")
	testing.expect_value(t, extension("dot."), "")
}

@(test)
test_list :: proc(t: ^testing.T) {
	dir := join(os.get_env("TMPDIR", context.temp_allocator) != "" ? os.get_env("TMPDIR", context.temp_allocator) : "/tmp", fmt.tprintf("classeur_fs_test_%d", os.get_pid()), context.temp_allocator)
	when ODIN_OS == .Windows { dir = join(os.get_env("TEMP", context.temp_allocator), fmt.tprintf("classeur_fs_test_%d", os.get_pid()), context.temp_allocator) }
	_ = os.make_directory_all(join(dir, "sub", context.temp_allocator))
	defer os.remove_all(dir)
	testing.expect(t, os.write_entire_file(join(dir, "hello.txt", context.temp_allocator), transmute([]u8)string("hello")) == nil)
	testing.expect(t, os.write_entire_file(join(dir, ".hidden", context.temp_allocator), transmute([]u8)string("")) == nil)

	l: Listing
	defer listing_destroy(&l)
	testing.expect_value(t, list(&l, dir), Error.None)
	testing.expect_value(t, len(l.entries), 3)
	seen := 0
	for e in l.entries {
		switch e.name {
		case "hello.txt":
			seen += 1
			testing.expect_value(t, e.kind, Kind.File)
			testing.expect_value(t, e.size, 5)
			testing.expect(t, e.mtime > 0)
		case "sub":
			seen += 1
			testing.expect_value(t, e.kind, Kind.Directory)
			testing.expect_value(t, e.size, -1)
		case ".hidden":
			seen += 1
			when ODIN_OS != .Windows { testing.expect(t, .Hidden in e.flags) }
		}
	}
	testing.expect_value(t, seen, 3)
	testing.expect_value(t, list(&l, join(dir, "missing", context.temp_allocator)), Error.Not_Found)
	testing.expect_value(t, list(&l, join(dir, "hello.txt", context.temp_allocator)), Error.Not_A_Folder)
}

@(test)
test_operations :: proc(t: ^testing.T) {
	dir := join(os.get_env("TMPDIR", context.temp_allocator) != "" ? os.get_env("TMPDIR", context.temp_allocator) : "/tmp", fmt.tprintf("classeur_ops_test_%d", os.get_pid()), context.temp_allocator)
	when ODIN_OS == .Windows { dir = join(os.get_env("TEMP", context.temp_allocator), fmt.tprintf("classeur_ops_test_%d", os.get_pid()), context.temp_allocator) }
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	a := join(dir, "a.txt", context.temp_allocator)
	b := join(dir, "b.txt", context.temp_allocator)
	data := make([]u8, 3 * 1024 * 1024 + 7, context.temp_allocator)
	for &c, i in data { c = u8(i * 31) }
	testing.expect(t, os.write_entire_file(a, data) == nil)

	seen: i64
	p := Progress{user = &seen, on_bytes = proc(user: rawptr, n: i64) { (^i64)(user)^ += n }}
	testing.expect_value(t, copy_file(a, b, &p), Error.None)
	testing.expect_value(t, seen, i64(len(data)))
	got, _ := os.read_entire_file(b, context.temp_allocator)
	testing.expect(t, string(got) == string(data), "the copy has the same bytes")
	testing.expect_value(t, copy_file(a, b), Error.Exists)

	// a cancelled copy leaves nothing
	c := join(dir, "c.txt", context.temp_allocator)
	stop := Progress{cancelled = proc(user: rawptr) -> bool { return true }}
	testing.expect_value(t, copy_file(a, c, &stop), Error.Cancelled)
	testing.expect(t, !exists(c))

	testing.expect_value(t, rename(a, b), Error.Exists)
	testing.expect_value(t, rename(a, c), Error.None)
	testing.expect(t, !exists(a) && exists(c))
	testing.expect_value(t, make_folder(join(dir, "sub", context.temp_allocator)), Error.None)
	testing.expect_value(t, make_folder(join(dir, "sub", context.temp_allocator)), Error.Exists)
	testing.expect_value(t, remove(join(dir, "sub", context.temp_allocator)), Error.None)
	testing.expect_value(t, remove(c), Error.None)
	// a new file never over another; one volume with itself
	n := join(dir, "made.txt", context.temp_allocator)
	testing.expect_value(t, make_file(n), Error.None)
	testing.expect_value(t, make_file(b), Error.Exists)
	got2, _ := os.read_entire_file(b, context.temp_allocator)
	testing.expect_value(t, len(got2), len(data))   // (left whole)
	testing.expect(t, same_volume(n, dir))
	testing.expect(t, !same_volume(n, join(dir, "nowhere", context.temp_allocator)))

	testing.expect_value(t, numbered_name("photo.jpg", 2, context.temp_allocator), "photo 2.jpg")
	testing.expect_value(t, numbered_name("Projects", 3, context.temp_allocator), "Projects 3")
	testing.expect_value(t, free_name(dir, "b.txt", context.temp_allocator), "b 2.txt")
	testing.expect_value(t, free_name(dir, "new.txt", context.temp_allocator), "new.txt")
}

// A walk read by several threads hands its entries out as it goes: batches before the end, never more than the final
// listing, and that one whole.
@(test)
test_walk_progress :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()   // (the walk's threads allocate: the test's tracking allocator is one thread's)
	root := join(os.get_env("TMPDIR", context.temp_allocator) != "" ? os.get_env("TMPDIR", context.temp_allocator) : "/tmp", fmt.tprintf("classeur_walk_%d", os.get_pid()), context.temp_allocator)
	when ODIN_OS == .Windows { root = join(os.get_env("TEMP", context.temp_allocator), fmt.tprintf("classeur_walk_%d", os.get_pid()), context.temp_allocator) }
	defer os.remove_all(root)
	FOLDERS :: 300
	for i in 0 ..< FOLDERS {
		dir := join(root, fmt.tprintf("d%d", i), context.temp_allocator)
		testing.expect(t, os.make_directory_all(dir) == nil)
		for k in 0 ..< 2 { testing.expect(t, os.write_entire_file(join(dir, fmt.tprintf("f%d.txt", k), context.temp_allocator), "x") == nil) }
	}
	Seen :: struct { batches, entries: int }
	seen: Seen
	l: Listing
	defer listing_destroy(&l)
	// (each folder a little slow: the walk lasts past a batch's period)
	err := walk(&l, root, nil, proc(user: rawptr) -> bool { time.sleep(2 * time.Millisecond); return false }, &seen, proc(user: rawptr, batch: ^Listing) {
		s := (^Seen)(user)
		s.batches += 1
		s.entries += len(batch.entries)
		listing_destroy(batch)
	})
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, len(l.entries), FOLDERS * 3)
	testing.expect(t, seen.batches > 0, "batches before the end")
	testing.expect(t, seen.entries <= len(l.entries), "never more than the listing")
}
