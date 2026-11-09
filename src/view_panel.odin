package classeur

// A panel, File Pilot's: its toolbar (back, forward, up, the history; the lock and the bookmark; the path; the panel's
// menu), the columns' header, the list of the folder (only the rows in view are built: a folder of any size costs the
// same per frame), and its footer (the filter, the counts). Its tabs are in the row at the top of the window (view.odin).

import "core:fmt"
import "core:slice"
import "core:strings"
import "gt:draw"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

// Heights in ems.
TOOLBAR_EM :: 2.6
HEADER_EM  :: 2.1
ROW_EM     :: 2.2
FOOTER_EM  :: 2.3
// The widths of the columns after the name, in ems.
COL_CHECK_EM    :: 2.4
COL_MODIFIED_EM :: 9.5
COL_TYPE_EM     :: 8.5
COL_COUNT_EM    :: 4.6
COL_SIZE_EM     :: 6.5
// Under this width (ems), the date column is left out.
WIDE_EM :: 62
// The filter's width in the footer, in ems.
FILTER_EM :: 15

panel_build :: proc(app: ^App, p: ^Panel, index: int, em: f32) -> ui.Rect {
	focused := index == app.focus
	box := ui.build_box({.Clip}, fmt.tprintf("###panel%d", index))
	if ui.parent(box) {
		// a press anywhere in the panel makes it the one the keyboard works in; the keyboard goes back to the list unless
		// the press was on a text field (a button, a column, a crumb keep no keyboard of their own)
		if (ui.mouse_pressed() || ui.mouse_pressed(.Right)) && ui.hot_within(box.key) {
			app.focus = index
			t := panel_tab(p)
			if t != nil && t.focus_due == .None && !slice.contains(app.text_keys_before[:], ui.hot_key()) { t.focus_due = .List }
		}
		t := panel_tab(p)
		if t == nil { return box.rect }
		wide := (box.rect.max.x - box.rect.min.x) > em * WIDE_EM
		toolbar(app, p, t, index, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		if t.view == .Grid {
			grid_list(app, t, focused, em)
		} else {
			header(app, t, wide, em)
			ui.next({width = ui.fill(), height = ui.fill()})
			folder_list(app, t, focused, wide, em)
		}
		footer(app, t, focused, em)
	}
	return box.rect
}

////////////////////////////////
// The toolbar

@(private = "file")
toolbar :: proc(app: ^App, p: ^Panel, t: ^Tab, index: int, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOOLBAR_EM))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###toolbar") {
		ui.spacer(ui.px(em * 0.3))
		if ui.tags("weak") {
			if icon_action(app, "back", lucide.ARROW_LEFT, command_tip("back"), em, len(t.back) > 0) { tab_back(app, t) }
			if icon_action(app, "forward", lucide.ARROW_RIGHT, command_tip("forward"), em, len(t.forward) > 0) { tab_forward(app, t) }
			if icon_action(app, "up", lucide.ARROW_UP, command_tip("up"), em, fs.parent(t.path) != "") { tab_up(app, t) }
			if icon_action(app, "history", lucide.CHEVRON_DOWN, "The folders before", em, len(t.back) > 0) {
				app.focus = index
				history_menu_open(app, t, ui.parent_box().rect)
			}
			vrule(em)
			if icon_action(app, "lock", lucide.LOCK, t.locked ? "Unlock the tab: folders open in it" : "Lock the tab: folders open in a new tab", em, on = t.locked) { t.locked = !t.locked }
			marked := slice.contains(app.bookmarks[:], t.path)
			if icon_action(app, "bookmark", lucide.BOOKMARK, command_tip("bookmark"), em, on = marked) { bookmark_toggle(app, t.path) }
			vrule(em)
		}
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
		if t.address_open {
			address_field(app, t, em)
		} else {
			crumbs(app, t, em)
		}
		if ui.tags("weak") {
			if icon_action(app, fmt.tprintf("panelmenu%d", index), lucide.ELLIPSIS, "The panel's menu", em) {
				app.focus = index
				panel_menu_open(app, ui.mouse_pos())
			}
		}
		ui.spacer(ui.px(em * 0.3))
	}
}

// The path as words, one per folder, the last one bright; a click on the empty part types the path instead.
@(private = "file")
crumbs :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next_merge({radius = 0})
	if ui.row(.Center, {.Clickable, .Clip}, "###crumbs") {
		frame := ui.parent_box()
		parts := home_crumbs(app, t.path)
		// (a long path shows its end: the first crumbs go when the room is short)
		room := frame.size.x - em * 2
		first := 0
		widths := make([]f32, len(parts), context.temp_allocator)
		total: f32
		for c, i in parts {
			widths[i] = ui.text_width(ui.top_style().font, em, c.name) + em * 2.0
			total += widths[i]
		}
		for first < len(parts) - 1 && total > room && room > 0 {
			total -= widths[first]
			first += 1
		}
		if first > 0 {
			if ui.tags("weak") { glyph(app, lucide.ELLIPSIS, em * 1.3) }
		}
		for c, i in parts[first:] {
			at := first + i
			if i > 0 || first > 0 {
				if ui.tags("weak") { glyph(app, lucide.CHEVRON_RIGHT, em * 1.1) }
			}
			last := at == len(parts) - 1
			ui.next({width = ui.text_size(em * 0.35), height = ui.px(ui.dense(em * 1.7)), radius = em * 0.15})
			sig: ui.Signal
			if !last { ui.push_tags("weak") }
			if ui.tags("ghost_button") { sig = ui.button(fmt.tprintf("%s###crumb%d", shown_text(c.name), at)) }
			if !last { ui.pop_tags() }
			if sig.clicked && !last { tab_go(app, t, c.path) }
			if sig.middle_clicked { tab_open(app, current_panel(app), c.path, current_panel(app).active + 1) }
		}
		ui.spacer(ui.fill())
		if ui.signal(frame).clicked { act_goto(app) }
	}
}

@(private = "file")
address_field :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next_merge({radius = em * 0.15})
	if ui.field_frame("###address") {
		if ui.tags("weak") { glyph(app, lucide.FOLDER_SEARCH, em * 1.7) }
		key := ui.key_from_string(ui.parent_box().key, "###addr")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###addr", &t.address, "A folder's path") }
		note_text_field(app, key)
		if t.focus_due == .Address {
			ui.set_focus(key)
			t.focus_due = .None
		} else if !res.focused && ui.focus_key() != key {
			t.address_open = false   // (the keyboard went elsewhere: the crumbs again)
		}
		if res.cancelled {
			t.address_open = false
			t.focus_due = .List
		}
		if res.committed {
			path := fs.clean(ui.field_string(&t.address), context.temp_allocator)
			info, ok := fs.stat(path)
			switch {
			case !ok:
				say(app, "%s does not exist.", path)
			case info.kind == .Directory:
				t.address_open = false
				t.focus_due = .List
				tab_go(app, t, path)
			case:
				// a file: its folder, the file at the cursor
				t.address_open = false
				t.focus_due = .List
				tab_go(app, t, fs.parent(path))
				delete(t.reveal_name)
				t.reveal_name = strings.clone(fs.base(path))
			}
		}
	}
}

@(private = "file")
list_move :: proc(t: ^Tab, by: int) {
	f := &t.folder
	if len(f.shown) == 0 { return }
	folder_pick(f, clamp(f.cursor + by, 0, len(f.shown) - 1))
	ui.list_select(&t.vl, f.cursor)
}

////////////////////////////////
// The columns

@(private = "file")
header :: proc(app: ^App, t: ^Tab, wide: bool, em: f32) {
	f := &t.folder
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * HEADER_EM))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###header") {
		// the box of every row: all, some or none of them selected
		all := len(f.shown) > 0 && f.count == len(f.shown)
		if check_box(app, "check_all", all, f.count > 0 && !all, em) {
			if f.count > 0 { folder_select_none(f) } else { folder_select_all(f) }
		}
		if ui.tags("weak") {
			column_head(app, t, .Name, "Name", ui.fill(), .Left, em)
			if wide { column_head(app, t, .Modified, "Modified", ui.px(em * COL_MODIFIED_EM), .Left, em) }
			column_head(app, t, .Type, "Type", ui.px(em * COL_TYPE_EM), .Left, em)
			plain_head("Folders", em * COL_COUNT_EM, em)
			plain_head("Files", em * COL_COUNT_EM, em)
			column_head(app, t, .Size, "Size", ui.px(em * COL_SIZE_EM), .Right, em)
		}
		ui.spacer(ui.px(em * 0.9))
	}
}

@(private = "file")
column_head :: proc(app: ^App, t: ^Tab, key: fs.Sort_Key, title: string, width: ui.Size, align: ui.Text_Align, em: f32) {
	s := t.folder.sort
	on := s.key == key
	ui.next({width = width, height = ui.pct(1), radius = 0})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects}, fmt.tprintf("###col_%s", title)) {
		sig = ui.signal(ui.parent_box())
		if align == .Right { ui.spacer(ui.fill()) }
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.text_size(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", title))
		if on { glyph(app, s.descending ? lucide.ARROW_DOWN : lucide.ARROW_UP, em * 1.3) }
		ui.spacer(ui.px(em * 0.4))
	}
	if sig.clicked {
		folder_sort_by(&t.folder, key)
		app.default_sort = t.folder.sort
	}
}

@(private = "file")
plain_head :: proc(title: string, width, em: f32) {
	ui.next({width = ui.px(width), height = ui.pct(1), text_align = .Right})
	ui.label(fmt.tprintf("%s###col_%s", title, title))
}

@(private = "file")
Check_Draw :: struct { on, some: bool, line, fill, mark: ui.Color }

@(private = "file")
check_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Check_Draw)(user)
	r := b.rect
	c := (r.min + r.max) * 0.5
	s := min(r.max.x - r.min.x, r.max.y - r.min.y) * 0.5
	box := ui.Rect{c - s * 0.5, c + s * 0.5}
	w := max(1, s * 0.09)
	if d.on {
		draw.rect(dc, box, d.fill, radius = s * 0.12)
		// the tick
		draw.line(dc, {box.min.x + s * 0.22, c.y + s * 0.02}, {box.min.x + s * 0.42, c.y + s * 0.22}, w * 1.6, d.mark)
		draw.line(dc, {box.min.x + s * 0.42, c.y + s * 0.22}, {box.max.x - s * 0.2, c.y - s * 0.2}, w * 1.6, d.mark)
	} else {
		draw.rect(dc, box, d.line, radius = s * 0.12, border = w)
		if d.some { draw.rect(dc, {{box.min.x + s * 0.25, c.y - w}, {box.max.x - s * 0.25, c.y + w}}, d.line) }
	}
}

// The box at the start of a row (and of the header): clicked, it says so.
@(private = "file")
check_box :: proc(app: ^App, id: string, on, some: bool, em: f32) -> bool {
	d := ui.frame_new(Check_Draw)
	d^ = {on, some, ui.color("weak text"), ui.color("accent"), ui.color("bright")}
	if ui.tags("weak") { d.line = ui.color("text") }
	d.mark = {1, 1, 1, 1}
	ui.next({width = ui.px(em * COL_CHECK_EM), height = ui.pct(1)})
	b := ui.custom(fmt.tprintf("###%s", id), check_draw, d, {.Clickable})
	return ui.signal(b).clicked
}

////////////////////////////////
// The list

// What the list says when it has no row (reading, an error, empty, all filtered out). True: it said it.
empty_state :: proc(app: ^App, t: ^Tab, em: f32) -> bool {
	f := &t.folder
	if f.loaded && f.listing.error == .None && len(f.shown) > 0 { return false }
	message := "Reading…"
	switch {
	case !f.loaded:                    message = "Reading…"
	case f.listing.error != .None:     message = fs.ERROR_TEXT[f.listing.error]
	case len(f.listing.entries) == 0:  message = "This folder is empty."
	case f.filter != "":               message = "No name has these letters."
	case:                              message = "Only hidden files are here (Ctrl+H shows them)."
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	empty := ui.build_box({.Clickable}, "###empty")
	if ui.parent(empty) {
		if ui.tags("weak") {
			ui.next({width = ui.fill(), height = ui.px(em * 5), text_align = .Center})
			ui.label(fmt.tprintf("%s###msg", message))
		}
	}
	if ui.signal(empty).right_clicked && f.loaded && f.listing.error == .None { entry_menu_open(app, t, ui.mouse_pos(), on_entry = false) }
	return true
}

@(private = "file")
folder_list :: proc(app: ^App, t: ^Tab, focused, wide: bool, em: f32) {
	f := &t.folder
	if empty_state(app, t, em) { return }
	// the cursor and the list's active row are the same row
	t.vl.sel = f.cursor
	labels := make([]string, len(f.shown), context.temp_allocator)
	for i, row in f.shown { labels[row] = f.listing.entries[i].name }
	rows, ok := ui.vlist("###list", &t.vl, f.ids[:], labels)
	if !ok { return }
	if t.focus_due == .List && t.vl.key != 0 {
		ui.set_focus(t.vl.key)
		t.focus_due = .None
	}
	clicked := false
	selection := selection_color(app)
	for row in rows.first ..< rows.last {
		e := &f.listing.entries[f.shown[row]]
		// the selection solid when the panel has the keyboard, faded when not; the cursor alone is the list's own
		selected := f.selected[f.shown[row]]
		bg: Maybe(ui.Color)
		if selected { bg = focused ? selection : selection * {1, 1, 1, 0.55} }
		ui.next({height = ui.px(ui.dense(em * ROW_EM)), radius = 0, flags = selected ? {.Draw_Background} : {}, bg = bg})
		if selected { ui.push_tags("selected") }
		sig := ui.list_row(&t.vl, row, e.name)
		if selected { ui.pop_tags() }
		check := false
		if ui.parent(sig.box) { check = entry_row(app, t, e, row, selected, wide, em) }
		if row == t.vl.sel { t.cursor_rect = sig.box.rect }
		if check {
			clicked = true
			folder_pick(f, row, toggle = true)
		} else if sig.pressed {
			clicked = true
			folder_pick(f, row, extend = .Shift in sig.mods, toggle = .Ctrl in sig.mods)
		}
		if sig.right_clicked {
			clicked = true
			if !folder_row_selected(f, row) { folder_pick(f, row) }
			f.cursor = row
			entry_menu_open(app, t, ui.mouse_pos())
		}
		if sig.middle_clicked && e.kind == .Directory {
			tab_open(app, current_panel(app), fs.join(t.path, e.name, context.temp_allocator), current_panel(app).active + 1)
		}
		if sig.double_clicked && !check {
			folder_pick(f, row)
			act_open(app)
			return
		}
	}
	// a move of the list's own keys (Up, Down, Page Up, Home, type-ahead): the cursor's row alone is selected
	if t.vl.changed && !clicked && t.vl.sel >= 0 { folder_pick(f, t.vl.sel) }
	if t.vl.activated && !clicked { act_open(app) }
}

// The cells of a row: its box, its icon, its name (or the field that renames it), its date, its type, its counts and its
// size. True: its box was clicked.
@(private = "file")
entry_row :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, row: int, selected, wide: bool, em: f32) -> (check: bool) {
	check = check_box(app, fmt.tprintf("check%d", row), selected, false, em)
	folder := e.kind == .Directory
	entry_glyph(app, e^, em * 1.9)
	ui.spacer(ui.px(em * 0.5))
	r := &app.rename
	if r.active && r.tab == t.id && r.name == e.name {
		key := ui.key_from_string(ui.parent_box().key, "###rename")
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7)), radius = em * 0.15})
		res := ui.line_edit("###rename", &r.field)
		note_text_field(app, key)
		if r.focus_due {
			ui.set_focus(key)
			r.focus_due = false
		} else if !res.focused && ui.focus_key() != key {
			rename_commit(app)   // (the keyboard went elsewhere: what was typed stays)
		}
		if res.committed { rename_commit(app) }
		if res.cancelled { rename_end(app) }
	} else {
		ui.next({width = ui.fill(), height = ui.pct(1)})
		hidden := .Hidden in e.flags && !selected
		if hidden { ui.push_tags("weak") }
		ui.label(fmt.tprintf("%s###n", shown_text(e.name)))
		if hidden { ui.pop_tags() }
	}
	m: Measure
	measured := false
	if folder { m, measured = measure_of(app, t, e^) }
	if !selected { ui.push_tags("weak") }
	if ui.style({font_size = em * 0.92}) {
		if wide {
			ui.next({width = ui.px(em * COL_MODIFIED_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###m", date_text(app, e.mtime)))
		}
		ui.next({width = ui.px(em * COL_TYPE_EM), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###k", type_text(e^)))
		count := proc(n: i64, measured: bool) -> string {
			if !measured || n == 0 { return "--" }
			return count_text(n)
		}
		ui.next({width = ui.px(em * COL_COUNT_EM), height = ui.pct(1), text_align = .Right})
		ui.label(fmt.tprintf("%s###fo", folder ? count(m.folders, measured) : "--"))
		ui.next({width = ui.px(em * COL_COUNT_EM), height = ui.pct(1), text_align = .Right})
		ui.label(fmt.tprintf("%s###fi", folder ? count(m.files, measured) : "--"))
		size := ""
		if e.size >= 0 { size = size_text(e.size) } else if measured { size = size_text(m.bytes) }
		ui.next({width = ui.px(em * COL_SIZE_EM), height = ui.pct(1), text_align = .Right})
		ui.label(fmt.tprintf("%s###s", size))
	}
	if !selected { ui.pop_tags() }
	ui.spacer(ui.px(em * 0.9))
	return
}

////////////////////////////////
// The footer

@(private = "file")
footer :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * FOOTER_EM))})
	if ui.row(.Center, {.Draw_Side_Top}, "###footer") {
		filter_field(app, t, em)
		ui.spacer(ui.fill())
		if ui.style({font_size = em * 0.9}) {
			if focused { job_status(app, em) }
			folders, files, folders_shown, files_shown: int
			for e in f.listing.entries { if e.kind == .Directory { folders += 1 } else { files += 1 } }
			for i in f.shown { if f.listing.entries[i].kind == .Directory { folders_shown += 1 } else { files_shown += 1 } }
			stat(app, "sel", lucide.LAYERS_2, fmt.tprintf("%d", f.count), "Selected", em)
			stat(app, "fol", lucide.FOLDER, fmt.tprintf("%d/%d", folders_shown, folders), "Folders shown, of all", em)
			stat(app, "fil", lucide.FILE, fmt.tprintf("%d/%d", files_shown, files), "Files shown, of all", em)
			if t.has_space && t.space.total > 0 {
				used := 100 - int(100 * f64(t.space.free) / f64(t.space.total))
				stat(app, "disk", lucide.HARD_DRIVE, fmt.tprintf("%d%%", used), fmt.tprintf("%s free of %s", size_text(t.space.free), size_text(t.space.total)), em)
			}
			vrule(em)
			if ui.tags("weak") {
				if icon_action(app, "view_details", lucide.LIST, command_tip("view_details"), em, on = t.view == .Details) { t.view = .Details }
				if icon_action(app, "view_grid", lucide.LAYOUT_GRID, command_tip("view_grid"), em, on = t.view == .Grid) { t.view = .Grid }
			}
		}
		ui.spacer(ui.px(em * 0.5))
	}
}

// A count of the footer: its icon and its number, its meaning in its tooltip.
@(private = "file")
stat :: proc(app: ^App, id, icon, text, tip: string, em: f32) {
	ui.next({width = ui.children_sum(), height = ui.pct(1)})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable}, fmt.tprintf("###stat_%s", id)) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, icon, em * 1.5) }
		ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###v", text))
		ui.spacer(ui.px(em * 0.4))
	}
	if ui.hovered_for(sig, 0.4) {
		if ui.tooltip() {
			ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 1.8))})
			ui.label(fmt.tprintf("%s###tip", tip))
		}
	}
}

@(private = "file")
filter_field :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next({width = ui.px(em * FILTER_EM), height = ui.pct(1)})
	if ui.row(.Center, {.Draw_Side_Right}, "###filterbox") {
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.6) }
		key := ui.key_from_string(ui.parent_box().key, "###filter")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###filter", &t.filter, "Filter...") }
		note_text_field(app, key)
		if t.focus_due == .Filter {
			ui.set_focus(key)
			t.focus_due = .None
		}
		folder_set_filter(&t.folder, ui.field_string(&t.filter))
		if res.focused {
			// the list's moves from the filter: the keyboard stays in it
			if ui.key_press(.Down) { list_move(t, 1) }
			if ui.key_press(.Up) { list_move(t, -1) }
		}
		if res.cancelled {
			if len(t.filter.buf) > 0 { ui.field_clear(&t.filter) }
			t.focus_due = .List
		}
		if res.committed { act_open(app) }
		ui.spacer(ui.px(em * 0.3))
	}
}

// The crumbs of a path; under the home folder they start at it, named "Home".
home_crumbs :: proc(app: ^App, path: string) -> []fs.Crumb {
	parts := fs.crumbs(path)
	home := fs.crumbs(app.home)
	if len(home) == 0 || len(parts) < len(home) || parts[len(home) - 1].path != app.home { return parts }
	out := parts[len(home) - 1:]
	out[0].name = "Home"
	return out
}
