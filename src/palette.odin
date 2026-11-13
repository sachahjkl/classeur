package classeur

// The command palette (Ctrl+K, Ctrl+Shift+P): the toolkit's (ui.palette), over every command of the table under its
// group, then every setting (prefs_page.palette_commands). A few letters find a command ("nf": New folder), an alias of
// one's own too (its tags); Enter runs it. Ctrl+Enter records keys of one's own for it (the recorder, below), Alt+Enter
// makes the letters typed its alias. The commands chosen most, and lately, come first, under Recent (ui.Choice_Memory,
// kept in the state folder).
//
// The palette and the sheet keep their lists: the tables they are given are built again only when what they read
// changes (the keymap, the language, "tab" typed or not, a command that can or cannot run), with a new version.

import "core:fmt"
import vmem "core:mem/virtual"
import "core:strings"
import config "gt:config"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

PALETTE_RECENT :: ui.CHOICE_RECENT_MOST

Palette :: struct {
	using pal: ui.Command_Palette,
	recording: int,         // the command whose keys are recorded (-1: none): the recorder's dialog is open
	chords:    [2]Shortcut, // what was pressed so far
	count:     int,
	choices:   ui.Choice_Memory,     // what the person chose before (palette_choices_file)
	sheet:     ui.Shortcuts_Sheet,   // the sheet of the keys (F1): sheet.open shows it

	list:       Palette_List,   // the palette's table, kept (in list_arena) while list_key holds
	list_key:   Palette_Key,
	list_arena: vmem.Arena,
	gated:      [dynamic]int,   // the commands that have an `enabled` (read each frame: few)

	sheet_list:  []ui.Command,  // the sheet's table, kept (in sheet_arena) while sheet_key holds
	sheet_key:   Sheet_Key,
	sheet_arena: vmem.Arena,
}

// What the palette's table reads: when one changes, the table is built again and its version bumped.
@(private = "file")
Palette_Key :: struct {
	built:    bool,
	keymap:   u64,                // Keymap.version: one's own keys and aliases
	language: u32,                // i18n.version(): the settings' groups and the keys' texts are in it
	tabs:     bool,               // "tab" typed: Tab 1 to Last tab are offered
	enabled:  u64,                // a bit per gated command that can run now
	version:  u64,
}

@(private = "file")
Sheet_Key :: struct {
	built:    bool,
	keymap:   u64,
	language: u32,   // i18n.version() it was made in
	version:  u64,
}

palette_free :: proc(p: ^Palette) {
	ui.palette_destroy(&p.pal)
	ui.shortcuts_sheet_destroy(&p.sheet)
	ui.choice_memory_close(&p.choices)
	vmem.arena_destroy(&p.list_arena)
	vmem.arena_destroy(&p.sheet_arena)
	delete(p.gated)
	p^ = {}
}

// Where the palette's choices are kept: <state>/classeur/palette_choices, beside the tests' session file for theirs, none
// (in memory only) when headless or standalone.
palette_choices_file :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".choices"}, context.temp_allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.State, APP_NAME, context.temp_allocator), "/palette_choices"}, context.temp_allocator)
}

// (once the window's state is made: the file is read on its chores)
palette_start :: proc(app: ^App) {
	p := &app.palette
	p.recording = -1   // (no command's keys recorded: the recorder is shut)
	ui.choice_memory_open(&p.choices, &app.main.state, palette_choices_file(app))
	for c, i in COMMANDS { if c.enabled != nil { append(&p.gated, i) } }
	assert(len(p.gated) <= 64, "Palette_Key.enabled holds a bit per gated command")
}

palette_open :: proc(app: ^App) {
	p := &app.palette
	ui.palette_open(&p.pal)
	p.size = {f32(config.float_of(&app.prefs, "palette.width")), f32(config.float_of(&app.prefs, "palette.height"))}   // (ems)
	p.recording = -1
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
	case id == "palette" || id == "shortcuts" || id == "options" || id == "jobs" || id == "jobs_cancel": return 6
	}
	return 2
}

// The palette's list: the program's commands by group (`order`: each line's command), then the settings (`settings`:
// each one's preference); the keys' texts (one's own), the aliases as tags, each line's name in the memory of choices
// (a command's id; a setting is not remembered). All in the palette's list_arena.
@(private = "file")
Palette_List :: struct {
	commands: []ui.Command,
	order:    []int,      // line -> COMMANDS index, for the program's commands (the lines before the settings)
	settings: []string,   // the settings' names, after them
	names:    []string,   // line -> its key in the memory of choices
	keys:     []string,   // line -> the text of its keys
}

// The palette's table as it is now: the one kept, built again when what it reads changed.
@(private = "file")
palette_list :: proc(app: ^App) -> ^Palette_List {
	p := &app.palette
	// (Tab 1 to Last tab would take nine lines of every search: they show once "tab" is typed)
	// (the word in the person's language: the titles they search are)
	key := Palette_Key{built = true, keymap = app.keymap.version, language = i18n.version()}
	key.tabs = strings.has_prefix(strings.to_lower(strings.trim_space(ui.line_edit_string(&p.field)), context.temp_allocator), i18n.tr("palette: the word that shows Tab 1 to Last tab", "tab"))
	for c, bit in p.gated { if COMMANDS[c].enabled(app) { key.enabled |= 1 << u64(bit) } }
	key.version = p.list_key.version
	if key == p.list_key { return &p.list }
	key.version += 1
	p.list_key = key

	vmem.arena_free_all(&p.list_arena)
	a := vmem.arena_allocator(&p.list_arena)
	cmds := make([dynamic]ui.Command, a)
	order := make([dynamic]int, a)
	names := make([dynamic]string, a)
	keys := make([dynamic]string, a)
	for g in 0 ..< len(COMMAND_GROUPS) {
		for &c, i in COMMANDS {
			if command_group(c.id) != g || (!key.tabs && tab_pick_command(c.id)) { continue }
			// (a command that would do nothing now is not offered)
			if c.enabled != nil && !c.enabled(app) { continue }
			tags := make([dynamic]string, a)
			append(&tags, ..c.tags)
			for alias, id in app.keymap.aliases { if id == c.id { append(&tags, strings.clone(alias, a)) } }
			append(&cmds, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = c.keys, tags = tags[:]})
			append(&order, i)
			append(&names, c.id)
			append(&keys, strings.clone(command_keys(app, &c), a))
		}
	}
	settings, setting_names := prefs_page.palette_commands(&app.prefs, options_page(app), a)
	append(&cmds, ..settings)
	for _ in settings { append(&names, "") }
	p.list = {commands = cmds[:], order = order[:], settings = setting_names, names = names[:], keys = keys[:]}
	return &p.list
}

// The palette's options for its kept table: the memory of choices, the keys' texts, an alias typed whole first.
@(private = "file")
palette_options :: proc(app: ^App, l: ^Palette_List) -> (o: ui.Palette_Options) {
	o = {memory = &app.palette.choices, names = l.names, keys = l.keys, version = app.palette.list_key.version}
	o.foot = i18n.tr("Enter: run   Ctrl+Enter: a key of your own   Alt+Enter: the letters typed, its alias")
	if a := alias_command(app, ui.line_edit_string(&app.palette.field)); a != nil {
		for c, line in l.order { if &COMMANDS[c] == a { o.first = line } }
	}
	return
}

// One of the commands that show the tab of a number (Alt+1 to Alt+9).
tab_pick_command :: proc(id: string) -> bool {
	return id == "tab_last" || (len(id) == 5 && strings.has_prefix(id, "tab_") && id[4] >= '1' && id[4] <= '9')
}

// The sheet of the keys (F1) while it is open: every command that has keys under its group, the person's own keys
// when they set some (a sequence reads "Ctrl+M, T", as the sheet joins a command's two chords).
// (its table built again only when the keymap or the language changed)
shortcuts_build :: proc(app: ^App) {
	p := &app.palette
	if !p.sheet.open { return }
	key := Sheet_Key{built = true, keymap = app.keymap.version, language = i18n.version(), version = p.sheet_key.version}
	if key != p.sheet_key {
		key.version += 1
		p.sheet_key = key
		vmem.arena_free_all(&p.sheet_arena)
		a := vmem.arena_allocator(&p.sheet_arena)
		list := make([dynamic]ui.Command, a)
		for g in 0 ..< len(COMMAND_GROUPS) {
			for &c in COMMANDS {
				if command_group(c.id) != g { continue }
				keys := c.keys
				if b, ok := app.keymap.custom[c.id]; ok {
					n := b.chords[1].key == .None ? 1 : 2
					keys = make([]Shortcut, n, a)
					copy(keys, b.chords[:n])
				}
				append(&list, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = keys})
			}
		}
		p.sheet_list = list[:]
	}
	ui.shortcuts_sheet(&p.sheet, "shortcuts", p.sheet_list, version = p.sheet_key.version)
}

palette_build :: proc(app: ^App) {
	// (the sheet of the keys is the palette's sibling: built here, over the window, before it)
	shortcuts_build(app)
	p := &app.palette
	if p.recording >= 0 {
		palette_recorder(app)
		return
	}
	if !p.open { return }
	l := palette_list(app)
	chosen, resized := ui.palette(&p.pal, l.commands, nil, palette_options(app, l))
	if resized || !p.open { palette_keep_size(app) }
	if chosen < 0 { return }
	// a setting: the settings, on that one alone
	if chosen >= len(l.order) {
		name := l.settings[chosen - len(l.order)]
		app.options.open = true
		prefs_page.show(&app.options.page, &app.prefs, options_page(app), name)
		return
	}
	c := &COMMANDS[l.order[chosen]]
	switch p.chosen_mods {
	case {.Ctrl}:
		// (the palette comes back as it was once the keys are recorded)
		p.recording, p.count, p.chords = l.order[chosen], 0, {}
	case {.Alt}:
		needle := strings.trim_space(ui.line_edit_string(&p.field))
		if needle != "" {
			keymap_alias(app, needle, c.id)
			say(app, i18n.tr("%s: an alias of %s."), needle, i18n.tr(c.title))
		}
		p.open = true
	case:
		ui.choice_note(&p.choices, c.id)
		if t := current_tab(app); t != nil { t.focus_due = .List }
		c.run(app)
	}
}

// The recorder: a small dialog over the window while a command's keys are recorded. What is pressed is taken (two
// chords for a sequence); Enter keeps them, Escape forgets them, Backspace first gives the command its own keys again.
// Then the palette comes back as it was.
@(private = "file")
palette_recorder :: proc(app: ^App) {
	p := &app.palette
	c := &COMMANDS[p.recording]
	em := ui.font_size()
	open := true
	keep, cancel := false, false
	// (the toolkit's three parts of a dialog: the command in the header, the keys pressed in the body, then the buttons)
	if ui.modal("palette_keys", &open, {}) {
		hk, ok := ui.key_take()
		if ok && hk.key != .None {
			key, mods := hk.key, hk.mods
			switch {
			case key == .Escape && mods == {}:
				cancel = true
			case key == .Return && mods == {} && p.count > 0:
				keep = true
			case key == .Backspace && mods == {} && p.count == 0:
				keymap_unbind(app, c.id)
				say(app, i18n.tr("%s: its own keys again."), i18n.tr(c.title))
				cancel = true
			case:
				if p.count == 2 { p.count = 0; p.chords = {} }
				p.chords[p.count] = Shortcut{key, mods}
				p.count += 1
			}
		}
		if ui.dialog_header("rec_title", fmt.tprintf(i18n.tr("Keys for %s"), ui.text_shown(i18n.tr(c.title))), {icon = lucide.KEYBOARD, icon_font = app.icons, close = true}) {}
		if ui.dialog_body("rec_body") {
			if ui.tags("weak") {
				ui.next({width = ui.fill()})
				ui.paragraph(fmt.tprintf("%s###rec_help", i18n.tr("Press them: two for a sequence. Backspace first gives it its own keys again.")))
			}
			ui.spacer(ui.px(em * 0.8))
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.6))})
			if ui.row(.Center, id = "###rec_keys") {
				ui.spacer(ui.fill())
				ui.kbd(p.count == 0 ? i18n.tr("Press the keys…") : binding_text(Binding{p.chords}))
				ui.spacer(ui.fill())
			}
		}
		if ui.dialog_buttons("rec_buttons") {
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("rec_cancel", i18n.tr("Cancel")).clicked { cancel = true }
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("rec_keep", i18n.tr("Keep (Enter)"), o = {intent = .Primary, disabled = p.count == 0}).clicked { keep = true }
		}
	}
	switch {
	case keep && p.count > 0:
		keymap_bind(app, c.id, Binding{p.chords})
		say(app, "%s: %s.", i18n.tr(c.title), binding_text(Binding{p.chords}))
		palette_recorder_end(app)
	case cancel || !open:
		palette_recorder_end(app)
	}
}

@(private = "file")
palette_recorder_end :: proc(app: ^App) {
	p := &app.palette
	p.recording = -1
	p.open = true   // (the palette again, its letters kept)
}

// The command of line `k` of the palette as it is now, nothing typed (the tests; -1: a setting or none).
palette_line_command :: proc(app: ^App, k: int) -> int {
	l := palette_list(app)
	recent := ui.choice_recent(&app.palette.choices, l.names)
	if k < len(recent) { return l.order[recent[k]] }
	line := k - len(recent)
	return line < len(l.order) ? l.order[line] : -1
}

// The command of the palette's first line for what is typed (the tests).
palette_first :: proc(app: ^App) -> int {
	if a := alias_command(app, ui.line_edit_string(&app.palette.field)); a != nil {
		for &c, i in COMMANDS { if &c == a { return i } }
	}
	// (ranked as the palette ranks them: ui.palette_match, the label, then the aliases, the group, then with slips)
	l := palette_list(app)
	query := ui.line_edit_string(&app.palette.field)
	best, at := min(int), -1
	for c, line in l.commands[:len(l.order)] {
		score, _, ok := ui.palette_match(query, c.label, c.group, c.tags)
		if ok && score > best { best, at = score, l.order[line] }
	}
	return at
}

@(private = "file")
palette_keep_size :: proc(app: ^App) {
	p := &app.palette
	w, h := f64(p.size.x), f64(p.size.y)
	if w == config.float_of(&app.prefs, "palette.width") && h == config.float_of(&app.prefs, "palette.height") { return }
	config.set_float(&app.prefs, "palette.width", w)
	config.set_float(&app.prefs, "palette.height", h)
}
