package classeur

// The long reads: a flat search of a large tree (its batches merged into the rows), a change made while a folder is
// read, closing while a walk runs, the measures of one panel when another goes elsewhere.

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:sync"
import "core:testing"
import "core:time"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

// `folders` folders "dNN" under `dir`, each with `files` files "fNNN.txt".
@(private = "file")
write_tree :: proc(dir: string, folders, files: int) {
	for d in 0 ..< folders {
		sub := fs.join(dir, fmt.tprintf("d%02d", d), context.temp_allocator)
		_ = os.make_directory_all(sub)
		for n in 0 ..< files {
			_ = os.write_entire_file(fs.join(sub, fmt.tprintf("f%03d.txt", n), context.temp_allocator), transmute([]u8)string("x"))
		}
	}
}

// A flat search of a tree of a few thousand files: every entry a row, named by its path; a filter keeps its own.
@(test)
test_flat_search_tree :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {})
		write_tree(dir, 30, 100)
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		session.key(s, .F, {.Ctrl, .Shift})
		wait_read(s)
		testing.expect(t, tab.folder.flat)
		names := shown_names(tab)
		testing.expect_value(t, len(names), 30 + 30 * 100)
		testing.expect(t, slice.contains(names, fs.join("d07", "f042.txt", context.temp_allocator)))
		testing.expect(t, slice.contains(names, "d29"))
		// "f042": that file of each folder
		session.type_text(s, "f042")
		names = shown_names(tab)
		testing.expect_value(t, len(names), 30)
		for n in names { testing.expect_value(t, fs.base(n), "f042.txt") }
	})
}

@(private = "file")
listing_of :: proc(entries: []fs.Entry) -> fs.Listing {
	l: fs.Listing
	l.path = fs.keep_name(&l, "/x")
	for e in entries {
		x := e
		x.name = fs.keep_name(&l, e.name)
		append(&l.entries, x)
	}
	return l
}

// A walk's batches merged into the rows give the rows of the whole listing read at once: filtered, grouped or not.
@(test)
test_batches_merged :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		N :: 1200
		BATCH :: 100
		exts := [?]string{"txt", "pdf", "png", "md"}
		all := make([]fs.Entry, N, context.temp_allocator)
		for &e, k in all {
			// (a walk's order: not the sort's)
			p := (k * 7919) % N
			e = {name = fmt.tprintf("n%d.%s", p, exts[p % len(exts)]), kind = .File, size = i64((p * 37) % 5000)}
			if p % 10 == 0 { e.kind, e.size = .Directory, -1 }
			if p % 13 == 0 { e.flags += {.Hidden} }
		}
		Case :: struct { filter: string, group: Group_By }
		cases := [?]Case{{"", .None}, {"n1", .None}, {"", .Type}, {"", .Size}, {"n1", .Type}}
		for c in cases {
			merged, whole: Folder
			first := listing_of(all[:BATCH])
			folder_set_listing(&merged, &first)
			folder_set_filter(&merged, c.filter)
			folder_set_group(&merged, c.group, 0, nil)
			for at := BATCH; at < N; at += BATCH {
				batch := listing_of(all[at:min(at + BATCH, N)])
				folder_add_entries(&merged, &batch)
				fs.listing_destroy(&batch)
			}
			full := listing_of(all)
			folder_set_listing(&whole, &full)
			folder_set_filter(&whole, c.filter)
			folder_set_group(&whole, c.group, 0, nil)

			testing.expectf(t, len(merged.shown) == len(whole.shown), "%v: %d rows, %d expected", c, len(merged.shown), len(whole.shown))
			same := len(merged.shown) == len(whole.shown)
			for k in 0 ..< min(len(merged.shown), len(whole.shown)) {
				if merged.listing.entries[merged.shown[k]].name != whole.listing.entries[whole.shown[k]].name { same = false; break }
			}
			testing.expectf(t, same, "%v: the rows in the order of the whole listing", c)
			testing.expectf(t, slice.equal(merged.ids[:], whole.ids[:]), "%v: the rows' ids", c)
			testing.expect_value(t, merged.size_max, whole.size_max)
			folder_destroy(&merged)
			folder_destroy(&whole)
		}
	})
}

// A change made while the folder is read (the watcher's word comes during the read): the folder is read again once the
// read comes, and shows it.
@(test)
test_change_while_read :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		before := tab.serial
		tab_load(app, tab)
		_ = os.write_entire_file(fs.join(dir, "late.txt", context.temp_allocator), transmute([]u8)string("x"))
		tab.reload_due = true   // (what folder_changed does for a tab that reads)
		wait_read(s)
		testing.expect(t, tab.serial >= before + 2, "read again")
		testing.expect(t, !tab.reload_due)
		testing.expect(t, slice.contains(shown_names(tab), "late.txt"), "the file made during the read")
	})
}

// Closing while a flat search walks a large tree: the walk stops, closing does not wait for its end.
@(test)
test_close_during_walk :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		dir := make_fixture(t, {})
		write_tree(dir, 200, 100)
		folders := []string{dir}
		app := app_open({folders = folders, headless = true})
		if !testing.expect(t, app != nil, "classeur opens") { return }
		tab := current_tab(app)
		tab.flat = true
		tab_load(app, tab)
		// (the walk under way: its first folder read)
		job := tab.walk
		for _ in 0 ..< 2000 {
			if sync.atomic_load(&job.count) > 0 { break }
			time.sleep(time.Millisecond)
		}
		began := time.tick_now()
		app_close(app)
		took := time.duration_seconds(time.tick_since(began))
		testing.expectf(t, took < 1, "closed in %.2f s", took)
	})
}

// A panel that goes elsewhere stops its own measures; those of the other panel go on.
@(test)
test_measures_of_other_panel :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Left/", "Left/Inner/", "Left/Other/", "Right/"})
		write_tree(fs.join(dir, "Right", context.temp_allocator), 40, 50)
		s, app := start(t, {fs.join(dir, "Left", context.temp_allocator)})
		context.allocator = runtime.heap_allocator()
		left := current_tab(app)
		panel_open(app, fs.join(dir, "Right", context.temp_allocator))
		right := current_tab(app)
		wait_read(s)
		testing.expect(t, left.id in app.measure_asks, "the left panel's folders asked")
		ask := app.measure_asks[right.id]
		testing.expect(t, ask != nil, "the right panel's folders asked")

		tab_go(app, left, fs.join(dir, "Left/Inner", context.temp_allocator))
		testing.expect(t, left.id not_in app.measure_asks, "the left panel's ask dropped")
		testing.expect(t, app.measure_asks[right.id] == ask, "the right panel's ask kept")
		if ask != nil { testing.expect(t, !sync.atomic_load(&ask.cancel), "the right panel's measures go on") }
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			app := (^App)(s.user)
			right := current_tab(app)
			for i in right.folder.shown {
				e := right.folder.listing.entries[i]
				if e.kind != .Directory { continue }
				if _, ok := measure_of(app, right, e); !ok { return false }
			}
			return true
		}, "the right panel's folders measured")
		m, _ := measure_of(app, right, right.folder.listing.entries[folder_find_name(&right.folder, "d07")])
		testing.expect_value(t, m.files, i64(50))
	})
}
