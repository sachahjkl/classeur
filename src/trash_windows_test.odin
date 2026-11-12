package classeur

// The Recycle Bin of Windows as a tab (trash:///): its items by their original names and folders, Put back (a name
// taken there asked about), Empty the trash. On a Recycle Bin of the test's own (fs.recycle_bins_override): the
// person's is never read nor touched. (Windows only: the body is the system's; its imports are kept on the others.)

@(require) import "base:runtime"
@(require) import "core:os"
@(require) import "core:slice"
@(require) import "core:strings"
import "core:testing"
@(require) import "gt:testkit"
@(require) import "gt:testkit/session"
@(require) import "gt:testkit/unwatched"
@(require) import "fs"

@(test)
test_recycle_bin_tab :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		unwatched.run(t, proc(t: ^testing.T) {
			files := FIXTURE
			dir := make_fixture(t, files[:])
			bin := fs.clean(testkit.temp_folder(t, "classeur_bin"), context.temp_allocator)
			// what Windows lays: the item ($R<id>) and its record ($I<id>), which says where it was
			lay :: proc(bin, id, from, text: string, folder := false) {
				item := fs.join(bin, strings.concatenate({"$R", id}, context.temp_allocator), context.temp_allocator)
				if folder {
					_ = os.make_directory_all(item)
					item = fs.join(item, "inside.txt", context.temp_allocator)
				}
				_ = os.write_entire_file(item, transmute([]u8)text)
				record := fs.recycle_record_bytes(from, i64(len(text)), 1_762_000_000_000_000_000)
				_ = os.write_entire_file(fs.join(bin, strings.concatenate({"$I", id}, context.temp_allocator), context.temp_allocator), record)
			}
			lay(bin, "A1.txt", fs.join(dir, "notes.txt", context.temp_allocator), "first")
			lay(bin, "B2.txt", fs.join(dir, "Documents\\notes.txt", context.temp_allocator), "second")
			lay(bin, "C3", fs.join(dir, "Gone\\Old", context.temp_allocator), "old", folder = true)
			// (a record whose item is gone: not listed)
			_ = os.write_entire_file(fs.join(bin, "$ID4.txt", context.temp_allocator), fs.recycle_record_bytes(fs.join(dir, "lost.txt", context.temp_allocator), 1, 0))
			bins := []string{strings.clone(bin, runtime.heap_allocator())}
			fs.recycle_bins_override = bins
			defer { fs.recycle_bins_override = nil; delete(bins[0], runtime.heap_allocator()) }

			s, app := start(t, {dir}, size = {1200, 700})
			context.allocator = runtime.heap_allocator()
			tab := current_tab(app)
			tab_go(app, tab, "trash:///")
			wait_read(s)
			testing.expect_value(t, tab.path, fs.RECYCLE_BIN)
			testing.expect(t, shows_trash(tab), "the tab is the trash")
			testing.expect_value(t, tab_title(app, tab), "Recycle Bin")
			names := shown_names(tab)
			testing.expect_value(t, len(tab.folder.listing.entries), 3)
			for n in ([]string{"notes.txt", "notes 2.txt", "Old"}) { testing.expectf(t, slice.contains(names, n), "%s listed by its original name (%v)", n, names) }
			old := folder_find_name(&tab.folder, "Old")
			if old >= 0 {
				x, ok := fs.entry_trashed(&tab.folder.listing, &tab.folder.listing.entries[old])
				testing.expect(t, ok && x.from == fs.join(dir, "Gone", context.temp_allocator), "where it was deleted from")
			}

			// Put back: a folder whose folder is gone goes back where it was, its record removed
			point_at(t, tab, "Old")
			session.key(s, .R, {.Ctrl, .Alt})
			wait_jobs(s)
			wait_read(s)
			testing.expect(t, fs.exists(fs.join(dir, "Gone\\Old\\inside.txt", context.temp_allocator)), "put back where it was")
			testing.expect(t, !fs.exists(fs.join(bin, "$RC3", context.temp_allocator)), "out of the Recycle Bin")
			testing.expect(t, !fs.exists(fs.join(bin, "$IC3", context.temp_allocator)), "its record gone")
			testing.expect(t, !slice.contains(shown_names(tab), "Old"), "the tab read again")

			// Put back onto a name taken: asked, both kept
			first := ""
			for i in 0 ..< len(tab.folder.listing.entries) {
				x, ok := fs.entry_trashed(&tab.folder.listing, &tab.folder.listing.entries[i])
				if ok && strings.has_suffix(x.item, "$RA1.txt") { first = strings.clone(tab.folder.listing.entries[i].name, context.temp_allocator) }
			}
			testing.expect(t, first != "", "the item from the fixture's folder")
			point_at(t, tab, first)
			session.key(s, .R, {.Ctrl, .Alt})
			session.wait_until(s, proc(s: ^session.Session) -> bool { return job_asking((^App)(s.user)) != nil }, "the question")
			session.wait_box(s, "both")
			session.click(s, "both")
			wait_jobs(s)
			wait_read(s)
			data, _ := os.read_entire_file(fs.join(dir, "notes 2.txt", context.temp_allocator), context.temp_allocator)
			testing.expect_value(t, string(data), "first")
			testing.expect(t, fs.exists(fs.join(dir, "notes.txt", context.temp_allocator)), "what was there stays")
			testing.expect(t, !fs.exists(fs.join(bin, "$IA1.txt", context.temp_allocator)), "its record gone")

			// Empty the trash: asked (the items by their names), then each item and its record deleted
			session.key(s, .Delete, {.Ctrl, .Shift})
			testing.expect(t, app.confirm.open && app.confirm.trash, "asked")
			testing.expect(t, len(app.confirm.names) == 1 && !strings.has_prefix(app.confirm.names[0], "$R"), "named by its original name")
			session.wait_box(s, "confirm_act")
			session.click(s, "confirm_act")
			wait_jobs(s)
			wait_read(s)
			testing.expect(t, !fs.exists(fs.join(bin, "$RB2.txt", context.temp_allocator)), "emptied")
			testing.expect(t, !fs.exists(fs.join(bin, "$IB2.txt", context.temp_allocator)), "its record too")
			testing.expect_value(t, len(tab.folder.listing.entries), 0)
		})
	}
}
