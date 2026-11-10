package classeur

// The command palette (Ctrl+Shift+P, F1): every command of the table, found by a few letters of its name (fuzzy:
// "nf" finds "New folder"), run with Enter or a click. The rows show the keys of each command.

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "gt:draw"
import lucide "gt:lucide"
import "gt:ui"

PALETTE_ROWS :: 10

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
}

palette_build :: proc(app: ^App) {
	p := &app.palette
	if !p.open { return }
	em := ui.font_size()
	pw := min(em * 44, app.room * ui.scale() * 0.92)

	rows := make([dynamic]Palette_Row, context.temp_allocator)
	needle := strings.clone(ui.field_string(&p.field), context.temp_allocator)
	for c, i in COMMANDS {
		score, ranges, ok := ui.fuzzy_score(needle, c.title)
		if ok { append(&rows, Palette_Row{i, score, ranges}) }
	}
	slice.stable_sort_by(rows[:], proc(a, b: Palette_Row) -> bool { return a.score > b.score })
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
			if ui.column(.Center, id = "###pal_rows") {
				for vi in 0 ..< min(n, PALETTE_ROWS) {
					at := p.scroll + vi
					r := rows[at]
					c := COMMANDS[r.command]
					selected := at == p.sel
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
					help := p.recording >= 0 ? "Press the keys (two for a sequence)   Enter: keep   Backspace: its own keys   Esc: cancel" : "Up, Down: choose   Enter: run   Ctrl+Enter: a key of your own   Alt+Enter: the letters typed, an alias"
					ui.label(fmt.tprintf("%d of %d commands   %s###pal_count", n, len(COMMANDS), help))
				}
			}
		}
	}
	if run >= 0 {
		p.open = false
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
