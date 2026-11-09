package classeur

// The command palette (Ctrl+Shift+P, F1): every command of the table, found by a few letters of its name (fuzzy:
// "nf" finds "New folder"), run with Enter or a click. The rows show the keys of each command.

import "core:fmt"
import "core:math"
import "core:slice"
import "gt:draw"
import "gt:ui"

PALETTE_ROWS :: 10

Palette :: struct {
	open:      bool,
	field:     ui.Text_Field,
	sel:       int,
	scroll:    int,
	focus_due: bool,
	mouse:     [2]f32,
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
	needle := ui.field_string(&p.field)
	for c, i in COMMANDS {
		score, ranges, ok := ui.fuzzy_score(needle, c.title)
		if ok { append(&rows, Palette_Row{i, score, ranges}) }
	}
	slice.stable_sort_by(rows[:], proc(a, b: Palette_Row) -> bool { return a.score > b.score })
	n := len(rows)
	if n > 0 {
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
				if res.changed { p.sel, p.scroll = 0, 0 }
				if res.cancelled { p.open = false }
				if res.committed && n > 0 { run = rows[p.sel].command }
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
						for k, ki in c.keys {
							if k.key == .None { continue }
							if ki > 0 { ui.spacer(ui.px(em * 0.3)) }
							ui.kbd(shortcut_text(k))
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
					ui.label(fmt.tprintf("%d of %d commands   Up, Down: choose   Enter: run   Esc: close###pal_count", n, len(COMMANDS)))
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
