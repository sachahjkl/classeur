package classeur

// The program's own commands (program_actions.odin): each in the table with its words and keys, found in the palette by
// the words a person types, and doing what it says on a headless window.

import "base:runtime"
import "core:strings"
import "core:testing"
import config "gt:config"
import "gt:platform"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"

@(private = "file", rodata)
PROGRAM_COMMANDS := [?]string{
	"app_quit", "app_restart", "app_new_window", "app_minimize", "app_maximize", "app_full_screen",
	"app_update_check", "app_update_install", "app_update_restart", "app_about", "app_website", "app_report",
	"app_changelog", "app_settings_folder", "app_version_copy", "app_theme_next", "app_theme_previous", "app_density",
	"app_animations", "app_text_bigger", "app_text_smaller", "app_text_reset", "app_reload_all", "app_layout_reset",
	"app_thumbs_clear",
}

@(test)
test_program_commands_listed :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		for id in PROGRAM_COMMANDS {
			c := command_find(id)
			if !testing.expectf(t, c != nil, "%s is a command", id) { continue }
			testing.expectf(t, len(c.tags) > 0, "%s has tags", id)
			testing.expectf(t, c.keys[0].key != .None, "%s has a key", id)
			testing.expectf(t, command_group(id) == len(COMMAND_GROUPS) - 1, "%s is in the Program group", id)
		}
	})
}

// "exit" finds Quit, "reboot" Restart: words their titles do not say.
@(test)
test_palette_finds_program_commands :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		session.key(s, .K, {.Ctrl})
		session.type_text(s, "exit")
		session.frames(s, 2)
		first := palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "app_quit", "\"exit\": Quit")
		ui.field_set(&app.palette.field, "reboot")
		session.frames(s, 1)
		first = palette_first(app)
		testing.expect(t, first >= 0 && COMMANDS[first].id == "app_restart", "\"reboot\": Restart")
		// (headless, no updater: Install the update would do nothing, it is not offered)
		ui.field_set(&app.palette.field, "install the update")
		session.frames(s, 1)
		first = palette_first(app)
		testing.expect(t, first < 0 || COMMANDS[first].id != "app_update_install", "no update to install: not offered")
		session.key(s, .Escape)
	})
}

// Next theme writes the next of the settings' themes; Previous goes back.
@(test)
test_theme_commands :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		list := themes(app)
		if len(list) < 2 { return }   // (one theme: nothing to step to)
		before := strings.clone(app.settings.theme, context.temp_allocator)   // (the theme in effect: the preference may say none)
		at := -1
		for th, i in list { if th.name == before { at = i } }
		session.key(s, .Period, {.Ctrl, .Shift, .Alt})
		session.frames(s, 1)
		testing.expect_value(t, config.string_of(&app.prefs, "appearance.theme"), list[(at + 1) % len(list)].name)
		testing.expect_value(t, app.settings.theme, list[(at + 1) % len(list)].name)
		session.key(s, .Comma, {.Ctrl, .Shift, .Alt})
		session.frames(s, 1)
		testing.expect_value(t, app.settings.theme, before)
	})
}

// The text's size by a point, back to the default; the rows compact and back.
@(test)
test_look_commands :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		size := app.settings.font_size
		session.key(s, .Equal, {.Ctrl, .Alt})
		session.frames(s, 1)
		testing.expect_value(t, app.settings.font_size, size + TEXT_STEP)
		session.key(s, .N0, {.Ctrl})
		session.frames(s, 1)
		testing.expect_value(t, app.settings.font_size, size)
		compact := app.settings.compact
		session.key(s, .D, {.Ctrl, .Shift, .Alt})
		session.frames(s, 1)
		testing.expect_value(t, app.settings.compact, !compact)
		command_find("app_density").run(app)
		testing.expect_value(t, app.settings.compact, compact)
	})
}

// F11 puts the window in full screen and takes it out (the offscreen window of the tests keeps the state on both
// systems); Alt+F10 maximizes and restores.
@(test)
test_window_commands :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		win := app.main.win
		testing.expect(t, !platform.is_fullscreen(win), "not full screen at first")
		session.key(s, .F11)
		session.frames(s, 1)
		testing.expect(t, platform.is_fullscreen(win), "F11: full screen")
		session.key(s, .F11)
		session.frames(s, 1)
		testing.expect(t, !platform.is_fullscreen(win), "F11 again: not full screen")
		session.key(s, .F10, {.Alt})
		session.frames(s, 1)
		testing.expect(t, platform.is_maximized(win), "Alt+F10: maximized")
		session.key(s, .F10, {.Alt})
		session.frames(s, 1)
		testing.expect(t, !platform.is_maximized(win), "Alt+F10 again: restored")
	})
}

// New window starts this program on the home folder (noted, headless); Reset the layout leaves one panel, one tab at
// home; Reload all folders reads every tab again.
@(test)
test_layout_commands :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		opened := len(app.opened)
		session.key(s, .N, {.Ctrl})
		session.frames(s, 1)
		if testing.expect_value(t, len(app.opened), opened + 1) {
			testing.expect_value(t, app.opened[opened], strings.concatenate({"window:", app.home}, context.temp_allocator))
		}
		session.key(s, .D, {.Ctrl, .Shift})   // (a split: two panels)
		session.key(s, .T, {.Ctrl})
		wait_read(s)
		testing.expect(t, len(app.panels) == 2 && len(current_panel(app).tabs) == 2, "two panels, two tabs in one")
		session.key(s, .L, {.Ctrl, .Shift, .Alt})
		wait_read(s)
		testing.expect_value(t, len(app.panels), 1)
		testing.expect_value(t, len(app.panels[0].tabs), 1)
		testing.expect_value(t, current_tab(app).path, app.home)
		serial := current_tab(app).serial
		session.key(s, .F5, {.Ctrl})
		wait_read(s)
		testing.expect(t, current_tab(app).serial > serial, "Ctrl+F5: read again")
	})
}

// Quit asks the window to close as its close button does (app_run's loop then ends, the session saved).
@(test)
test_quit :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		testing.expect(t, !platform.is_closed(app.main.win), "open")
		session.key(s, .Q, {.Ctrl})
		session.frames(s, 1)
		testing.expect(t, platform.is_closed(app.main.win), "Ctrl+Q: closed")
		testing.expect_value(t, app.launch_after, "")
	})
}

// Restart closes too, with this program to start once this one has ended (app_run's end).
@(test)
test_restart :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, home = dir)
		context.allocator = runtime.heap_allocator()
		command_find("app_restart").run(app)
		session.frames(s, 1)
		testing.expect(t, platform.is_closed(app.main.win), "closed")
		testing.expect_value(t, app.launch_after, app.exe)
	})
}
