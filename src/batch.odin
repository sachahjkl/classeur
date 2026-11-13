package classeur

// Batch rename (File Pilot's): F2 with several items selected. Each new name is made from a pattern, then a find and
// replace, then a case; the list shows each old name and its new one as they are typed, the names that cannot be had in
// red. The pattern's fields (the extension is kept after the pattern unless the pattern has {ext}):
//   {name} the name without its extension   {ext} the extension (without the dot)
//   {n} a number from 1, in the list's order ({n:3}: three digits, 001)
//   {date} the date modified (2026-11-10)    {time} its time (14-05-09)
//   {id} a short id of its own (eight letters and digits)
// "Names from the clipboard": a line of the clipboard per item, in order.
// The renames are made in two steps (each to a free name first, then to its new one): two names can swap. The whole
// batch is one step of the undo.

import "core:fmt"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import lucide "gt:lucide"
import "gt:platform"
import "gt:ui"
import "fs"

BATCH_ROWS :: 12

Batch_Case :: enum u8 { Keep, Lower, Upper }

Batch :: struct {
	open:      bool,
	tab:       u64,
	dir:       string,             // owned: the folder the items are in
	names:     [dynamic]string,    // owned: the items, in the list's order
	mtimes:    [dynamic]i64,
	ids:       [dynamic]string,    // owned: each item's {id}, made once
	taken:     map[string]bool,    // owned keys: the names of the folder that are not of the batch (read at the opening)
	list:      [dynamic]string,    // owned: the names from the clipboard (empty: the pattern)
	list_asked: u64,               // the clipboard's text asked for these names (platform.clipboard_request; 0: none)
	pattern:   ui.Text_Field,
	find:      ui.Text_Field,
	replace:   ui.Text_Field,
	casing:    Batch_Case,
	tz:        ^datetime.TZ_Region,   // the local time zone ({date}, {time}); the app's
	focus_due: bool,
	scroll:    int,
}

batch_free :: proc(b: ^Batch) {
	batch_clear(b)
	delete(b.names)
	delete(b.mtimes)
	delete(b.ids)
	delete(b.taken)
	delete(b.list)
	ui.field_destroy(&b.pattern)
	ui.field_destroy(&b.find)
	ui.field_destroy(&b.replace)
	b^ = {}
}

@(private = "file")
batch_clear :: proc(b: ^Batch) {
	delete(b.dir)
	b.dir = ""
	for s in b.names { delete(s) }
	for s in b.ids { delete(s) }
	for s in b.list { delete(s) }
	for k in b.taken { delete(k) }
	clear(&b.taken)
	clear(&b.names)
	clear(&b.mtimes)
	clear(&b.ids)
	clear(&b.list)
	b.list_asked = 0
}

// The clipboard's text came (clipboard_answer): a name per line, when the batch that asked is still open.
batch_names_answer :: proc(app: ^App, r: platform.Clipboard_Reply) {
	b := &app.batch
	if r.id == 0 || r.id != b.list_asked { return }
	b.list_asked = 0
	if !b.open { return }
	for s in b.list { delete(s) }
	clear(&b.list)
	for line in strings.split_lines(strings.trim_right_space(r.text), context.temp_allocator) { append(&b.list, strings.clone(strings.trim_space(line))) }
}

batch_open :: proc(app: ^App, t: ^Tab) {
	if read_only_here(app, t) { return }
	b := &app.batch
	batch_clear(b)
	b.open, b.tab, b.focus_due, b.scroll, b.casing = true, t.id, true, 0, .Keep
	b.dir = strings.clone(t.path)
	b.tz = app.tz
	alphabet := "abcdefghijkmnpqrstuvwxyz23456789"
	mine := make(map[string]bool, context.temp_allocator)
	for e in folder_targets(&t.folder) { mine[e.name] = true }
	for e in t.folder.listing.entries { if e.name not_in mine { b.taken[fs.name_key(e.name)] = true } }
	for e in folder_targets(&t.folder) {
		append(&b.names, strings.clone(e.name))
		append(&b.mtimes, e.mtime)
		id: [8]u8
		for &c in id { c = alphabet[rand.int_max(len(alphabet))] }
		append(&b.ids, strings.clone(string(id[:])))
	}
	ui.field_set(&b.pattern, "{name}")
	ui.field_select_all(&b.pattern)
	ui.field_clear(&b.find)
	ui.field_clear(&b.replace)
}

// The new name of item `i`.
batch_name :: proc(b: ^Batch, i: int, allocator := context.temp_allocator) -> string {
	old := b.names[i]
	ext := fs.extension(old)
	stem := ext != "" ? old[:len(old) - len(ext) - 1] : old
	out: string
	if len(b.list) > 0 {
		out = i < len(b.list) ? b.list[i] : old
	} else {
		sb := strings.builder_make(context.temp_allocator)
		pat := ui.field_string(&b.pattern)
		for k := 0; k < len(pat); {
			if pat[k] == '{' {
				if end := strings.index_byte(pat[k:], '}'); end > 0 {
					field := pat[k + 1:k + end]
					if batch_field(&sb, b, i, field, stem, ext) {
						k += end + 1
						continue
					}
				}
			}
			strings.write_byte(&sb, pat[k])
			k += 1
		}
		if ext != "" && !strings.contains(pat, "{ext}") { fmt.sbprintf(&sb, ".%s", ext) }
		out = strings.to_string(sb)
	}
	if find := ui.field_string(&b.find); find != "" {
		out, _ = strings.replace_all(out, find, ui.field_string(&b.replace), context.temp_allocator)
	}
	switch b.casing {
	case .Keep:
	case .Lower: out = strings.to_lower(out, context.temp_allocator)
	case .Upper: out = strings.to_upper(out, context.temp_allocator)
	}
	return strings.clone(strings.trim_space(out), allocator)
}

@(private = "file")
batch_field :: proc(sb: ^strings.Builder, b: ^Batch, i: int, field, stem, ext: string) -> bool {
	name, _, arg := strings.partition(field, ":")
	switch name {
	case "name": strings.write_string(sb, stem)
	case "ext":  strings.write_string(sb, ext)
	case "id":   strings.write_string(sb, b.ids[i])
	case "n":
		width, _ := strconv.parse_int(arg)
		fmt.sbprintf(sb, "%0*d", max(width, 1), i + 1)
	case "date", "time":
		// (the local time, as the list shows it)
		dt, _ := time.time_to_datetime(time.unix(0, b.mtimes[i]))
		if b.tz != nil { if local, ok := timezone.datetime_to_tz(dt, b.tz); ok { dt = local } }
		y, mon, d := int(dt.year), int(dt.month), int(dt.day)
		h, mi, sec := int(dt.hour), int(dt.minute), int(dt.second)
		if name == "date" { fmt.sbprintf(sb, "%04d-%02d-%02d", y, mon, d) } else { fmt.sbprintf(sb, "%02d-%02d-%02d", h, mi, sec) }
	case:
		return false
	}
	return true
}

// Why each new name cannot be had ("": it can). From the folder's names read at the opening: nothing is asked of the
// file system while the pattern is typed.
@(private = "file")
batch_problems :: proc(b: ^Batch, news: []string) -> []string {
	out := make([]string, len(news), context.temp_allocator)
	seen := make(map[string]int, len(news), context.temp_allocator)
	for n in news { seen[fs.name_key(n, context.temp_allocator)] += 1 }
	for n, i in news {
		k := fs.name_key(n, context.temp_allocator)
		switch {
		case n == "":                                                      out[i] = "empty"
		case strings.contains_any(n, fs.SEPARATOR_STRING) || n == "." || n == "..": out[i] = "not a name"
		case seen[k] > 1:                                                  out[i] = "twice"
		case k in b.taken:                                                 out[i] = "taken"
		}
	}
	return out
}

// The renames on their way to the edits' worker and back.
@(private = "file")
Batch_Ask :: struct {
	app:   ^App,
	tab:   u64,
	pairs: [][2]string,   // owned: (before, after)
	done:  bool,          // the answer: every name given
}

// The renames, all or nothing (undo.odin's renames_swap: through free names, never over a name), by the edits' worker;
// one step of the undo.
@(private = "file")
batch_apply :: proc(app: ^App, news: []string) {
	b := &app.batch
	pairs := make([dynamic][2]string)
	for n, i in news {
		if n == b.names[i] { continue }
		append(&pairs, [2]string{fs.join(b.dir, b.names[i]), fs.join(b.dir, n)})
	}
	if len(pairs) == 0 {
		delete(pairs)
		if t := find_tab(app, b.tab); t != nil { tab_load(app, t) }
		return
	}
	a := new(Batch_Ask)
	a^ = {app = app, tab = b.tab, pairs = pairs[:]}
	app.steps_due += 1
	edit_submit(app, proc(data: rawptr) {
		a := (^Batch_Ask)(data)
		a.done = renames_swap(a.pairs, back = false)
		if !ui.post(&a.app.main.state, batch_done, a) { batch_ask_free(a) }
	}, a)
}

@(private = "file")
batch_ask_free :: proc(a: ^Batch_Ask) {
	for p in a.pairs { delete(p[0]); delete(p[1]) }
	delete(a.pairs)
	free(a)
}

// On the interface's thread: the step of the undo, said; the folder read again, whatever came of the renames.
@(private = "file")
batch_done :: proc(data: rawptr, word: u64) {
	a := (^Batch_Ask)(data)
	app := a.app
	defer batch_ask_free(a)
	answer_came(app)
	app.steps_due -= 1
	if t := find_tab(app, a.tab); t != nil { tab_load(app, t) }
	if !a.done {
		say(app, "The names could not all be given: nothing was renamed.")
		return
	}
	undo_push(app, .Rename, a.pairs)
	announce(app, .Good, "%d item%s renamed.", len(a.pairs), len(a.pairs) == 1 ? "" : "s")
}

batch_build :: proc(app: ^App, em: f32) {
	b := &app.batch
	if !b.open { return }
	n := len(b.names)
	pw := min(em * 52, app.room * ui.scale() * 0.94)
	news := make([]string, n, context.temp_allocator)
	for i in 0 ..< n { news[i] = batch_name(b, i) }
	problems := batch_problems(b, news)
	bad := 0
	for p in problems { if p != "" { bad += 1 } }
	apply := false

	if ui.modal("batch_rename", pw, &b.open, 0.1) {
		if ui.style({width = ui.px(pw)}) {
			if ui.dialog_header("batch_head", fmt.tprintf("Rename %d items", n), {icon = lucide.PENCIL, icon_font = app.icons, close = true}) {}
			// (Enter in a field renames)
			if batch_field_row(app, "Pattern", "###bpat", &b.pattern, "{name}", em, pw, focus = b.focus_due) { apply = true }
			b.focus_due = false
			if batch_field_row(app, "Find", "###bfind", &b.find, "Text to replace", em, pw) { apply = true }
			if batch_field_row(app, "Replace", "###brep", &b.replace, "With", em, pw) { apply = true }
			ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.6))})
			if ui.row(.Center, id = "###batch_opts") {
				ui.spacer(ui.px(em * 0.9))
				// (the case: one of three, the toolkit's segmented control)
				casing := int(b.casing)
				// (three equal parts: each word must fit a third)
				ui.next({width = ui.px(em * 18), height = ui.px(ui.dense(em * 2.2))})
				ui.segmented("###case", {"As is", "lower", "UPPER"}, &casing, tips = {"The case of each name kept", "Every letter in lower case", "Every letter in upper case"})
				b.casing = Batch_Case(casing)
				ui.spacer(ui.fill())
				ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
				if ui.button(len(b.list) > 0 ? "Pattern again###blist" : "Names from the clipboard###blist").clicked {
					if len(b.list) > 0 {
						for s in b.list { delete(s) }
						clear(&b.list)
					} else {
						// (the clipboard's owner may be another program, slow or hung: the names come in a later frame)
						b.list_asked = platform.clipboard_request(app.main.win, .Text)
					}
				}
				ui.spacer(ui.px(em * 0.9))
			}
			if ui.tags("weak") {
				ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 1.8)), font_size = em * 0.85})
				if ui.row(.Center, id = "###batch_help") {
					ui.spacer(ui.px(em * 0.9))
					ui.next({width = ui.fill(), height = ui.pct(1)})
					ui.label("{name} {ext} {n} {n:3} {date} {time} {id}###bhelp")
				}
			}
			ui.hline(ui.px(pw))
			// the old names and the new ones
			if ui.key_press(.Page_Down) { b.scroll += BATCH_ROWS }
			if ui.key_press(.Page_Up) { b.scroll -= BATCH_ROWS }
			b.scroll = clamp(b.scroll, 0, max(n - BATCH_ROWS, 0))
			ui.next({width = ui.px(pw), height = ui.children_sum()})
			if ui.column(.Start, id = "###batch_rows") {
				for vi in 0 ..< min(n, BATCH_ROWS) {
					i := b.scroll + vi
					problem := problems[i]
					ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.0))})
					if ui.row(.Center, id = fmt.tprintf("###brow%d", vi)) {
						ui.spacer(ui.px(em * 0.9))
						path_icon(app, fs.join(b.dir, b.names[i], context.temp_allocator), false, em * 1.5)
						ui.spacer(ui.px(em * 0.4))
						if ui.tags("weak") {
							ui.next({width = ui.pct(0.42), height = ui.pct(1)})
							ui.label(fmt.tprintf("%s###old", ui.text_shown(b.names[i])))
						}
						if ui.tags("weak") { glyph(app, lucide.ARROW_RIGHT, em * 1.4) }
						ui.spacer(ui.px(em * 0.4))
						ui.next({width = ui.fill(), height = ui.pct(1), fg = problem != "" ? ui.color("bad text") : nil})
						ui.label(problem != "" ? fmt.tprintf("%s (%s)###new", ui.text_shown(news[i]), problem) : fmt.tprintf("%s###new", ui.text_shown(news[i])))
						ui.spacer(ui.px(em * 0.9))
					}
				}
			}
			ui.hline(ui.px(pw))
			ui.spacer(ui.px(em * 0.6))
			// (the toolkit's row of a dialog's buttons; what keeps the names from being had said before them)
			if ui.dialog_buttons("batch_buttons") {
				if ui.tags("weak") {
					ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 2.2)), font_size = em * 0.85})
					ui.label(bad > 0 ? fmt.tprintf("%d name%s cannot be had.###bstate", bad, bad == 1 ? "" : "s") : "Esc: close###bstate")
				}
				ui.spacer(ui.px(em * 0.6))
				ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
				if ui.button("Cancel###bcancel", intent = .Cancel).clicked { b.open = false }
				ui.spacer(ui.px(em * 0.6))
				ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
				if ui.button("Rename (Enter)###bapply", intent = .Primary, disabled = bad > 0).clicked { apply = true }
			}
		}
	}
	if apply && bad == 0 {
		batch_apply(app, news)
		b.open = false
		if t := find_tab(app, b.tab); t != nil { t.focus_due = .List }
	}
}

@(private = "file")
batch_field_row :: proc(app: ^App, label, id: string, field: ^ui.Text_Field, hint: string, em, pw: f32, focus := false) -> (committed: bool) {
	ui.next({width = ui.px(pw), height = ui.px(ui.dense(em * 2.6))})
	if ui.row(.Center, id = fmt.tprintf("%s_row", id)) {
		ui.spacer(ui.px(em * 0.9))
		if ui.tags("weak") {
			ui.next({width = ui.px(em * 6), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###lab", label))
		}
		key := ui.key_from_string(ui.parent_box().key, id)
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.1))})
		committed = ui.line_edit(id, field, hint).committed
		if focus { ui.set_focus(key) }
		ui.spacer(ui.px(em * 0.9))
	}
	return
}
