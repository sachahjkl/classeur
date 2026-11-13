package classeur

// The commands' table read as a person reads it: short titles, a distinct icon each, the old words still found in the
// palette, Tab 1 to Last tab out of the way, the sheet of the keys on F1.

import "base:runtime"
import "core:strings"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"

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
		session.frames(s, 2)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "inspector", "the inspector by a word of its tags")
		session.key(s, .Escape)
	})
}

// Tab 1 to Last tab are in the palette once "tab" is typed, not for other letters.
@(test)
test_palette_tab_numbers :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		lists_tab_number :: proc(app: ^App) -> bool {
			for k in 0 ..< len(COMMANDS) + PALETTE_RECENT {
				if c := palette_line_command(app, k); c >= 0 && tab_pick_command(COMMANDS[c].id) { return true }
			}
			return false
		}
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "tab")
		session.frames(s, 2)
		testing.expect(t, lists_tab_number(app), "\"tab\": Tab 1 and the others")
		ui.line_edit_set(&app.palette.field, "tab 3")
		session.frames(s, 1)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "tab_3", "\"tab 3\": Tab 3 first")
		ui.line_edit_set(&app.palette.field, "zo")
		session.frames(s, 1)
		testing.expect(t, !lists_tab_number(app), "\"zo\": no Tab 1")
		session.key(s, .Escape)
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
		testing.expect(t, app.shortcuts_open, "open")
		testing.expect(t, session.find_text(s, "Keyboard shortcuts") != nil, "the sheet")
		testing.expect(t, session.find_text(s, "Ctrl+K, Ctrl+Shift+P") != nil, "a command's keys")
		n := len(current_panel(app).tabs)
		session.key(s, .T, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, len(current_panel(app).tabs), n)
		session.key(s, .Escape)
		session.frames(s, 3)
		testing.expect(t, !app.shortcuts_open, "closed")
		testing.expect(t, session.find_text(s, "Keyboard shortcuts") == nil, "the sheet gone")
	})
}
