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
COL_COUNT_EM    :: 5.6
COL_SIZE_EM     :: 6.5
// How far the rows' pills and lines stand from the panel's sides, in ems.
ROW_INSET_EM :: 0.5
// The selection's border (sRGB): a brighter step of its fill.
SELECTION_EDGE_DARK  :: 0x35b6e9ff
SELECTION_EDGE_LIGHT :: 0x0a7cadff
// The ring of the cursor (sRGB).
CURSOR_DARK  :: 0x1aa3d9ff
CURSOR_LIGHT :: 0x0a7cadff
// The name's least width, and what a row holds besides its columns (insets, box, icon), in ems.
NAME_MIN_EM   :: 14
ROW_FIXED_EM  :: 7

// The columns after the name: as many as the panel's width holds, the size first, then the type, the counts, the date
// (File Pilot drops them in the same order when a panel narrows).
Column :: enum u8 { Size, Type, Counts, Modified }
Columns :: bit_set[Column]

details_columns :: proc(room, em: f32) -> (cols: Columns) {
	left := room / max(em, 1) - NAME_MIN_EM - ROW_FIXED_EM
	widths := [Column]f32{.Size = COL_SIZE_EM, .Type = COL_TYPE_EM, .Counts = 2 * COL_COUNT_EM, .Modified = COL_MODIFIED_EM}
	for c in Column {
		if left < widths[c] { break }
		left -= widths[c]
		cols += {c}
	}
	return
}
// The filter's width in the footer, in ems.
FILTER_EM :: 18

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
		// the mouse's side buttons: back and forward in the panel under it
		if ui.hot_within(box.key) {
			if ui.mouse_pressed(.Back) { tab_back(app, t) }
			if ui.mouse_pressed(.Forward) { tab_forward(app, t) }
		}
		room := box.rect.max.x - box.rect.min.x
		if app.inspector.open && focused { room -= app.inspector.width_px * ui.scale() }
		wide := details_columns(room, em)
		toolbar(app, p, t, index, em)
		// the list, and beside it the inspector in the panel that has the keyboard
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row(.Start, {}, "###body") {
			ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
			if ui.column(.Start, {}, "###content") {
				// (the contents of a panel without the keyboard, dimmed: the one that has it stands out)
				dim := focused || len(app.panels) == 1 ? 0 : 1 - app.settings.inactive_opacity
				switch tab_mode(t) {
				case .Details:
					header(app, t, wide, em)
					ui.next({width = ui.fill(), height = ui.fill(), transparency = dim})
					folder_list(app, t, focused, wide, false, em)
				case .List:
					ui.next({width = ui.fill(), height = ui.fill(), transparency = dim})
					folder_list(app, t, focused, {}, true, em)
				case .Columns, .Grid:
					ui.next({width = ui.fill(), height = ui.fill(), transparency = dim})
					grid_list(app, t, focused, em)
				}
			}
			if app.inspector.open && focused { inspector_build(app, t, em) }
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
	ui.next_merge({bg = draw.hex(surfaces(app).list)})
	if ui.row(.Center, {.Draw_Side_Bottom, .Draw_Background}, "###toolbar") {
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
		if ui.signal(frame).clicked { act_goto_popup(app) }
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
	ui.list_select(&t.vl, f.cursor / tab_row_items(t))
}

////////////////////////////////
// The columns

@(private = "file")
header :: proc(app: ^App, t: ^Tab, wide: Columns, em: f32) {
	f := &t.folder
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * HEADER_EM)), bg = draw.hex(surfaces(app).head)})
	if ui.row(.Center, {.Draw_Background, .Draw_Side_Bottom}, "###header") {
		ui.spacer(ui.px(em * ROW_INSET_EM))
		// the box of every row: all, some or none of them selected
		all := len(f.shown) > 0 && f.count == len(f.shown)
		if check_box(app, "check_all", all, f.count > 0 && !all, em) {
			if f.count > 0 { folder_select_none(f) } else { folder_select_all(f) }
		}
		if ui.tags("weak") {
			column_head(app, t, .Name, "Name", ui.fill(), .Left, em)
			if .Modified in wide { column_head(app, t, .Modified, "Modified", ui.px(em * COL_MODIFIED_EM), .Left, em) }
			if .Type in wide { column_head(app, t, .Type, "Type", ui.px(em * COL_TYPE_EM), .Left, em) }
			if .Counts in wide {
				plain_head("Folders", em * COL_COUNT_EM, em)
				plain_head("Files", em * COL_COUNT_EM, em)
			}
			if .Size in wide { column_head(app, t, .Size, "Size", ui.px(em * COL_SIZE_EM), .Right, em) }
		}
		ui.spacer(ui.px(em * (ROW_INSET_EM + 0.5)))
	}
}

// A column's title, a line before it; the sort's arrow at its right end. A click sorts by it.
@(private = "file")
column_head :: proc(app: ^App, t: ^Tab, key: fs.Sort_Key, title: string, width: ui.Size, align: ui.Text_Align, em: f32) {
	s := t.folder.sort
	on := s.key == key
	ui.next({width = width, height = ui.pct(1), radius = em * 0.2})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects}, fmt.tprintf("###col_%s", title)) {
		sig = ui.signal(ui.parent_box())
		if key != .Name { vrule(em, 1.2) } else { ui.spacer(ui.px(em * 0.4)) }
		if align == .Right { ui.spacer(ui.fill()) }
		ui.next({width = ui.text_size(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", title))
		if align == .Left { ui.spacer(ui.fill()) }
		if on { glyph(app, s.descending ? lucide.ARROW_DOWN : lucide.ARROW_UP, em * 1.4) } else { ui.spacer(ui.px(em * 0.4)) }
	}
	if sig.clicked {
		folder_sort_by(&t.folder, key)
		app.default_sort = t.folder.sort
	}
}

@(private = "file")
plain_head :: proc(title: string, width, em: f32) {
	ui.next({width = ui.px(width), height = ui.pct(1)})
	if ui.row(.Center, {}, fmt.tprintf("###col_%s", title)) {
		vrule(em, 1.2)
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", title))
	}
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
folder_list :: proc(app: ^App, t: ^Tab, focused: bool, wide: Columns, names_only: bool, em: f32) {
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
	look := row_look(app, focused, em)
	for row in rows.first ..< rows.last {
		e := &f.listing.entries[f.shown[row]]
		selected := f.selected[f.shown[row]]
		// (the list's own fill of the cursor's row is clear: the row draws its pill itself)
		ui.next({height = ui.px(ui.dense(em * ROW_EM)), radius = 0, bg = ui.Color{}})
		if selected && focused { ui.push_tags("selected") }
		sig := ui.list_row(&t.vl, row, e.name)
		if selected && focused { ui.pop_tags() }
		row_paint(sig.box, look, selected, row == f.cursor && (!selected || f.count > 1), row & 1 == 1)
		check := false
		if ui.parent(sig.box) { check = entry_row(app, t, e, row, selected, wide, names_only, em) }
		if row == t.vl.sel { t.cursor_rect = sig.box.rect }
		if check {
			clicked = true
			folder_pick(f, row, toggle = true)
		} else if app.settings.single_click && sig.clicked && sig.mods == {} {
			folder_pick(f, row)
			act_open(app)
			return
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

// How the rows of a list are painted, File Pilot's way: a line under each, the selection a pill a little in from the
// sides (solid while the panel has the keyboard), the cursor a ring of the accent.
Row_Look :: struct {
	edge:    ui.Color,  // the selection's border
	card:    ui.Color,  // a card's own surface (the grid), clear for a row
	card_edge: ui.Color,
	stripes: bool,      // every other row a shade lighter (the option)
	stripe:  ui.Color,
	inset:   f32,
	radius:  f32,
	line:    ui.Color,
	fill:    ui.Color,
	ring:    ui.Color,
	focused: bool,
}

@(private = "file")
Row_Paint :: struct {
	look:     ^Row_Look,
	selected: bool,
	cursor:   bool,
	odd:      bool,
}

row_look :: proc(app: ^App, focused: bool, em: f32) -> ^Row_Look {
	look := ui.frame_new(Row_Look)
	sel := selection_color(app)
	look^ = {
		inset = em * ROW_INSET_EM, radius = max(1, ui.scale()) * 2,
		line = ui.color("border") * {1, 1, 1, 0.7},
		fill = focused ? sel : sel * {1, 1, 1, 0.35},
		edge = focused ? draw.hex(app.theme_shown.light ? SELECTION_EDGE_LIGHT : SELECTION_EDGE_DARK) : draw.hex(app.theme_shown.light ? SELECTION_EDGE_LIGHT : SELECTION_EDGE_DARK) * {1, 1, 1, 0.45},
		ring = draw.hex(app.theme_shown.light ? CURSOR_LIGHT : CURSOR_DARK),
		focused = focused,
		stripes = app.settings.alternating_rows,
		stripe = ui.color("text") * {1, 1, 1, 0.035},
	}
	return look
}

// The box `b` (a row, a card) draws its pill and its ring under what it holds.
row_paint :: proc(b: ^ui.Box, look: ^Row_Look, selected, cursor: bool, odd := false) {
	d := ui.frame_new(Row_Paint)
	d^ = {look, selected, cursor && look.focused, odd}
	b.custom, b.custom_user = row_draw, d
}

@(private = "file")
row_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Row_Paint)(user)
	l := d.look
	r := b.rect
	inner := ui.Rect{{r.min.x + l.inset, r.min.y + 1}, {r.max.x - l.inset, r.max.y - 1}}
	if l.stripes && d.odd { draw.rect(dc, inner, l.stripe, radius = l.radius) }
	draw.rect(dc, {{inner.min.x, r.max.y - 1}, {inner.max.x, r.max.y}}, l.line)
	if l.card.a > 0 && !d.selected { paint_raised(dc, inner, {base = l.card, edge = l.card_edge, radii = radii_all(l.radius)}) }
	if d.selected { paint_raised(dc, inner, {base = l.fill, edge = l.edge, radii = radii_all(l.radius)}) }
	if d.cursor { draw.rect(dc, inner, l.ring, radius = l.radius, border = 1) }
}

// The cells of a row: its box, its icon, its name (or the field that renames it), its date, its type, its counts and its
// size. `names_only`: the icon and the name. True: its box was clicked.
@(private = "file")
entry_row :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, row: int, selected: bool, wide: Columns, names_only: bool, em: f32) -> (check: bool) {
	ui.spacer(ui.px(em * ROW_INSET_EM))
	if names_only {
		ui.spacer(ui.px(em * 0.4))
	} else {
		check = check_box(app, fmt.tprintf("check%d", row), selected, false, em)
	}
	folder := e.kind == .Directory
	entry_glyph(app, t.path, e^, em * 1.9)
	ui.spacer(ui.px(em * 0.5))
	entry_name(app, t, e, selected, em)
	if names_only {
		ui.spacer(ui.px(em * ROW_INSET_EM))
		return
	}
	m: Measure
	measured := false
	if folder { m, measured = measure_of(app, t, e^) }
	if !selected { ui.push_tags("weak") }
	if ui.style({font_size = em * 0.92}) {
		if .Modified in wide {
			ui.next({width = ui.px(em * COL_MODIFIED_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###m", date_text(app, e.mtime)))
		}
		if .Type in wide {
			ui.next({width = ui.px(em * COL_TYPE_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###k", type_text(e^)))
		}
		if .Counts in wide {
			count := proc(n: i64, measured: bool) -> string {
				if !measured || n == 0 { return "--" }
				return count_text(n)
			}
			ui.next({width = ui.px(em * COL_COUNT_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###fo", folder ? count(m.folders, measured) : "--"))
			ui.next({width = ui.px(em * COL_COUNT_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###fi", folder ? count(m.files, measured) : "--"))
		}
		if .Size in wide {
			size := "--"
			if e.size >= 0 { size = size_text(e.size) } else if measured && m.bytes > 0 { size = size_text(m.bytes) }
			ui.next({width = ui.px(em * COL_SIZE_EM), height = ui.pct(1), text_align = .Right})
			ui.label(fmt.tprintf("%s###s", size))
		}
	}
	if !selected { ui.pop_tags() }
	ui.spacer(ui.px(em * (ROW_INSET_EM + 0.5)))
	return
}

// The name of an entry, or the field that renames it.
entry_name :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, selected: bool, em: f32) {
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
		return
	}
	hidden := .Hidden in e.flags && !selected
	needle := t.folder.filter
	if !t.folder.flat && needle == "" {
		ui.next({width = ui.fill(), height = ui.pct(1)})
		if hidden { ui.push_tags("weak") }
		ui.label(fmt.tprintf("%s###n", shown_text(shown_name(app, e^))))
		if hidden { ui.pop_tags() }
		return
	}
	// a flat result: its name, then where it is; the letters of the filter in the accent's colour (File Pilot's search)
	ui.next({width = ui.fill(), height = ui.pct(1)})
	if ui.row(.Center, {.Clip}, "###n") {
		name := fs.base(e.name)
		ranges, _ := ui.fuzzy_find(needle, e.name)
		if hidden { ui.push_tags("weak") }
		match_text(e.name[len(e.name) - len(name):], ranges, len(e.name) - len(name), selected)
		if hidden { ui.pop_tags() }
		if dir := fs.parent(e.name); dir != "" && dir != e.name {
			if ui.tags("weak") { glyph(app, lucide.CHEVRON_RIGHT, em * 1.3) }
			if !selected { ui.push_tags("weak") }
			match_text(dir, ranges, 0, selected)
			if !selected { ui.pop_tags() }
		}
	}
}

// `text` (a part of what `ranges` were found in, from `offset`) in pieces: the matched ones in the accent's colour.
@(private = "file")
match_text :: proc(text: string, ranges: []ui.Fuzzy_Range, offset: int, selected: bool) {
	accent := selected ? draw.hex(0xffffffff) : draw.hex(CURSOR_DARK)
	at := 0
	piece :: proc(s: string, lit: bool, accent: ui.Color, n: int) {
		if s == "" { return }
		ui.next({width = ui.text_size(0), height = ui.pct(1), text_pad = 0, fg = lit ? accent : nil})
		ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###p%d", shown_text(s), n))
	}
	n := 0
	for r in ranges {
		lo, hi := r[0] - offset, r[1] - offset
		if hi <= 0 || lo >= len(text) { continue }
		lo, hi = max(lo, 0), min(hi, len(text))
		if lo > at { piece(text[at:lo], false, accent, n); n += 1 }
		piece(text[lo:hi], true, accent, n)
		n += 1
		at = hi
	}
	piece(text[at:], false, accent, n)
}

////////////////////////////////
// The footer

// The footer: one strip under the list, its cells flush with its edges, a single line between two cells: the filter at
// the left (a well, darker), the job at work, the counts and the zoom at the right.
@(private = "file")
footer :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * FOOTER_EM)), bg = draw.hex(surfaces(app).side)})
	if ui.row(.Center, {.Draw_Background, .Draw_Side_Top}, "###footer") {
		filter_field(app, t, em)
		cell_rule()
		ui.spacer(ui.fill())
		if focused { job_status(app, em) }
		cell_rule()
		ui.next({width = ui.children_sum(), height = ui.pct(1)})
		if ui.row(.Center, {}, "###stats") {
			if ui.style({font_size = em * 0.92}) {
				folders, files, folders_shown, files_shown: int
				for e in f.listing.entries { if e.kind == .Directory { folders += 1 } else { files += 1 } }
				for i in f.shown { if f.listing.entries[i].kind == .Directory { folders_shown += 1 } else { files_shown += 1 } }
				if t.walk != nil { stat(app, "walk", lucide.LOADER, fmt.tprintf("%s…", count_text(i64(tab_walked(t)))), "Entries read so far", em) }
				if f.count > 0 {
					bytes: i64
					for e in folder_targets(f) { if e.kind != .Directory && e.size > 0 { bytes += e.size } }
					stat(app, "sel", lucide.LAYERS_2, bytes > 0 ? fmt.tprintf("%d · %s", f.count, size_text(bytes)) : fmt.tprintf("%d", f.count), "Selected, and the size of their files", em)
				}
				stat(app, "fol", lucide.FOLDER, fmt.tprintf("%d/%s", folders_shown, count_text(i64(folders))), "Folders shown, of all", em)
				stat(app, "fil", lucide.FILE, fmt.tprintf("%d/%s", files_shown, count_text(i64(files))), "Files shown, of all", em)
				if t.has_space && t.space.total > 0 {
					used := 100 - int(100 * f64(t.space.free) / f64(t.space.total))
					stat(app, "disk", lucide.HARD_DRIVE, fmt.tprintf("%d%%", used), fmt.tprintf("%s free of %s", size_text(t.space.free), size_text(t.space.total)), em)
				}
				ui.spacer(ui.px(em * 0.5))
				zoom_pill(app, t, em)
				ui.spacer(ui.px(em * 0.5))
			}
		}
	}
}

// A line between two cells of a strip, as high as the strip.
cell_rule :: proc() {
	ui.next({width = ui.px(max(1, ui.scale())), height = ui.pct(1), bg = ui.color("border")})
	ui.build_box({.Draw_Background}, fmt.tprintf("###cell_rule%d", ui.parent_box().child_count))
}

@(private = "file")
Zoom_Draw :: struct { t: f32, fill, track: ui.Color }

@(private = "file")
zoom_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Zoom_Draw)(user)
	r := b.rect
	rad := (r.max.y - r.min.y) * 0.22
	draw.rect(dc, r, d.track, radius = rad)
	w := max((r.max.x - r.min.x) * d.t, (r.max.y - r.min.y) * 0.3)
	draw.rect(dc, {r.min, {r.min.x + w, r.max.y}}, d.fill, radius = rad)
}

// The zoom as File Pilot shows it: its percent on a bar of the accent; a click goes to the next view, a right click to
// the one before.
@(private = "file")
zoom_pill :: proc(app: ^App, t: ^Tab, em: f32) {
	z := ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)]
	d := ui.frame_new(Zoom_Draw)
	d^ = {f32(z.percent) / 100, selection_color(app), ui.color("border")}
	ui.next({width = ui.px(em * 3.4), height = ui.px(em * 1.5)})
	b := ui.custom("###zoom", zoom_draw, d, {.Clickable})
	// (the percent over the bar: a box of its own, drawn after the bar)
	if ui.parent(b) {
		ui.next({width = ui.fill(), height = ui.pct(1), text_align = .Center, fg = z.percent > 40 ? draw.hex(0xffffffff) : nil})
		ui.label(fmt.tprintf("%d%%###pct", z.percent))
	}
	sig := ui.signal(b)
	if sig.clicked { tab_set_zoom(app, t, (t.zoom + 1) % len(ZOOMS)) }
	if sig.right_clicked { tab_set_zoom(app, t, (t.zoom + len(ZOOMS) - 1) % len(ZOOMS)) }
	if ui.hovered_for(sig, 0.4) {
		if ui.tooltip() {
			ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 1.8))})
			ui.label("The view: a click zooms in, a right click out (Ctrl+wheel, Ctrl+= and Ctrl+-)###tip")
		}
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
	// (a well, the whole height of the footer: darker than it; a line of the accent along its top while it searches
	// every folder below)
	ui.next({width = ui.px(em * FILTER_EM), height = ui.pct(1), bg = draw.hex(surfaces(app).top)})
	if ui.row(.Center, {.Draw_Background}, "###filterbox") {
		if t.flat { tab_flat_line(ui.parent_box()) }
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.5) }
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
			if ui.key_press(.Down) { list_move(t, tab_row_items(t)) }
			if ui.key_press(.Up) { list_move(t, -tab_row_items(t)) }
		}
		if res.cancelled {
			if len(t.filter.buf) > 0 { ui.field_clear(&t.filter) }
			t.focus_due = .List
		}
		if res.committed { act_open(app) }
		if ui.tags("weak") {
			if icon_action(app, "flat", lucide.FOLDER_TREE, command_tip("flat"), em, on = t.flat) {
				t.flat = !t.flat
				tab_load(app, t)
				t.focus_due = .Filter
			}
			if len(t.filter.buf) > 0 || t.flat {
				if icon_action(app, "filter_clear", lucide.X, "Clear the filter, leave the search (Escape)", em) {
					ui.field_clear(&t.filter)
					if t.flat { t.flat = false; tab_load(app, t) }
				}
			}
		}
		ui.spacer(ui.px(em * 0.2))
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

// The name as the options show it: the extension of a file left out when they say so.
shown_name :: proc(app: ^App, e: fs.Entry) -> string {
	if app.settings.show_extensions || e.kind == .Directory { return e.name }
	ext := fs.extension(e.name)
	return ext == "" ? e.name : e.name[:len(e.name) - len(ext) - 1]
}

// The accent along the top of `b` (the filter while it searches every folder below).
@(private = "file")
tab_flat_line :: proc(b: ^ui.Box) {
	b.custom = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		r := b.rect
		draw.rect(dc, {r.min, {r.max.x, r.min.y + max(2, ui.scale() * 2)}}, ui.color("accent"))
	}
}
