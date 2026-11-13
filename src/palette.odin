package classeur

// The command palette (Ctrl+K, Ctrl+Shift+P): the toolkit's (ui.palette), over every command of the table under its
// group, then every setting (prefs_page.palette_commands). A few letters find a command ("nf": New folder), an alias of
// one's own too (its tags); Enter runs it. Ctrl+Enter records keys of one's own for it (the recorder, below), Alt+Enter
// makes the letters typed its alias. The commands run last come first, under Recent.

import "core:fmt"
import "core:strings"
import config "gt:config"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:ui"

PALETTE_RECENT :: 6

Palette :: struct {
	using pal: ui.Command_Palette,
	recording: int,         // the command whose keys are recorded (-1: none): the recorder's dialog is open
	chords:    [2]Shortcut, // what was pressed so far
	count:     int,
}

palette_free :: proc(p: ^Palette) {
	ui.palette_destroy(&p.pal)
	p^ = {}
}

palette_open :: proc(app: ^App) {
	p := &app.palette
	ui.palette_open(&p.pal)
	p.size = {f32(config.int_of(&app.prefs, "palette.width")), f32(config.int_of(&app.prefs, "palette.height"))}
	p.recording = -1
}

// The groups of the commands, in the palette's order, and the group of each (by its id).
@(rodata)
COMMAND_GROUPS := [?]string{"Go", "Tabs and panels", "Files", "Selection", "View", "Find", "Program"}

command_group :: proc(id: string) -> int {
	has :: strings.has_prefix
	switch {
	case has(id, "app_"): return 6
	case id == "open" || id == "up" || id == "back" || id == "forward" || id == "home" || id == "goto" || id == "goto_popup" || id == "open_folder" || id == "refresh": return 0
	case has(id, "tab") || has(id, "panel") || id == "open_new_tab" || id == "open_other_panel" || has(id, "layout") || id == "lock": return 1
	case has(id, "select"): return 3
	case has(id, "view") || has(id, "zoom") || has(id, "sort") || has(id, "group") || id == "tree" || id == "hidden" || id == "sidebar" || id == "folders_mixed" || id == "inspector": return 4
	case id == "filter" || id == "flat" || id == "types" || id == "files_only" || id == "folders_only" || id == "every_type": return 5
	case id == "palette" || id == "shortcuts" || id == "options" || id == "setup" || id == "jobs" || id == "jobs_cancel": return 6
	}
	return 2
}

// A command run from the palette goes first in its Recent group (kept in palette.recent).
palette_note_run :: proc(app: ^App, id: string) {
	recent := strings.split(config.string_of(&app.prefs, "palette.recent"), ",", context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, id)
	n := 1
	for x in recent {
		if x == "" || x == id || n >= PALETTE_RECENT { continue }
		strings.write_byte(&b, ',')
		strings.write_string(&b, x)
		n += 1
	}
	config.set_string(&app.prefs, config.ref_of(&app.prefs, "palette.recent"), strings.to_string(b))
}

// The palette's list: the program's commands by group (`order`: each line's command), then the settings (`settings`:
// each one's preference); the keys' texts (one's own), the aliases as tags, the recent ones, an alias typed whole first.
@(private = "file")
Palette_List :: struct {
	commands: []ui.Command,
	order:    []int,      // line -> COMMANDS index, for the program's commands (the lines before the settings)
	settings: []string,   // the settings' names, after them
	opts:     ui.Palette_Options,
}

@(private = "file")
palette_list :: proc(app: ^App) -> (l: Palette_List) {
	cmds := make([dynamic]ui.Command, context.temp_allocator)
	order := make([dynamic]int, context.temp_allocator)
	keys := make([dynamic]string, context.temp_allocator)
	// (Tab 1 to Last tab would take nine lines of every search: they show once "tab" is typed)
	tabs := strings.has_prefix(strings.to_lower(strings.trim_space(ui.field_string(&app.palette.field)), context.temp_allocator), "tab")
	for g in 0 ..< len(COMMAND_GROUPS) {
		for &c, i in COMMANDS {
			if command_group(c.id) != g || (!tabs && tab_pick_command(c.id)) { continue }
			// (the toolkit's palette has no line that cannot run: one that would do nothing now is not offered)
			if c.enabled != nil && !c.enabled(app) { continue }
			tags := make([dynamic]string, context.temp_allocator)
			append(&tags, ..c.tags)
			for alias, id in app.keymap.aliases { if id == c.id { append(&tags, alias) } }
			append(&cmds, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = c.keys, tags = tags[:]})
			append(&order, i)
			append(&keys, command_keys(app, &c))
		}
	}
	settings, names := prefs_page.palette_commands(&app.prefs, options_page(app))
	append(&cmds, ..settings)
	l.commands, l.order, l.settings = cmds[:], order[:], names
	l.opts.keys = keys[:]
	l.opts.foot = "Enter: run   Ctrl+Enter: a key of your own   Alt+Enter: the letters typed, its alias"
	// (the commands run last, by their line)
	recent := make([dynamic]int, context.temp_allocator)
	for id in strings.split(config.string_of(&app.prefs, "palette.recent"), ",", context.temp_allocator) {
		for c, line in order { if id != "" && COMMANDS[c].id == id { append(&recent, line) } }
	}
	l.opts.recent = recent[:]
	if a := alias_command(app, ui.field_string(&app.palette.field)); a != nil {
		for c, line in order { if &COMMANDS[c] == a { l.opts.first = line } }
	}
	return
}

// One of the commands that show the tab of a number (Alt+1 to Alt+9).
tab_pick_command :: proc(id: string) -> bool {
	return id == "tab_last" || (len(id) == 5 && strings.has_prefix(id, "tab_") && id[4] >= '1' && id[4] <= '9')
}

// The sheet of the keys (F1) while it is open: every command that has keys under its group, the person's own keys
// when they set some (a sequence reads "Ctrl+M, T", as the sheet joins a command's two chords).
shortcuts_build :: proc(app: ^App) {
	list := make([dynamic]ui.Command, context.temp_allocator)
	if app.shortcuts_open {
		for g in 0 ..< len(COMMAND_GROUPS) {
			for &c in COMMANDS {
				if command_group(c.id) != g { continue }
				keys := c.keys
				if b, ok := app.keymap.custom[c.id]; ok { keys = b.chords }
				append(&list, ui.Command{label = c.title, group = COMMAND_GROUPS[g], icon = c.icon, keys = keys})
			}
		}
	}
	ui.shortcuts_sheet("shortcuts", list[:], &app.shortcuts_open)
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
	chosen, resized := ui.palette(&p.pal, l.commands, nil, l.opts)
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
		needle := strings.trim_space(ui.field_string(&p.field))
		if needle != "" {
			keymap_alias(app, needle, c.id)
			say(app, "%s: an alias of %s.", needle, c.title)
		}
		p.open = true
	case:
		palette_note_run(app, c.id)
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
	w := em * ui.CONFIRM_WIDTH_EM
	if ui.modal("palette_keys", w, &open) {
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
				say(app, "%s: its own keys again.", c.title)
				cancel = true
			case:
				if p.count == 2 { p.count = 0; p.chords = {} }
				p.chords[p.count] = Shortcut{key, mods}
				p.count += 1
			}
		}
		if ui.dialog_header("rec_title", fmt.tprintf("Keys for %s", ui.text_shown(c.title)), {icon = lucide.KEYBOARD, icon_font = app.icons, close = true}) {}
		if ui.dialog_body("rec_body") {
			if ui.tags("weak") {
				ui.next({width = ui.fill()})
				ui.paragraph("Press them: two for a sequence. Backspace first gives it its own keys again.###rec_help")
			}
			ui.spacer(ui.px(em * 0.8))
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.6))})
			if ui.row(.Center, id = "###rec_keys") {
				ui.spacer(ui.fill())
				ui.kbd(p.count == 0 ? "Press the keys…" : binding_text(Binding{p.chords}))
				ui.spacer(ui.fill())
			}
		}
		if ui.dialog_buttons("rec_buttons") {
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("Cancel###rec_cancel", intent = .Cancel).clicked { cancel = true }
			ui.spacer(ui.px(em * 0.6))
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
			if ui.button("Keep (Enter)###rec_keep", intent = .Primary, disabled = p.count == 0).clicked { keep = true }
		}
	}
	switch {
	case keep && p.count > 0:
		keymap_bind(app, c.id, Binding{p.chords})
		say(app, "%s: %s.", c.title, binding_text(Binding{p.chords}))
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
	if k < len(l.opts.recent) { return l.order[l.opts.recent[k]] }
	line := k - len(l.opts.recent)
	return line < len(l.order) ? l.order[line] : -1
}

// The command of the palette's first line for what is typed (the tests).
palette_first :: proc(app: ^App) -> int {
	if a := alias_command(app, ui.field_string(&app.palette.field)); a != nil {
		for &c, i in COMMANDS { if &c == a { return i } }
	}
	// (ranked as the palette ranks them: ui.palette_match, the label, then the aliases, the group, then with slips)
	l := palette_list(app)
	query := ui.field_string(&app.palette.field)
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
	w, h := i64(p.size.x), i64(p.size.y)
	if w == config.int_of(&app.prefs, "palette.width") && h == config.int_of(&app.prefs, "palette.height") { return }
	config.set_int(&app.prefs, config.ref_of(&app.prefs, "palette.width"), w)
	config.set_int(&app.prefs, config.ref_of(&app.prefs, "palette.height"), h)
}
