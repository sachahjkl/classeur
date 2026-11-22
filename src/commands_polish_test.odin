package classeur

// The commands' table read as a person reads it: short titles, a distinct icon each, the old words still found in the
// palette, Tab 1 to Last tab out of it (the tabs are under `@`), the sheet of the keys on F1.

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"
import "fs"

// A title is a label of two to four words (one for a few: Open, Copy), without a colon or an explanation.
@(test)
test_command_titles_short :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		for c in COMMANDS {
			words := strings.fields(c.title, context.temp_allocator)
			testing.expectf(t, len(words) >= 1 && len(words) <= 4, "%s: %q has %d words", c.id, c.title, len(words))
			testing.expectf(t, !strings.contains(c.title, ":"), "%s: %q has a colon", c.id, c.title)
		}
	})
}

// No two commands share an icon, but for a family that says one thing.
@(test)
test_command_icons_distinct :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		families := [][]string{
			// the tab of a number: one sign for the nine
			{"tab_1", "tab_2", "tab_3", "tab_4", "tab_5", "tab_6", "tab_7", "tab_8", "tab_last"},
			// a cross closes tabs or cancels the jobs, as on a tab's own button
			{"tab_close", "tab_close_left", "tab_close_right", "jobs_cancel"},
			// (one stop and the other way round: F6, Ctrl+Shift+F6)
			{"panel_next", "panel_previous"},
			// a window of its own, for a tab or on the home folder: the same start
			{"tab_window", "app_new_window"},
			// the themes in one order and the other
			{"app_theme_next", "app_theme_previous"},
			// the text's size, up, down and back (the subset has one sign of text)
			{"app_text_bigger", "app_text_smaller", "app_text_reset"},
			// a folder read again, or every tab's
			{"refresh", "app_reload_all"},
		}
		family :: proc(families: [][]string, id: string) -> int {
			for f, i in families { for x in f { if x == id { return i } } }
			return -1
		}
		for a, i in COMMANDS {
			for b in COMMANDS[i + 1:] {
				if a.icon != b.icon { continue }
				fa := family(families, a.id)
				testing.expectf(t, fa >= 0 && fa == family(families, b.id), "%s and %s share an icon", a.id, b.id)
			}
		}
	})
}

// The inspector's title lost "beside the list": the palette still finds it by those words (its tags).
@(test)
test_palette_finds_by_tag :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "beside")
		palette_ranked(s)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "inspector", "the inspector by a word of its tags")
		session.key(s, .Escape)
	})
}

// The palette's prefixes are the ones classeur fills; `@` lists the tabs (the commands Tab 1 to Last tab are out of the
// palette), and choosing one shows it.
@(test)
test_palette_tabs :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		p := current_panel(app)
		tab_open(app, p, fs.join(dir, "Documents", context.temp_allocator), p.active + 1)
		wait_read(s)
		first_tab := p.tabs[0].id
		session.key(s, .K, {.Ctrl})
		testing.expect_value(t, strings.join(ui.palette_prefixes(&app.palette.pal), ", ", context.temp_allocator), "> Commands, @ Tabs, / Paths, : Settings")
		session.type_text(s, "tab 3")
		palette_ranked(s)
		for k in 0 ..< ui.palette_row_count(&app.palette.pal) {
			c := palette_row_command(app, k)
			testing.expectf(t, c < 0 || !tab_pick_command(COMMANDS[c].id), "row %d: %s is out of the palette", k, c >= 0 ? COMMANDS[c].id : "")
		}
		ui.line_edit_set(&app.palette.pal.field, "@")
		palette_ranked(s)
		tabs := 0
		for k in 0 ..< ui.palette_row_count(&app.palette.pal) {
			if src, _, ok := ui.palette_row(&app.palette.pal, k); ok && src == &app.palette.tabs { tabs += 1 }
		}
		testing.expect_value(t, tabs, 2)
		// the first tab, chosen by its folder's name
		ui.line_edit_set(&app.palette.pal.field, fmt.tprintf("@%s", tab_title(app, p.tabs[0])))
		palette_ranked(s)
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return !ui.palette_is_open(&(^App)(s.user).palette.pal) }, "chosen")
		session.frames(s, 1)
		testing.expect_value(t, panel_tab(p).id, first_tab)
	})
}

// `/` lists the folders of the path typed, read on a worker and found by the letters after its last separator; Enter
// goes there.
@(test)
test_palette_folders :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		session.key(s, .K, {.Ctrl})
		want := fs.join(dir, "Documents", context.temp_allocator)
		typed := fs.join(dir, "Doc", context.temp_allocator)
		if typed[0] != '/' { typed = fmt.tprintf("/%s", typed) }   // (a drive's path after the prefix)
		ui.line_edit_set(&app.palette.pal.field, typed)
		palette_ranked(s)
		src, id, ok := ui.palette_row(&app.palette.pal, 0)
		testing.expect(t, ok && src == &app.palette.folders && id == want, "Documents first")
		session.key(s, .Return)
		session.wait_until(s, proc(s: ^session.Session) -> bool { return !ui.palette_is_open(&(^App)(s.user).palette.pal) }, "chosen")
		wait_read(s)
		testing.expect_value(t, current_tab(app).path, want)
	})
}

// F1 opens the sheet of the keys; other commands wait while it is open; Escape closes it.
@(test)
test_shortcuts_sheet :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1100, 800})
		testing.expect(t, session.find_text(s, "Keyboard shortcuts") == nil, "no sheet at first")
		session.key(s, .F1)
		session.frames(s, 3)
		testing.expect(t, ui.shortcuts_sheet_is_open(&app.palette.sheet), "open")
		testing.expect(t, session.find_text(s, "Keyboard shortcuts") != nil, "the sheet")
		testing.expect(t, session.find_text(s, "Backspace / Alt+Up") != nil, "a command's keys (its two, \" / \" between them; the sheet builds the lines in view)")
		n := len(current_panel(app).tabs)
		session.key(s, .T, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, len(current_panel(app).tabs), n)
		session.key(s, .Escape)
		session.frames(s, 3)
		testing.expect(t, !ui.shortcuts_sheet_is_open(&app.palette.sheet), "closed")
		testing.expect(t, session.find_text(s, "Keyboard shortcuts") == nil, "the sheet gone")
	})
}
