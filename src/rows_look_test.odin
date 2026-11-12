package classeur

// How the rows read: the Size column's bars and the counts' cells, what is cut (dimmed) and what a paste made
// (selected), the footer's counts and what it says of the rows, the cards' long names.

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "gt:ui"
import "fs"

// The box named `name` under `b` (b itself included), nil: none.
@(private = "file")
box_under :: proc(b: ^ui.Box, name: string) -> ^ui.Box {
	if b == nil { return nil }
	if b.name == name { return b }
	for c := b.first; c != nil; c = c.next { if r := box_under(c, name); r != nil { return r } }
	return nil
}

// The number a count of the footer shows.
@(private = "file")
stat_text :: proc(s: ^session.Session, id: string) -> string {
	return ui.box_text(box_under(session.find(s, fmt.tprintf("stat_%s", id)), "v"))
}

@(private = "file")
entry_named :: proc(f: ^Folder, name: string) -> fs.Entry {
	return f.listing.entries[folder_find_name(f, name)]
}

@(test)
test_size_column_cells :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Sub/", "tiny.txt"})
		_ = os.write_entire_file(fs.join(dir, "large.bin", context.temp_allocator), make([]u8, 100_000, context.temp_allocator))
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder

		// a file has no counts: its cells are empty
		folders, files := entry_counts_text(app, tab, entry_named(f, "tiny.txt"))
		testing.expect_value(t, folders, "")
		testing.expect_value(t, files, "")
		// a folder: its counts once measured (an empty one: 0 and 0)
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			app := (^App)(s.user)
			tab := current_tab(app)
			_, ok := measure_of(app, tab, entry_named(&tab.folder, "Sub"))
			return ok
		}, "the folder measured")
		folders, files = entry_counts_text(app, tab, entry_named(f, "Sub"))
		testing.expect_value(t, folders, "0")
		testing.expect_value(t, files, "0")

		// a tiny file beside a large one: under 2 % of it, no bar (a stray dot); the large one has its bar
		testing.expect_value(t, f.size_max, i64(100_000))
		testing.expect(t, !size_bar_shown(entry_named(f, "tiny.txt").size, f.size_max), "no bar for a tiny file")
		testing.expect(t, size_bar_shown(entry_named(f, "large.bin").size, f.size_max), "a bar for the largest")
	})
}

@(test)
test_cut_and_pasted :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Dest/", "a.txt", "b.txt", "c.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		f := &tab.folder

		// cut a.txt and b.txt: their rows are dimmed, c.txt is not
		testing.expect(t, folder_cursor_to_name(f, "a.txt"))
		folder_pick(f, f.cursor)
		testing.expect(t, folder_cursor_to_name(f, "b.txt"))
		folder_pick(f, f.cursor, toggle = true)
		session.key(s, .X, {.Ctrl})
		session.frames(s, 2)
		testing.expect(t, row_is_cut(app, fs.join(dir, "a.txt", context.temp_allocator)), "a.txt cut")
		testing.expect(t, row_is_cut(app, fs.join(dir, "b.txt", context.temp_allocator)), "b.txt cut")
		testing.expect(t, !row_is_cut(app, fs.join(dir, "c.txt", context.temp_allocator)), "c.txt not cut")
		dimmed := session.find(s, "cut")
		testing.expect(t, dimmed != nil && dimmed.transparency == CUT_TRANSPARENCY, "a cut row's cells are dimmed")
		testing.expect(t, session.find(s, "cut", 2) == nil, "two rows dimmed, not three")

		// pasted in Dest: moved there, selected there, the cursor on the first; nothing is cut any more
		testing.expect(t, folder_cursor_to_name(f, "Dest"))
		folder_pick(f, f.cursor)
		session.key(s, .Return)
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Dest")
		session.key(s, .V, {.Ctrl})
		wait_jobs(s)
		testing.expect(t, fs.exists(fs.join(dir, "Dest/a.txt", context.temp_allocator)), "a.txt moved")
		testing.expect_value(t, len(app.cut), 0)
		testing.expect_value(t, f.count, 2)
		testing.expect(t, f.selected[folder_find_name(f, "a.txt")], "a.txt selected")
		testing.expect(t, f.selected[folder_find_name(f, "b.txt")], "b.txt selected")
		testing.expect_value(t, folder_cursor_entry(f).name, "a.txt")
		session.frames(s, 2)
		testing.expect(t, session.find(s, "cut") == nil, "no row dimmed once pasted")
	})
}

@(test)
test_footer_counts :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a1.txt", "a2.txt", "a3.txt", "b1.md", "b2.md", "b3.md", "b4.md"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)

		// nothing filtered: the count alone
		testing.expect_value(t, stat_text(s, "fil"), "7")
		// a filter hides rows: shown of all
		session.key(s, .F, {.Ctrl})
		session.type_text(s, "a")
		session.frames(s, 2)
		testing.expect_value(t, len(tab.folder.shown), 3)
		testing.expect_value(t, stat_text(s, "fil"), "3/7")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect_value(t, stat_text(s, "fil"), "7")

		// the cursor's item, then nothing when three are selected
		session.key(s, .Home)
		session.frames(s, 2)
		info := ui.box_text(session.find(s, "item_info"))
		testing.expectf(t, strings.has_prefix(info, "a1.txt · "), "the cursor's item: %q", info)
		session.key(s, .Down, {.Shift}, repeat = 2)
		session.frames(s, 2)
		testing.expect_value(t, tab.folder.count, 3)
		// (three: the selection's count says it, not the left part again)
		info_box := session.find(s, "item_info")
		testing.expect(t, info_box == nil || ui.box_text(info_box) == "", "three selected: no item described")
	})
}

@(test)
test_card_long_name :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		long :: "a very long name of a report that goes on and on for many words before it comes to its end at last.txt"
		dir := make_fixture(t, {long})
		s, app := start(t, {dir}, size = {1100, 700})
		tab := current_tab(app)
		session.key(s, .N2, {.Ctrl})
		testing.expect_value(t, tab_mode(tab), View_Mode.Grid)
		session.advance(s, 1000)   // (the cards grow to their size)
		label := box_under(session.find(s, "item0"), "n")
		if !testing.expect(t, label != nil, "the card's name") { return }
		text := ui.box_text(label)
		// on two lines at most (wrapped), cut in its middle: its end and its extension kept
		testing.expect(t, .Text_Wrap in label.flags, "the name wraps")
		testing.expectf(t, strings.contains(text, "…"), "cut: %q", text)
		testing.expectf(t, strings.has_suffix(text, "ast.txt"), "its end kept: %q", text)
		testing.expectf(t, strings.has_prefix(text, "a very long"), "its start kept: %q", text)
		testing.expectf(t, label.rect.max.y - label.rect.min.y > label.font_size * 2, "room for two lines: %v", label.rect)
	})
}
