package classeur

// The command palette (Ctrl+Shift+P, F1): every command of the table, found by a few letters of its name (fuzzy:
// "nf" finds "New folder"), run with Enter or a click. The rows show the keys of each command.

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import config "gt:config"
import "gt:draw"
import lucide "gt:lucide"
import "gt:ui"

PALETTE_ROWS :: 12
PALETTE_RECENT :: 6

Palette :: struct {
	open:      bool,
	field:     ui.Text_Field,
	sel:       int,
	scroll:    int,
	focus_due: bool,
	mouse:     [2]f32,
	recording: int,         // the command whose keys are recorded (-1: none; keymap.odin)
	chords:    [2]Shortcut, // what was pressed so far
	count:     int,
}

palette_free :: proc(p: ^Palette) {
	ui.field_destroy(&p.field)
	p^ = {}
}

palette_open :: proc(app: ^App) {
	p := &app.palette
	p.open = true
	ui.field_clear(&p.field)
	p.sel, p.scroll = 0, 0
	p.focus_due = true
	p.recording = -1
}

@(private = "file")
Palette_Row :: struct {
	command: int,
	score:   int,
	ranges:  []ui.Fuzzy_Range,
	header:  string,   // a group's title above this row ("": none)
}

// The groups of the commands, in the palette's order, and the group of each (by its id).
@(rodata)
COMMAND_GROUPS := [?]string{"Go", "Tabs and panels", "Files", "Selection", "View", "Find", "Program"}

command_group :: proc(id: string) -> int {
	has :: strings.has_prefix
	switch {
	case id == "open" || id == "up" || id == "back" || id == "forward" || id == "home" || id == "goto" || id == "goto_popup" || id == "open_folder" || id == "refresh": return 0
	case has(id, "tab") || has(id, "panel") || id == "open_new_tab" || id == "open_other_panel" || has(id, "layout") || id == "lock": return 1
	case has(id, "select"): return 3
	case has(id, "view") || has(id, "zoom") || has(id, "sort") || has(id, "group") || id == "tree" || id == "hidden" || id == "sidebar" || id == "folders_mixed" || id == "inspector": return 4
	case id == "filter" || id == "flat" || id == "types" || id == "files_only" || id == "folders_only" || id == "every_type": return 5
	case id == "palette" || id == "options" || id == "setup" || id == "jobs" || id == "jobs_cancel": return 6
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
	prefs_save(app)
}

palette_build :: proc(app: ^App) {
	p := &app.palette
	if !p.open { return }
	em := ui.font_size()
	pw := min(em * 44, app.room * ui.scale() * 0.92)

	rows := make([dynamic]Palette_Row, context.temp_allocator)
	needle := strings.clone(ui.field_string(&p.field), context.temp_allocator)
	if strings.trim_space(needle) == "" {
		// nothing typed: the commands run last, then every command under its group's title
		for id, k in strings.split(config.string_of(&app.prefs, "palette.recent"), ",", context.temp_allocator) {
			for c, i in COMMANDS {
				if c.id == id && id != "" { append(&rows, Palette_Row{command = i, header = k == 0 ? "Recent" : ""}) }
			}
		}
		for g in 0 ..< len(COMMAND_GROUPS) {
			first := true
			for c, i in COMMANDS {
				if command_group(c.id) != g { continue }
				append(&rows, Palette_Row{command = i, header = first ? COMMAND_GROUPS[g] : ""})
				first = false
			}
		}
	} else {
		// letters typed: the commands that have them, the best first (a command's alias counts as its title)
		for c, i in COMMANDS {
			score, ranges, ok := ui.fuzzy_score(needle, c.title)
			if ok { append(&rows, Palette_Row{command = i, score = score, ranges = ranges}) }
		}
		slice.stable_sort_by(rows[:], proc(a, b: Palette_Row) -> bool { return a.score > b.score })
	}
	// (an alias typed whole: its command first)
	if a := alias_command(app, needle); a != nil {
		for &row, k in rows {
			if COMMANDS[row.command].id != a.id { continue }
			first := row
			ordered_remove(&rows, k)
			inject_at(&rows, 0, first)
			break
		}
	}
	n := len(rows)
	// recording a command's keys: what is pressed is taken (Enter keeps it, Escape forgets it, Backspace first: its
	// own keys again)
	if p.recording >= 0 {
		palette_record(app)
	} else if n > 0 {
		if ui.key_press(.Down) { p.sel = (p.sel + 1) % n }
		if ui.key_press(.Up) { p.sel = (p.sel + n - 1) % n }
		if ui.key_press(.Page_Down) { p.sel = min(p.sel + PALETTE_ROWS, n - 1) }
		if ui.key_press(.Page_Up) { p.sel = max(p.sel - PALETTE_ROWS, 0) }
		p.sel = clamp(p.sel, 0, n - 1)
		if p.sel < p.scroll { p.scroll = p.sel }
		if p.sel >= p.scroll + PALETTE_ROWS { p.scroll = p.sel - PALETTE_ROWS + 1 }
		p.scroll = clamp(p.scroll, 0, max(n - PALETTE_ROWS, 0))
	}
	mouse := ui.mouse_pos()
	moved := abs(mouse.x - p.mouse.x) + abs(mouse.y - p.mouse.y) > 0.5
	p.mouse = mouse
	run := -1

	if ui.modal("palette", pw, &p.open, 0.12) {
		if ui.style({width = ui.px(pw)}) {
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.2))})
			if ui.row(.Center, id = "###pal_head") {
				ui.spacer(ui.px(em * 0.8))
				input_key := ui.key_from_string(ui.parent_box().key, "###pal_input")
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.3))})
				res := ui.line_edit("###pal_input", &p.field, "Type a command")
				if res.changed && p.recording >= 0 {
					ui.field_set(&p.field, needle)   // (the keys recorded are not letters of the search)
				} else if res.changed {
					p.sel, p.scroll = 0, 0
				}
				if res.cancelled { p.open = false }
				if res.committed && n > 0 && p.recording < 0 { run = rows[p.sel].command }
				// Ctrl+Enter: record the chosen command's keys; Alt+Enter: the letters typed, its alias
				if p.recording < 0 && n > 0 && ui.key_press(.Return, {.Ctrl}) { p.recording, p.count = rows[p.sel].command, 0 }
				if p.recording < 0 && n > 0 && ui.key_press(.Return, {.Alt}) && strings.trim_space(needle) != "" {
					keymap_alias(app, needle, COMMANDS[rows[p.sel].command].id)
					say(app, "%s: an alias of %s.", needle, COMMANDS[rows[p.sel].command].title)
				}
				if p.focus_due { ui.set_focus(input_key); p.focus_due = false }
				ui.spacer(ui.px(em * 0.8))
			}
			ui.hline(ui.px(pw))
			ui.spacer(ui.px(em * 0.3))
			ui.next({width = ui.px(pw), height = ui.children_sum()})
			if ui.row(.Start, id = "###pal_body") {
			// (the bar is as tall as the rows were last frame: a percent of a parent sized by its children is not known)
			rows_box := ui.box_from_key(ui.key_from_string(ui.parent_box().key, "###pal_rows"))
			rows_h := rows_box != nil ? rows_box.size.y : em * 2.3 * PALETTE_ROWS
			ui.next({width = ui.px(pw - em * 0.8), height = ui.children_sum()})
			if ui.column(.Center, {.Scroll_Self}, "###pal_rows") {
				// (the wheel scrolls the rows)
				if d := ui.signal(ui.parent_box()).scrolled.y; d != 0 {
					p.scroll = clamp(p.scroll + (d > 0 ? 3 : -3), 0, max(n - PALETTE_ROWS, 0))
				}
				for vi in 0 ..< min(n, PALETTE_ROWS) {
					at := p.scroll + vi
					r := rows[at]
					c := COMMANDS[r.command]
					selected := at == p.sel
					if r.header != "" {
						ui.next({width = ui.px(pw - em * 1.6), height = ui.px(ui.dense(em * 1.7))})
						if ui.row(.End, {}, fmt.tprintf("###pal_head_%d", at)) {
							ui.spacer(ui.px(em * 0.5))
							ui.push_tags("weak")
							ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.85)})
							ui.label(fmt.tprintf("%s###h", r.header))
							ui.pop_tags()
						}
					}
					if selected { ui.push_tags("selected") }
					ui.next({width = ui.px(pw - em * 1.0), height = ui.px(ui.dense(em * 2.3)), radius = em * 0.45, border = selected ? nil : draw.Color{}})
					flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Draw_Border}
					if selected { flags += {.Draw_Background} }
					sig: ui.Signal
					if ui.row(.Center, flags, fmt.tprintf("###pal_row_%s", c.id)) {
						sig = ui.signal(ui.parent_box())
						ui.spacer(ui.px(em * 0.4))
						if ui.tags("weak") { glyph(app, c.icon, em * 1.8) }
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label_fuzzy(c.title, r.ranges)
						// its aliases, and its group while searching
						ui.push_tags("weak")
						for alias, id in app.keymap.aliases {
							if id != c.id { continue }
							ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1), font_size = math.round(em * 0.85)})
							ui.label(fmt.tprintf("%s###alias_%s", alias, alias))
						}
						if needle != "" {
							ui.next({width = ui.text_size(em * 0.6), height = ui.pct(1), font_size = math.round(em * 0.85)})
							ui.label(fmt.tprintf("%s###grp", COMMAND_GROUPS[command_group(c.id)]))
						}
						ui.pop_tags()
						if p.recording == r.command {
							ui.push_tags("selected")
							ui.kbd(p.count == 0 ? "Press the keys…" : binding_text(Binding{p.chords}))
							ui.pop_tags()
						} else {
							for b, bi in command_bindings(app, &COMMANDS[r.command]) {
								if bi > 0 { ui.spacer(ui.px(em * 0.3)) }
								ui.kbd(binding_text(b))
							}
						}
						// File Pilot's +: a key of one's own for it
						if selected || sig.hovering {
							ui.spacer(ui.px(em * 0.3))
							if icon_action(app, fmt.tprintf("bind_%s", c.id), lucide.PLUS, "A key of your own (Ctrl+Enter)", em) { p.recording, p.count = r.command, 0 }
						}
						ui.spacer(ui.px(em * 0.5))
					}
					if selected { ui.pop_tags() }
					if sig.clicked { run = r.command }
					if sig.hovering && moved { p.sel = at }
				}
			}
			// the scroll bar: where the rows shown are among all
			if n > PALETTE_ROWS {
				d := ui.frame_new(Scroll_Draw)
				d^ = {f32(p.scroll) / f32(n), f32(min(n, p.scroll + PALETTE_ROWS)) / f32(n), ui.color("border"), ui.color("weak text")}
				ui.next({width = ui.px(em * 0.5), height = ui.px(rows_h)})
				ui.custom("###pal_bar", scroll_draw, d)
			}
			}
			if n == 0 {
				if ui.tags("weak") {
					ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 3.5)), text_align = .Center})
					ui.label("No command has these letters.###pal_none")
				}
			}
			ui.spacer(ui.px(em * 0.3))
			ui.hline(ui.px(pw))
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.1))})
			if ui.row(.Center, id = "###pal_foot") {
				ui.spacer(ui.px(em * 0.9))
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.85)})
					help := p.recording >= 0 ? "Press the keys (two for a sequence)   Enter: keep   Backspace: its own keys   Esc: cancel" : "Up, Down: choose   Enter: run   Ctrl+Enter: a key of your own   Alt+Enter: an alias"
					// (nothing typed: every command, the recent ones counted once)
					count := needle == "" ? fmt.tprintf("%d commands", len(COMMANDS)) : fmt.tprintf("%d of %d commands", n, len(COMMANDS))
					ui.label(fmt.tprintf("%s   %s###pal_count", count, help))
				}
			}
		}
	}
	if run >= 0 {
		p.open = false
		palette_note_run(app, COMMANDS[run].id)
		if t := current_tab(app); t != nil { t.focus_due = .List }
		COMMANDS[run].run(app)
	}
}

// The keys pressed while a command's keys are recorded.
@(private = "file")
palette_record :: proc(app: ^App) {
	p := &app.palette
	key, mods, ok := ui.key_take()
	if !ok { return }
	c := &COMMANDS[p.recording]
	switch {
	case key == .Escape && mods == {}:
		p.recording = -1
	case key == .Return && mods == {} && p.count > 0:
		keymap_bind(app, c.id, Binding{p.chords})
		say(app, "%s: %s.", c.title, binding_text(Binding{p.chords}))
		p.recording = -1
	case key == .Backspace && mods == {} && p.count == 0:
		keymap_unbind(app, c.id)
		say(app, "%s: its own keys again.", c.title)
		p.recording = -1
	case:
		if p.count == 2 { p.count = 0; p.chords = {} }
		p.chords[p.count] = Shortcut{key, mods}
		p.count += 1
	}
}

// The command of the palette's first row as last built (the tests).
palette_first :: proc(app: ^App) -> int {
	best, at := -1, -1
	for c, i in COMMANDS {
		score, _, ok := ui.fuzzy_score(ui.field_string(&app.palette.field), c.title)
		if ok && score > best { best, at = score, i }
	}
	return at
}

@(private = "file")
Scroll_Draw :: struct { from, to: f32, track, thumb: ui.Color }

@(private = "file")
scroll_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Scroll_Draw)(user)
	r := b.rect
	x0, x1 := r.min.x + (r.max.x - r.min.x) * 0.3, r.max.x - (r.max.x - r.min.x) * 0.3
	h := r.max.y - r.min.y
	draw.rect(dc, {{x0, r.min.y}, {x1, r.max.y}}, d.track)
	draw.rect(dc, {{x0, r.min.y + h * d.from}, {x1, r.min.y + h * d.to}}, d.thumb)
}
