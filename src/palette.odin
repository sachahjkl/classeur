package classeur

// The command palette (Ctrl+K, Ctrl+Shift+P): the toolkit's (ui.Command_Palette), the same in every program of the
// family. classeur gives it its sources (src/md/features/palette.md): its commands (`>`, and in the plain search), the
// settings (`:`), the tabs (`@`) and the folders (`/`, palette_sources.odin); the toolkit adds the views' moves. A few
// letters find a command ("nf": New folder); Enter runs it. Ctrl+Enter (a key of one's own) and Alt+Enter (an alias)
// are the toolkit's, through the window's keymap (ui.Keymap, gui_toolkit's src/md/features/keymap.md). The palette
// ranks on a chore and remembers the choices (palette_choices.txt in the state folder).
//
// The tables given to the palette and to the sheet are made once: the labels are translated where they show, and the
// keys in effect are the toolkit's to read. Only `disabled` is made again, when a command can or cannot act, with a new
// version: the palette compares the version, never the table.

import "core:strings"
import "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

Palette :: struct {
	pal:       ui.Command_Palette,           // the toolkit's: its field, its sources, its usage memory, its recorder
	settings:  prefs_page.Palette_Settings,  // the settings source
	tabs:      ui.Palette_Source,            // `@` (palette_sources.odin)
	folders:   ui.Palette_Source,            // `/` (absolute paths, recents, bookmarks, places)
	files:     ui.Palette_Files,             // `/` (gt:filesearch under the current folder)
	tabs_sig:  u64,                          // what the tabs source's items were made from (tabs_poll)
	folders_cache: Folders_Cache,            // the last folder the folders source listed (palette_sources.odin)
	sheet:     ui.Shortcuts_Sheet,           // the sheet of the keys (F1)

	// the sheet's table: app.commands by group (Tab 1 to Last tab included)
	sheet_table: [dynamic]ui.Command,
	// the commands source's table: the sheet's but Tab 1 to Last tab (the tabs source lists the tabs themselves)
	table:       [dynamic]ui.Command,
	order:       [dynamic]int,   // table index -> COMMANDS index
	line_of:     [dynamic]int,   // COMMANDS index -> table index (-1: not in the table)
	disabled:    [dynamic]bool,
	made:        bool,           // `disabled` was made once
	enabled:     u64,            // a bit per gated command that can act, as `disabled` says it
	version:     u64,            // the commands source's: bumped when `disabled` changes
	gated:       [dynamic]int,   // the commands that have an `enabled` (read each frame: few)
	layout_names: [dynamic]string,   // Open layout's choices while its form is open (layout_choices; the strings not owned)
}

// (the toolkit's palette is destroyed before the window: app_close)
palette_free :: proc(p: ^Palette) {
	ui.shortcuts_sheet_destroy(&p.sheet)
	ui.palette_files_destroy(&p.files)
	folders_cache_free(&p.folders_cache)
	delete(p.sheet_table)
	delete(p.table)
	delete(p.order)
	delete(p.line_of)
	delete(p.disabled)
	delete(p.gated)
	delete(p.layout_names)
	p^ = {}
}

// Where the palette's choices are kept: <state>/FromentSoftware/Classeur/palette_choices.txt, beside the tests' session
// file for theirs, none (in memory only) when headless or standalone.
palette_choices_file :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".choices"}, context.temp_allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/palette_choices.txt"}, context.temp_allocator)
}

// (once the window's state is made: the usage memory is read on its chores)
palette_start :: proc(app: ^App) {
	p := &app.palette
	ui.palette_memory_open(&p.pal, &app.main.state, palette_choices_file(app))
	for c, i in COMMANDS { if c.enabled != nil { append(&p.gated, i) } }
	assert(len(p.gated) <= 64, "Palette.enabled holds a bit per gated command")
	resize(&p.line_of, len(COMMANDS))
	for &l in p.line_of { l = -1 }
	for g in 0 ..< len(COMMAND_GROUPS) {
		for c, i in COMMANDS {
			if command_group(c.id) != g { continue }
			append(&p.sheet_table, app.commands[i])
			if tab_pick_command(c.id) { continue }
			p.line_of[i] = len(p.table)
			append(&p.table, app.commands[i])
			append(&p.order, i)
		}
	}
	// (the settings' page options read when the source needs them: the updater, the themes shown, as they are then)
	prefs_page.palette_settings_add(&p.pal, &p.settings, &app.prefs, &app.options.page, proc(user: rawptr) -> prefs_page.Page_Options {
		return options_page((^App)(user))
	}, proc(user: rawptr) {
		// (the setting chosen is already alone on its page: prefs_page.show)
		app := (^App)(user)
		ui.view_open(&app.views, OPTIONS_VIEW, app)
	}, app)
	palette_sources_add(app)
}

// The palette (a menu's line; Ctrl+K and Ctrl+Shift+P are the toolkit's: palette_keys_read), `typed` in its field.
palette_open :: proc(app: ^App, typed := "") {
	ui.palette_open(&app.palette.pal, typed)
}

// The groups of the commands, in the palette's order, and the group of each (by its id). (Not rodata: i18n.later marks
// them for the catalogue; tr where they are shown.)
COMMAND_GROUPS := [?]string{i18n.later("Go"), i18n.later("Tabs and panels"), i18n.later("Files"), i18n.later("Selection"), i18n.later("View"), i18n.later("Find"), i18n.later("Program")}

command_group :: proc(id: string) -> int {
	has :: strings.has_prefix
	switch {
	case has(id, "app_"): return 6
	case id == "open" || id == "up" || id == "back" || id == "forward" || id == "home" || id == "goto" || id == "goto_popup" || id == "open_folder" || id == "refresh": return 0
	case has(id, "tab") || has(id, "panel") || id == "open_new_tab" || id == "open_other_panel" || has(id, "layout") || id == "lock": return 1
	case has(id, "select"): return 3
	case has(id, "view") || has(id, "zoom") || has(id, "sort") || has(id, "group") || id == "tree" || id == "hidden" || id == "sidebar" || id == "folders_mixed" || id == "inspector": return 4
	case id == "filter" || id == "flat" || id == "types" || id == "files_only" || id == "folders_only" || id == "every_type": return 5
	case id == "shortcuts" || id == "options" || id == "jobs" || id == "jobs_cancel": return 6
	}
	return 2
}

// The index of a command of COMMANDS.
command_index :: proc(c: ^Command) -> int {
	return int((uintptr(c) - uintptr(&COMMANDS[0])) / size_of(Command))
}

// One of the commands that show the tab of a number (Alt+1 to Alt+9): out of the palette, whose tabs source lists the
// tabs themselves.
tab_pick_command :: proc(id: string) -> bool {
	return id == "tab_last" || (len(id) == 5 && strings.has_prefix(id, "tab_") && id[4] >= '1' && id[4] <= '9')
}

// `disabled` made again when what can act changed (a bit per gated command: three of them); it bumps the source's
// version.
@(private = "file")
palette_disabled_keep :: proc(app: ^App) {
	p := &app.palette
	enabled: u64
	for c, bit in p.gated { if COMMANDS[c].enabled(app) { enabled |= 1 << u64(bit) } }
	if p.made && enabled == p.enabled { return }
	p.made, p.enabled = true, enabled
	resize(&p.disabled, len(p.order))
	for ci, i in p.order {
		c := &COMMANDS[ci]
		p.disabled[i] = c.enabled != nil && !c.enabled(app)
	}
	p.version += 1
}

// The sheet of the keys (F1): every command that has keys in effect under its group, the person's own in the accent's
// colour (the toolkit's sheet reads the keymap).
shortcuts_open :: proc(app: ^App) {
	p := &app.palette
	ui.shortcuts_sheet_open(&p.sheet, p.sheet_table[:])
}

// At the top of each build, before anything is built: the commands given (compared by their version), then the choice.
// palette_chosen makes the run mode's writes (a setting changed in the palette): before the settings' view is built,
// the page shows the value in the same frame as the palette.
palette_choose :: proc(app: ^App) {
	p := &app.palette
	if ui.palette_is_open(&p.pal) {
		if t := current_tab(app); t != nil && !t.in_archive && !shows_trash(t) { deep_ensure_index(app, t.path) }
	}
	palette_disabled_keep(app)
	ui.palette_commands(&p.pal, p.table[:], p.disabled[:], {version = p.version, choices = palette_choices, user = app})
	// (the toolkit's sources act in palette_chosen: a setting, a view's move, a key or an alias of one's own, go to)
	if c, ok := ui.palette_chosen(&p.pal); ok { palette_run(app, c) }
}

// Ctrl+K and Ctrl+Shift+P, after the views' keys (a view with the focus reads its keys first), before the page's.
palette_keys_read :: proc(app: ^App) {
	// (the recorder claims every chord, Ctrl+K too: keys_claim)
	_ = ui.palette_keys(&app.palette.pal)
}

// The values a command's argument takes, when the program has the list (ui.Palette_Commands_Options.choices): `index`
// is the commands source's table's.
@(private = "file")
palette_choices :: proc(user: rawptr, index: int, argument: string) -> (labels, values: []string) {
	app := (^App)(user)
	p := &app.palette
	if index < 0 || index >= len(p.order) { return nil, nil }
	if COMMANDS[p.order[index]].id == "layout_open" && argument == "layout" {
		names := layout_choices(app, &p.layout_names)
		return names, names
	}
	return nil, nil
}

// A choice of one of classeur's sources.
@(private = "file")
palette_run :: proc(app: ^App, c: ui.Palette_Choice) {
	p := &app.palette
	if _, is := ui.palette_chosen_command(&p.pal, c); is {
		cmd := command_find(c.id)
		if cmd == nil { return }
		if t := current_tab(app); t != nil { t.focus_due = .List }
		// (a command with arguments chosen with their values: its form asked them, no dialog of its own)
		if cmd.run_with != nil && len(c.arguments) == len(cmd.arguments) {
			cmd.run_with(app, c.arguments)
		} else {
			cmd.run(app)
		}
		return
	}
	if c.source == &p.tabs {
		palette_tab_chosen(app, c.id)
	} else if c.source == &p.folders {
		palette_folder_chosen(app, c.id, c.mods)
	} else if c.source == &p.files.source {
		ui.palette_files_opened(&app.main.state, p.files.index, c.id)
		palette_folder_chosen(app, c.id, c.mods)
	}
}

// Whether the toolkit's recorder (Ctrl+Enter on a command) is open.
palette_recording :: proc(app: ^App) -> bool { return app.palette.pal.recorder.id != "" }

// The command of row `k` of the palette's list as the last ranking made it (the tests; -1: not a command, or none).
palette_row_command :: proc(app: ^App, k: int) -> int {
	p := &app.palette
	src, id, ok := ui.palette_row(&p.pal, k)
	if !ok || src != &p.pal.commands.source { return -1 }
	c := command_find(id)
	return c != nil ? command_index(c) : -1
}

// The command of the palette's first row (the tests, once its ranking came).
palette_first :: proc(app: ^App) -> int { return palette_row_command(app, 0) }
