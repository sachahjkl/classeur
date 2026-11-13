package classeur

// Back and Forward come back to the row and the scroll left; a rename refused keeps the field, Tab renames the next
// row; a row of tabs longer than its panel scrolls, the shown tab in view, and a chevron lists them.

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:ui"
import "gt:testkit/session"
import "fs"

@(test)
test_back_keeps_the_place :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := make([dynamic]string, context.temp_allocator)
		append(&files, "Sub/", "Sub/inner.txt")
		for i in 1 ..= 200 { append(&files, fmt.tprintf("file %03d.txt", i)) }
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1000, 600})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		// (no click first: the list has the keys from the start)
		session.key(s, .End)
		session.key(s, .Up, repeat = 5)
		session.advance(s, 600)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "file 195.txt")
		list := ui.box_from_key(tab.vl.key)
		if !testing.expect(t, list != nil, "the list") { return }
		scroll := list.view_target.y
		testing.expect(t, scroll > 0, "the list scrolled down to the cursor")

		tab_go(app, tab, fs.join(dir, "Sub", context.temp_allocator))
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Sub")
		session.key(s, .Left, {.Alt})
		wait_read(s)
		session.advance(s, 600)
		testing.expect_value(t, tab.path, dir)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "file 195.txt")
		list = ui.box_from_key(tab.vl.key)
		if !testing.expect(t, list != nil, "the list again") { return }
		testing.expectf(t, abs(list.view_off.y - scroll) < 1, "the list where it was left: %v, then %v", scroll, list.view_off.y)

		// Forward then Back again: the same place
		session.key(s, .Right, {.Alt})
		wait_read(s)
		testing.expect_value(t, fs.base(tab.path), "Sub")
		session.key(s, .Left, {.Alt})
		wait_read(s)
		session.advance(s, 600)
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "file 195.txt")
		testing.expect(t, abs(ui.box_from_key(tab.vl.key).view_off.y - scroll) < 1, "the list where it was, once more")
	})
}

// A name already there: the field stays with the name typed, selected. Tab keeps the name and renames the next row;
// a change of case alone is a rename.
@(test)
test_rename_refused_and_tab :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt", "b.txt", "c.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		testing.expect(t, folder_cursor_to_name(&tab.folder, "a.txt"))
		folder_pick(&tab.folder, tab.folder.cursor)

		session.key(s, .F2)
		testing.expect(t, app.rename.active)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "b.txt")
		session.key(s, .Return)
		wait_read(s)   // (the rename is the edits' worker's: its refusal comes back)
		testing.expect(t, app.rename.active, "the field stays open")
		testing.expect(t, app.rename.refused, "the field says the name was refused")
		testing.expect_value(t, ui.line_edit_string(&app.rename.field), "b.txt")
		testing.expect(t, app.rename.field.mark == 0 && app.rename.field.cursor == len("b.txt"), "what was typed is selected")
		testing.expect(t, fs.exists(fs.join(dir, "a.txt", context.temp_allocator)), "a.txt is still there")

		// another name, Tab: renamed, and the next row in the field
		session.type_text(s, "d.txt")
		testing.expect(t, !app.rename.refused, "typed again: no longer refused")
		session.key(s, .Tab)
		wait_read(s)
		testing.expect(t, fs.exists(fs.join(dir, "d.txt", context.temp_allocator)), "a.txt is now d.txt")
		testing.expect(t, app.rename.active, "the next row is renamed")
		testing.expect_value(t, app.rename.name, "b.txt")
		testing.expect_value(t, folder_cursor_entry(&tab.folder).name, "b.txt")
		// Tab again with the name as it was: nothing renamed, the row after it
		session.key(s, .Tab)
		session.frames(s, 2)
		testing.expect_value(t, app.rename.name, "c.txt")
		// Shift+Tab: the row before
		session.key(s, .Tab, {.Shift})
		session.frames(s, 2)
		testing.expect_value(t, app.rename.name, "b.txt")
		session.key(s, .Escape)
		session.frames(s, 2)
		testing.expect(t, !app.rename.active)

		// a change of case alone
		testing.expect(t, folder_cursor_to_name(&tab.folder, "c.txt"))
		folder_pick(&tab.folder, tab.folder.cursor)
		session.key(s, .F2)
		session.key(s, .A, {.Ctrl})
		session.type_text(s, "C.txt")
		session.key(s, .Return)
		wait_read(s)
		testing.expect(t, !app.rename.active, "renamed")
		names := shown_names(tab)
		testing.expect(t, slice.contains(names, "C.txt") && !slice.contains(names, "c.txt"), "c.txt is now C.txt")
	})
}

// More tabs than a narrow panel holds: the row scrolls, the shown tab in view, the new tab's button in the panel, and
// a chevron lists every tab.
@(test)
test_tabs_overflow :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"Documents/", "notes.txt"})
		s, app := start(t, {dir}, size = {700, 500})
		context.allocator = runtime.heap_allocator()
		p := current_panel(app)
		for _ in 0 ..< 14 { tab_open(app, p, dir) }
		wait_read(s)
		session.advance(s, 600)
		testing.expect_value(t, p.active, len(p.tabs) - 1)

		view := session.get(s, "tab_view")
		panel := session.get(s, "panel0").rect
		last := session.get(s, fmt.tprintf("tab%d", p.tabs[p.active].id)).rect
		testing.expectf(t, last.min.x >= view.rect.min.x - 1 && last.max.x <= view.rect.max.x + 1, "the shown tab in view: %v in %v", last, view.rect)
		plus := session.get(s, "newtab0").rect
		testing.expectf(t, plus.min.x >= panel.min.x && plus.max.x <= panel.max.x + 1, "the new tab's button in the panel: %v in %v", plus, panel)
		first := session.get(s, fmt.tprintf("tab%d", p.tabs[0].id)).rect
		testing.expect(t, first.max.x <= view.rect.min.x + 1, "the first tab scrolled out")

		// the chevron's menu: every tab; a click shows it
		session.click(s, "tablist0")
		session.frames(s, 2)
		testing.expect(t, ui.menu_is_open(TABS_MENU), "the tabs' menu")
		for k in 0 ..< len(p.tabs) {
			_, ok := ui.menu_item_rect(0, k)
			testing.expectf(t, ok, "tab %d in the menu", k)
		}
		if r, ok := ui.menu_item_rect(0, 0); ok { session.click_at(s, (r.min + r.max) * 0.5) }
		session.advance(s, 600)
		testing.expect_value(t, p.active, 0)
		first = session.get(s, fmt.tprintf("tab%d", p.tabs[0].id)).rect
		view = session.get(s, "tab_view")
		testing.expectf(t, first.min.x >= view.rect.min.x - 1, "the first tab back in view: %v in %v", first, view.rect)

		// the wheel over the tabs scrolls them
		before := view.view_target.x
		session.wheel(s, session.center(view), {0, 3})
		session.frames(s, 2)
		testing.expect(t, session.get(s, "tab_view").view_target.x > before, "the wheel scrolls the tabs")
	})
}
