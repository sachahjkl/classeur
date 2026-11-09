package classeur

// The options, File Pilot's (Ctrl+,): a list over the window, filtered by what is typed ("Select an option..."), each
// line an option's title and what it does, its control at the right: a switch, a choice (a click: the next one), a
// slider. Up and Down choose a line, Enter uses it, Left and Right move a choice or a slider, Escape closes.

import "core:fmt"
import "core:strings"
import config "gt:config"
import lucide "gt:lucide"
import "gt:ui"

OPTIONS_ROWS :: 9

@(private = "file")
Option :: struct { name, title: string }

@(private = "file", rodata)
OPTIONS := [?]Option{
	{"look.round_corners", "Round Corners"},
	{"look.follow_system", "System Light / Dark Scheme"},
	{"look.theme", "Color Scheme"},
	{"look.alternating_rows", "Alternating Row Colors"},
	{"look.inactive_opacity", "Inactive Panel Contents Opacity"},
	{"look.font_size", "Font Size"},
	{"files.show_extensions", "Show File Extension"},
	{"files.show_hidden", "Show Hidden Files"},
	{"files.folders_first", "Folders First"},
	{"files.measure_folders", "Measure Folders"},
	{"open.single_click", "Single Click to Open"},
}

Options :: struct {
	open:      bool,
	field:     ui.Text_Field,
	sel:       int,
	scroll:    int,
	focus_due: bool,
}

options_free :: proc(o: ^Options) {
	ui.field_destroy(&o.field)
	o^ = {}
}

act_options :: proc(app: ^App) {
	o := &app.options
	o.open = !o.open
	ui.field_clear(&o.field)
	o.sel, o.scroll, o.focus_due = 0, 0, true
}

// What a step of a choice or a slider does: -1 back, +1 on, 0 the same as Enter (a switch flips, a choice goes on).
@(private = "file")
option_step :: proc(app: ^App, name: string, dir: int) {
	p := &app.prefs
	r := config.ref_of(p, name)
	d := config.entry(p, r).def
	switch d.kind {
	case .Bool:
		if dir == 0 { config.set_bool(p, r, !config.get_bool(p, r)) }
	case .String:
		if len(d.choices) == 0 { return }
		at := 0
		for c, i in d.choices { if c == config.get_string(p, r) { at = i } }
		at = (at + (dir < 0 ? len(d.choices) - 1 : 1)) % len(d.choices)
		config.set_string(p, r, d.choices[at])
	case .Float:
		step := (d.max - d.min) / 14
		v := clamp(config.get_float(p, r) + f64(dir == 0 ? 1 : dir) * step, d.min, d.max)
		_ = config.set_from_string(p, name, fmt.tprintf("%.3f", v), .User)
	case .Int:
	}
	prefs_save(app)
	settings_apply(app)
}

options_build :: proc(app: ^App) {
	o := &app.options
	if !o.open { return }
	em := ui.font_size()
	width := min(em * 50, app.room * ui.scale() * 0.92)
	query := strings.to_lower(ui.field_string(&o.field), context.temp_allocator)
	shown := make([dynamic]int, context.temp_allocator)
	for opt, i in OPTIONS {
		d := config.entry(&app.prefs, config.ref_of(&app.prefs, opt.name)).def
		if query == "" || strings.contains(strings.to_lower(opt.title, context.temp_allocator), query) || strings.contains(strings.to_lower(d.description, context.temp_allocator), query) {
			append(&shown, i)
		}
	}
	n := len(shown)
	if n > 0 {
		if ui.key_press(.Down) { o.sel = (o.sel + 1) % n }
		if ui.key_press(.Up) { o.sel = (o.sel + n - 1) % n }
		o.sel = clamp(o.sel, 0, n - 1)
		if ui.key_press(.Right) { option_step(app, OPTIONS[shown[o.sel]].name, 1) }
		if ui.key_press(.Left) { option_step(app, OPTIONS[shown[o.sel]].name, -1) }
		if o.sel < o.scroll { o.scroll = o.sel }
		if o.sel >= o.scroll + OPTIONS_ROWS { o.scroll = o.sel - OPTIONS_ROWS + 1 }
		o.scroll = clamp(o.scroll, 0, max(n - OPTIONS_ROWS, 0))
	}
	if ui.modal("options", width, &o.open, 0.12) {
		if ui.style({width = ui.px(width)}) {
			ui.next({width = ui.px(width), height = ui.px(ui.dense(em * 3.0))})
			if ui.row(.Center, {.Draw_Side_Bottom}, "###opt_head") {
				ui.spacer(ui.px(em * 0.6))
				if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.7) }
				key := ui.key_from_string(ui.parent_box().key, "###opt_input")
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2))})
				res: ui.Edit_Result
				if ui.tags("bare") { res = ui.line_edit("###opt_input", &o.field, "Select an option...") }
				if res.changed { o.sel, o.scroll = 0, 0 }
				if res.cancelled { o.open = false }
				if res.committed && n > 0 { option_step(app, OPTIONS[shown[o.sel]].name, 0) }
				if o.focus_due { ui.set_focus(key); o.focus_due = false }
				if ui.tags("weak") { if icon_action(app, "opt_close", lucide.X, "Close (Escape)", em) { o.open = false } }
				ui.spacer(ui.px(em * 0.4))
			}
			for vi in 0 ..< min(n, OPTIONS_ROWS) {
				at := o.scroll + vi
				option_row(app, OPTIONS[shown[at]], at == o.sel, width, em)
			}
			if n == 0 {
				if ui.tags("weak") {
					ui.next({width = ui.px(width), height = ui.px(ui.dense(em * 3.5)), text_align = .Center})
					ui.label("No option has these words.###opt_none")
				}
			}
			ui.next({width = ui.px(width), height = ui.px(ui.dense(em * 2.4))})
			if ui.row(.Center, {.Draw_Side_Top}, "###opt_foot") {
				ui.spacer(ui.fill())
				if ui.tags("weak") {
					if ui.style({font_size = em * 0.86}) {
						for hint in ([][2]string{{"Up", ""}, {"Down", "to navigate"}, {"Enter", "to use"}, {"Escape", "to dismiss"}}) {
							ui.kbd(hint[0])
							ui.spacer(ui.px(em * 0.3))
							if hint[1] != "" {
								ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1)})
								ui.label(fmt.tprintf("%s###h%s", hint[1], hint[0]))
								ui.spacer(ui.px(em * 0.6))
							}
						}
					}
				}
				ui.spacer(ui.fill())
			}
		}
	}
}

@(private = "file")
option_row :: proc(app: ^App, opt: Option, selected: bool, width, em: f32) {
	p := &app.prefs
	r := config.ref_of(p, opt.name)
	d := config.entry(p, r).def
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within}
	if selected { flags += {.Draw_Border, .Draw_Background} }
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.3))})
	if ui.row(.Center, {}, fmt.tprintf("###optline_%s", opt.name)) {
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1), radius = em * 0.25, border = selected ? ui.color("accent") : nil, bg = selected ? ui.color("track") : nil})
		option_cells(app, opt, p, r, d, flags, em)
		ui.spacer(ui.px(em * 0.4))
	}
}

@(private = "file")
option_cells :: proc(app: ^App, opt: Option, p: ^config.Prefs, r: config.Ref, d: config.Def, flags: ui.Box_Flags, em: f32) {
	if ui.row(.Center, flags, fmt.tprintf("###opt_%s", opt.name)) {
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.4)})
			ui.label(fmt.tprintf("%s###t", opt.title))
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 1.3), font_size = em * 0.85})
				ui.label(fmt.tprintf("%s###d", d.description))
			}
			ui.spacer(ui.fill())
		}
		ui.spacer(ui.px(em * 0.6))
		switch d.kind {
		case .Bool:
			v := config.get_bool(p, r)
			was := v
			ui.next({width = ui.px(em * 3.4), height = ui.px(em * 1.8)})
			ui.toggle("###sw", "", &v)
			if v != was { option_step(app, opt.name, 0) }
		case .String:
			ui.next({width = ui.px(em * 11), height = ui.px(em * 1.9), radius = em * 0.25})
			sig := ui.button(fmt.tprintf("%s   ›###choice", config.get_string(p, r)))
			if sig.clicked { option_step(app, opt.name, 1) }
			if sig.right_clicked { option_step(app, opt.name, -1) }
		case .Float:
			v := f32(config.get_float(p, r))
			ui.next({width = ui.px(em * 11), height = ui.px(em * 1.8)})
			if ui.slider("###slider", &v, f32(d.min), f32(d.max)).dragging || v != f32(config.get_float(p, r)) {
				if v != f32(config.get_float(p, r)) {
					_ = config.set_from_string(p, opt.name, fmt.tprintf("%.3f", v), .User)
					prefs_save(app)
					settings_apply(app)
				}
			}
		case .Int:
		}
		ui.spacer(ui.px(em * 0.8))
	}
}
