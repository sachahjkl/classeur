package classeur

// A panel, File Pilot's: its toolbar (back, forward, up, the history; the lock and the bookmark; the path; the panel's
// menu), the columns' header, the list of the folder (only the rows in view are built: a folder of any size costs the
// same per frame), and its footer (the filter, the counts). Its tabs are in the row at the top of the window (view.odin).

import "core:fmt"
import "core:math"
import "core:sync"
import config "gt:config"
import "core:strings"
import "core:slice"
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
ROW_LEAD_EM     :: 0.4   // between a row's edge and its icon
ICON_CELL_EM    :: 1.9   // a row's icon, which is its box too
TREE_CHEVRON_EM :: 1.6   // a tree's chevron (icon_action at 0.8 em)
COL_MODIFIED_EM :: 9.5
COL_TYPE_EM     :: 11   // (the system's names of the types: "Plain text document")
COL_COUNT_EM    :: 5.6
COL_SIZE_EM     :: 6.5
// How far the alternating rows go from the list's colour toward the headers' (sRGB).
STRIPE_SHARE :: 0.35

// `a` toward `b` by `k`, channel by channel in sRGB (0xRRGGBBAA); a's alpha.
srgb_mix :: proc(a, b: u32, k: f32) -> u32 {
	out := a & 0xff
	for shift in ([]u32{24, 16, 8}) {
		x, y := f32((a >> shift) & 0xff), f32((b >> shift) & 0xff)
		out |= u32(clamp(x + (y - x) * k + 0.5, 0, 255)) << shift
	}
	return out
}

// How far the rows' pills and lines stand from the panel's sides, in ems.
ROW_INSET_EM :: 0.5
// The name's least width, and what a row holds besides its columns (insets, box, icon), in ems.
NAME_MIN_EM   :: 14
ROW_FIXED_EM  :: 7

// The details' columns: the toolkit's table header (ui.Table_Layout, ui.table_header) over rows classeur builds. A
// column's rule resizes it, its title dragged moves it, a right click on the header shows or hides them; a panel narrower
// than its columns scrolls sideways. Their order, the ones shown and their widths are preferences (view.columns,
// view.column_widths), the same in every panel; each tab keeps its own sort.
Detail :: enum u8 { Name, Modified, Type, Folders, Files, Size }

@(rodata)
DETAIL_COLUMNS := [Detail]ui.Table_Column{
	.Name     = {title = "Name", width = 0},
	.Modified = {title = "Modified", width = COL_MODIFIED_EM, descending_first = true},
	.Type     = {title = "Type", width = COL_TYPE_EM},
	.Folders  = {title = "Folders", width = COL_COUNT_EM, number = true, unsorted = true},
	.Files    = {title = "Files", width = COL_COUNT_EM, number = true, unsorted = true},
	.Size     = {title = "Size", width = COL_SIZE_EM, number = true},
}
// (the table's columns: a slice of the table of Detail)
detail_columns :: proc() -> []ui.Table_Column { return slice.enumerated_array(&DETAIL_COLUMNS) }

@(rodata)
DETAIL_KEYS := [Detail]string{.Name = "name", .Modified = "modified", .Type = "type", .Folders = "folders", .Files = "files", .Size = "size"}
// The sort of each column (the counts have none).
@(rodata)
DETAIL_SORT := [Detail]fs.Sort_Key{.Name = .Name, .Modified = .Modified, .Type = .Type, .Folders = .Name, .Files = .Name, .Size = .Size}
DETAIL_COLUMNS_DEFAULT :: "modified,type,folders,files,size"

// view.columns ("modified,type,folders,files,size": the columns shown after the name, in their order) and
// view.column_widths ("size=8.0": the widths not their own).
columns_read :: proc(app: ^App, shown, widths: string) {
	l := &app.columns
	keys := DETAIL_KEYS
	ui.table_layout_reset(l)
	names := strings.split(shown, ",", context.temp_allocator)
	for k in 1 ..< len(Detail) { l.shown[k] = slice.contains(names, keys[Detail(k)]) }
	ui.table_order_apply(l, slice.enumerated_array(&keys), shown)
	ui.table_widths_apply(l, slice.enumerated_array(&keys), widths)
}

columns_save :: proc(app: ^App) {
	l := &app.columns
	keys := DETAIL_KEYS
	b := strings.builder_make(context.temp_allocator)
	for k in l.order {
		if k == 0 || !l.shown[k] { continue }
		if strings.builder_len(b) > 0 { strings.write_byte(&b, ',') }
		strings.write_string(&b, keys[Detail(k)])
	}
	config.set_string(&app.prefs, config.ref_of(&app.prefs, "view.columns"), strings.to_string(b))
	config.set_string(&app.prefs, config.ref_of(&app.prefs, "view.column_widths"), ui.table_widths_text(l, slice.enumerated_array(&keys)))
	prefs_save(app)
}

// The header's menu (a right click on it): the toolkit's (the column clicked back to its own width and unsorted, the
// rows unsorted, each column ticked when shown, the default columns), on the sort of the tab whose header was clicked.
columns_menu_build :: proc(app: ^App, em: f32) {
	if app.columns_menu_key == 0 { app.columns_menu_key = ui.key_from_string(0, "classeur_columns_menu") }
	if ui.ctx_menu(app.columns_menu_key, em * MENU_WIDTH_EM) {
		t := find_tab(app, app.columns_menu_tab)
		if t == nil { return }
		// (the layout is every panel's; its sort, the tab's: shown as the tab sorts, given back to it when changed)
		l := &app.columns
		header_sort_show(l, &t.folder)
		changed, sort_changed := ui.table_menu_items(l)
		if changed { columns_save(app) }
		if sort_changed { header_sort_apply(app, l, &t.folder) }
	}
}

// The tab's sort on the header's columns (a count's column has none: its sort is by name).
@(private = "file")
header_sort_show :: proc(l: ^ui.Table_Layout, f: ^Folder) {
	l.sort, l.descending = int(Detail.Name), f.sort.descending
	for k in Detail { if DETAIL_SORT[k] == f.sort.key && !DETAIL_COLUMNS[k].unsorted { l.sort = int(k) } }
}

// The header's sort given to the tab (no sort: the names' order, as the sort commands give it).
@(private = "file")
header_sort_apply :: proc(app: ^App, l: ^ui.Table_Layout, f: ^Folder) {
	s := f.sort
	s.key, s.descending = .Name, false
	if l.sort != ui.TABLE_UNSORTED { s.key, s.descending = DETAIL_SORT[Detail(l.sort)], l.descending }
	folder_set_sort(f, s)
	app.default_sort = f.sort
}

// The filter's width in the footer, in ems.
FILTER_EM :: 18

// How much the contents of panel `index` are dimmed: nothing in the panel that has the keyboard or in a panel alone,
// else what look.inactive_opacity takes away.
panel_dim :: proc(app: ^App, index: int) -> f32 {
	if index == app.focus || len(app.panels) == 1 { return 0 }
	return 1 - app.settings.inactive_opacity
}

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
			if ui.mouse_pressed(.Back) { app.focus = index; command_find("back").run(app) }
			if ui.mouse_pressed(.Forward) { app.focus = index; command_find("forward").run(app) }
		}
		drop_zone(app, box.rect, t.path)
		room := box.rect.max.x - box.rect.min.x
		// (a panel below another: its tabs at its own top, on the window's top surface)
		if p.below {
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOP_EM)), bg = draw.hex(surfaces(app).top)})
			if ui.row(.Start, {.Draw_Background}, "###below_tabs") { tab_region(app, p, index, ui.fill(), room, em) }
		}
		if app.inspector.open && focused { room -= ui.pane_extent(&app.inspector.pane, .X, inspector_pane_options(app)) * ui.scale() }
		toolbar(app, p, t, index, em)
		// the list, and beside it the inspector in the panel that has the keyboard
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row(.Start, {}, "###body") {
			// (the contents of a panel without the keyboard, its column titles with its rows, dimmed: the one that has it
			// stands out)
			ui.next({width = ui.fill(), height = ui.fill(), axis = .Y, transparency = panel_dim(app, index)})
			if ui.column(.Start, {}, "###content") {
				switch tab_mode(t) {
				case .Details:
					head := header(app, t, em)
					// (the rows as wide as the columns at least: past the panel's edge they scroll sideways, the titles too)
					ui.next({width = ui.fill(), height = ui.fill(), flags = {.View_Scroll_X, .Allow_Overflow_X}})
					folder_list(app, t, focused, false, em, head)
				case .List:
					ui.next({width = ui.fill(), height = ui.fill()})
					folder_list(app, t, focused, true, em)
				case .Columns:
					ui.next({width = ui.fill(), height = ui.fill()})
					columns_list(app, t, focused, em)
				case .Grid:
					ui.next({width = ui.fill(), height = ui.fill()})
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
			if icon_action(app, "back", lucide.ARROW_LEFT, command_tip(app, "back"), em, len(t.back) > 0) { tab_back(app, t) }
			if icon_action(app, "forward", lucide.ARROW_RIGHT, command_tip(app, "forward"), em, len(t.forward) > 0) { tab_forward(app, t) }
			if icon_action(app, "up", lucide.ARROW_UP, command_tip(app, "up"), em, fs.parent(t.path) != "") { tab_up(app, t) }
			if icon_action(app, "history", lucide.CHEVRON_DOWN, "The folders before", em, len(t.back) > 0) {
				app.focus = index
				history_menu_open(app, t, ui.parent_box().rect)
			}
			vrule(em)
			if icon_action(app, "lock", lucide.LOCK, t.locked ? "Unlock the tab: folders open in it" : "Lock the tab: folders open in a new tab", em, on = t.locked) { t.locked = !t.locked }
			marked := slice.contains(app.bookmarks[:], t.path)
			if icon_action(app, "bookmark", lucide.BOOKMARK, command_tip(app, "bookmark"), em, on = marked) { bookmark_toggle(app, t.path) }
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
		parts := home_crumbs(app, t)
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
			ui.next({width = ui.text_size(em * 0.35), height = ui.px(ui.dense(em * 1.7))})
			ui.next_merge(control_look(em))
			sig: ui.Signal
			if !last { ui.push_tags("weak") }
			if ui.tags("ghost_button") { sig = ui.button(fmt.tprintf("%s###crumb%d", shown_text(c.name), at)) }
			if !last { ui.pop_tags() }
			// (files dropped on a crumb go into its folder, as on a row)
			drop_zone(app, sig.box.rect, c.path)
			if app.drop_hover == c.path { drop_mark(sig.box) }
			if sig.clicked && !last { tab_go(app, t, c.path) }
			hover_tip(sig, home_path(app, c.path), last ? "" : "A middle click opens it in a new tab")
			if sig.middle_clicked { tab_open(app, current_panel(app), c.path, current_panel(app).active + 1) }
		}
		ui.spacer(ui.fill())
		if ui.signal(frame).clicked { act_goto_popup(app) }
	}
}

@(private = "file")
address_field :: proc(app: ^App, t: ^Tab, em: f32) {
	// the path's suggestions: the folders of the folder typed so far, found by the letters after it (GoTo's, read on a
	// worker); Up and Down choose one, Tab completes the path to it, Enter goes there, a click too
	text := strings.clone(ui.field_string(&t.address), context.temp_allocator)
	rows := fs.looks_like_path(text) ? goto_rows(app, text) : nil
	n := min(len(rows), ADDRESS_ROWS)
	key: ui.Key
	frame: ui.Rect
	popover_id := fmt.tprintf("###addr_suggest%d", t.id)
	over_suggestions := false
	if r, shown := ui.popover_rect(popover_id); shown {
		m := ui.mouse_pos()
		over_suggestions = m.x >= r.min.x && m.x < r.max.x && m.y >= r.min.y && m.y < r.max.y
	}
	ui.next_merge(control_look(em))
	if ui.field_frame("###address") {
		frame = ui.parent_box().rect
		if ui.tags("weak") { glyph(app, lucide.FOLDER_SEARCH, em * 1.7) }
		key = ui.key_from_string(ui.parent_box().key, "###addr")
		if ui.focus_key() == key && n > 0 {
			// (none chosen until Up or Down: Enter goes to the path typed)
			if ui.key_press(.Down) { t.address_sel = t.address_moved ? (t.address_sel + 1) % n : 0; t.address_moved = true }
			if ui.key_press(.Up) { t.address_sel = t.address_moved ? (t.address_sel + n - 1) % n : n - 1; t.address_moved = true }
			if ui.key_press(.Tab) {
				ui.field_set(&t.address, fmt.tprintf("%s%s", home_path(app, rows[clamp(t.address_sel, 0, n - 1)].path), fs.SEPARATOR_STRING))
				t.address_sel, t.address_moved = 0, false
			}
		}
		t.address_sel = clamp(t.address_sel, 0, max(n - 1, 0))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###addr", &t.address, "A folder's path (Tab completes it)") }
		if res.changed { t.address_sel, t.address_moved = 0, false }
		note_text_field(app, key)
		if t.focus_due == .Address {
			ui.set_focus(key)
			t.focus_due = .None
		} else if !res.focused && ui.focus_key() != key && !over_suggestions {
			t.address_open = false   // (the keyboard went elsewhere: the crumbs again; not a press on a suggestion)
		}
		if res.cancelled {
			t.address_open = false
			t.focus_due = .List
		}
		if res.committed {
			// (the suggestion chosen, else the path typed: a file's path or one that is gone, the read on a worker goes
			// to the folder that holds it)
			t.address_open = false
			t.focus_due = .List
			tab_go(app, t, t.address_moved && n > 0 ? rows[t.address_sel].path : ui.field_string(&t.address))
			t.address_moved = false
		}
	}
	if !t.address_open || n == 0 { return }
	if ui.popover(popover_id, frame, frame.max.x - frame.min.x, .Below, false) {
		for r, i in rows[:n] {
			on := t.address_moved && i == t.address_sel
			if on { ui.push_tags("selected") }
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0)), radius = 0})
			flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects}
			if on { flags += {.Draw_Background} }
			sig: ui.Signal
			if ui.row(.Center, flags, fmt.tprintf("###sugg%d", i)) {
				sig = ui.signal(ui.parent_box())
				ui.spacer(ui.px(em * 0.6))
				path_icon(app, r.path, true, em * 1.6)
				ui.spacer(ui.px(em * 0.4))
				ui.next({width = ui.fill(), height = ui.pct(1)})
				// (the folder's name, the letters typed lit: the path before it is the field's)
				ui.matched_label("###label", shown_text(r.label), r.ranges)
			}
			if on { ui.pop_tags() }
			if sig.clicked {
				t.address_open = false
				t.focus_due = .List
				tab_go(app, t, r.path)
			}
		}
		if len(rows) > n {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7)), font_size = em * 0.85})
				ui.label(fmt.tprintf("   and %d more: type a few more letters###sugg_more", len(rows) - n))
			}
		}
	}
}

// The suggestions shown under the path field, at most.
ADDRESS_ROWS :: 8

@(private = "file")
list_move :: proc(t: ^Tab, by: int) {
	f := &t.folder
	if len(f.shown) == 0 { return }
	folder_pick(f, clamp(f.cursor + by, 0, len(f.shown) - 1))
	ui.list_select(&t.vl, f.cursor / tab_row_items(t))
}

////////////////////////////////
// The columns

// The room before the first title, as a row's before its name: its edge, the tree's chevron, the icon (the box that
// checks every row stands over the icons), in ems.
@(private = "file")
header_lead_em :: proc(f: ^Folder) -> f32 {
	lead: f32 = ROW_INSET_EM + ROW_LEAD_EM + ICON_CELL_EM + 0.5
	if f.tree && f.filter == "" { lead += TREE_CHEVRON_EM }
	return lead
}

// The details' header: the toolkit's titles over the tab's columns, the tab's sort on them. Returns the box the titles
// scroll in sideways (the rows' list follows it: folder_list).
@(private = "file")
header :: proc(app: ^App, t: ^Tab, em: f32) -> ui.Key {
	f := &t.folder
	l := &app.columns
	header_sort_show(l, f)
	Head :: struct { app: ^App, t: ^Tab }
	h := ui.frame_new(Head)
	h^ = {app, t}
	ui.next({width = ui.fill(), bg = draw.hex(surfaces(app).head)})
	ev := ui.table_header("###header", l, header_lead_em(f), {
		user = h,
		// the box of every row, over the icons' column (File Pilot's): all, some or none of them selected
		lead = proc(user: rawptr, em: f32) {
			h := (^Head)(user)
			f := &h.t.folder
			ui.spacer(ui.px(em * (ROW_INSET_EM + ROW_LEAD_EM)))
			if f.tree && f.filter == "" { ui.spacer(ui.px(em * TREE_CHEVRON_EM)) }
			all := len(f.shown) > 0 && f.count == len(f.shown)
			if check_box(h.app, "check_all", all, f.count > 0 && !all, em * ICON_CELL_EM) {
				if f.count > 0 { folder_select_none(f) } else { folder_select_all(f) }
			}
		},
		// a column's filter: its funnel, while the pointer is on its title or while it filters
		title = proc(user: rawptr, k: int, hot: bool, em: f32) {
			h := (^Head)(user)
			d := Detail(k)
			if DETAIL_COLUMNS[d].unsorted { return }
			column_funnel(h.app, h.t, DETAIL_SORT[d], DETAIL_COLUMNS[d].title, hot, em)
		},
	})
	if ev.sorted { header_sort_apply(app, l, f) }   // (the third click leaves no sort: the names' order)
	if ev.resized || ev.moved { columns_save(app) }
	if ev.menu {
		if app.columns_menu_key == 0 { app.columns_menu_key = ui.key_from_string(0, "classeur_columns_menu") }
		app.columns_menu_tab = t.id
		ui.ctx_menu_open(app.columns_menu_key, ui.mouse_pos())
	}
	return ev.view
}

// The column's filter (File Pilot's and Explorer's): its funnel, over the column or lit while it filters.
@(private = "file")
column_funnel :: proc(app: ^App, t: ^Tab, key: fs.Sort_Key, title: string, hot: bool, em: f32) {
	active := column_filtered(&t.folder, key)
	if active || hot {
		if !active { ui.push_tags("weak") }
		if icon_action(app, fmt.tprintf("filter_%s", title), lucide.FILTER, fmt.tprintf("Filter by %s", title), em * 0.8, on = active) {
			column_filter_open(app, t, key)
		}
		if !active { ui.pop_tags() }
	} else {
		ui.spacer(ui.px(em * 1.6))
	}
}

@(private = "file")
Size_Bar :: struct { share: f32, color: ui.Color, em: f32 }

// The least share of the largest row's size a bar is drawn for: under it, a bar of a pixel or two reads as a stray dot.
SIZE_BAR_LEAST :: 0.02

// Whether the Size cell of `bytes` draws its bar under the size (`largest`: the largest row's).
size_bar_shown :: proc(bytes, largest: i64) -> bool {
	return bytes > 0 && largest > 0 && f64(bytes) / f64(largest) >= SIZE_BAR_LEAST
}

@(private = "file")
size_bar_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Size_Bar)(user)
	r := b.rect
	h := max(2, math.round(d.em * 0.14))
	// (its right end under the text's: the cell's padding on both sides)
	right, left := r.max.x - b.text_pad, r.min.x + b.text_pad
	w := (right - left) * clamp(d.share, 0, 1)
	if w < 1 { return }
	y := r.max.y - d.em * 0.45
	// (square at every rounding: a bar two pixels thick has no corner to round, as the toolkit squares one under 3 px)
	draw.rect(dc, {{right - w, y - h}, {right, y}}, d.color)
}

// Whether the column's filter leaves rows out.
@(private = "file")
column_filtered :: proc(f: ^Folder, key: fs.Sort_Key) -> bool {
	switch key {
	case .Name:     return f.filter != ""
	case .Modified: return f.dates_off != {}
	case .Size:     return f.sizes_off != {}
	case .Type:     return f.kinds != .All || len(f.types_off) > 0
	}
	return false
}

// A column's filter: the name's letters (the filter's field), the types' popup, the dates' or the sizes' menu.
@(private = "file")
column_filter_open :: proc(app: ^App, t: ^Tab, key: fs.Sort_Key) {
	switch key {
	case .Name:     act_filter(app)
	case .Type:     types_menu_open(app, t)
	case .Modified: rank_menu_open(app, t, .Date, ui.mouse_pos())
	case .Size:     rank_menu_open(app, t, .Size, ui.mouse_pos())
	}
}


@(private = "file")
Check_Draw :: struct { on, some: bool, line, fill, mark: ui.Color, round: f32 }

@(private = "file")
check_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Check_Draw)(user)
	r := b.rect
	c := (r.min + r.max) * 0.5
	s := min(r.max.x - r.min.x, r.max.y - r.min.y) * 0.5
	box := ui.Rect{c - s * 0.5, c + s * 0.5}
	w := max(1, s * 0.09)
	if d.on {
		draw.rect(dc, box, d.fill, radius = s * 0.12 * d.round)
		// the tick
		draw.line(dc, {box.min.x + s * 0.22, c.y + s * 0.02}, {box.min.x + s * 0.42, c.y + s * 0.22}, w * 1.6, d.mark)
		draw.line(dc, {box.min.x + s * 0.42, c.y + s * 0.22}, {box.max.x - s * 0.2, c.y - s * 0.2}, w * 1.6, d.mark)
	} else {
		draw.rect(dc, box, d.line, radius = s * 0.12 * d.round, border = w)
		if d.some { draw.rect(dc, {{box.min.x + s * 0.25, c.y - w}, {box.max.x - s * 0.25, c.y + w}}, d.line) }
	}
}

// The box of the header, `width` wide (the icons' column): clicked, it says so.
@(private = "file")
check_box :: proc(app: ^App, id: string, on, some: bool, width: f32) -> bool {
	d := ui.frame_new(Check_Draw)
	d^ = {on, some, ui.color("text"), ui.color("accent"), {1, 1, 1, 1}, corner_k()}
	ui.next({width = ui.px(width), height = ui.pct(1)})
	b := ui.custom(fmt.tprintf("###%s", id), check_draw, d, {.Clickable})
	return ui.signal(b).clicked
}

// A row's icon, which is its box too (File Pilot's): the pointer over it, or the row checked among others, shows the
// box in its place. The row takes the presses (a drag from the icon drags the row, a double click opens it); a click on
// the icon checks the row or not, the others kept (the caller reads it with the row's signal). True: the pointer is over it.
@(private = "file")
icon_check :: proc(app: ^App, t: ^Tab, e: fs.Entry, row: int, selected: bool, em: f32) -> (over: bool) {
	width := em * ICON_CELL_EM
	ui.next({width = ui.px(width), height = ui.pct(1)})
	cell := ui.build_box({}, fmt.tprintf("###check%d", row))
	m := ui.mouse_pos()
	r := cell.rect   // (the last layout's)
	over = m.x >= r.min.x && m.x < r.max.x && m.y >= r.min.y && m.y < r.max.y
	if ui.parent(cell) {
		if over || selected && t.folder.count > 1 {
			d := ui.frame_new(Check_Draw)
			d^ = {selected, false, ui.color("text"), ui.color("accent"), {1, 1, 1, 1}, corner_k()}
			ui.next({width = ui.px(width), height = ui.pct(1)})
			ui.custom("###box", check_draw, d)
		} else {
			entry_glyph(app, t.path, e, width)
		}
	}
	return
}

////////////////////////////////
// The list

// What the list says when it has no row (reading, an error, empty, all filtered out). True: it said it.
empty_state :: proc(app: ^App, t: ^Tab, em: f32) -> bool {
	f := &t.folder
	if f.loaded && f.listing.error == .None && len(f.shown) > 0 { return false }
	// what it is, and what can be done about it: each button runs a command's procedure (the toolkit's empty state)
	Case :: enum { Reading, Error, Empty, Filter, Funnels, Hidden }
	c: Case
	switch {
	case !f.loaded:                    c = .Reading
	case f.listing.error != .None:     c = .Error
	case len(f.listing.entries) == 0:  c = .Empty
	case f.filter != "":               c = .Filter
	case folder_types_filtered(f):     c = .Funnels
	case:                              c = .Hidden
	}
	e: ui.Empty_State
	switch c {
	case .Reading:
	case .Error:   e = {icon = lucide.ALERT_CIRCLE, title = fs.ERROR_TEXT[f.listing.error], actions = {"Go up", "Try again"}}
	case .Empty:   e = {icon = lucide.FOLDER_OPEN, title = "This folder is empty", actions = {"New folder", "Paste"}}
	case .Filter:  e = {icon = lucide.FOLDER_SEARCH, title = "No name matches", note = fmt.tprintf("Nothing here has the letters %q.", f.filter), actions = {"Clear the filter"}}
	case .Funnels: e = {icon = lucide.FILTER, title = "No row fits the filters", note = "The types or the columns' funnels leave every row out.", actions = {"Show every row"}}
	case .Hidden:  e = {icon = lucide.EYE_OFF, title = "Only hidden files are here", actions = {"Show hidden files"}}
	}
	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
	empty := ui.build_box({.Clickable}, "###empty")
	if ui.parent(empty) {
		if c == .Reading {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 5), text_align = .Center})
				ui.label("Reading…###msg")
			}
		} else {
			a := ui.empty_state("folder_empty", e)
			switch {
			case a < 0:
			case c == .Error:   if a == 0 { tab_up(app, t) } else { tab_load(app, t) }
			case c == .Empty:   if a == 0 { act_new_folder(app) } else { act_paste(app) }
			case c == .Filter:
				ui.field_clear(&t.filter)
				folder_set_filter(f, "")
				if t.flat { t.flat = false; tab_load(app, t) }
				t.focus_due = .List
			case c == .Funnels:
				act_every_type(app)
				folder_all_ranks(f, .Date)
				folder_all_ranks(f, .Size)
			case c == .Hidden:  act_toggle_hidden(app)
			}
		}
	}
	if ui.signal(empty).right_clicked && f.loaded && f.listing.error == .None { entry_menu_open(app, t, ui.mouse_pos(), on_entry = false) }
	return true
}

@(private = "file")
// The rows of the details (`head`: the header's titles, which scroll sideways with them: a panel narrower than the
// columns scrolls), or of the names alone (`names_only`).
folder_list :: proc(app: ^App, t: ^Tab, focused: bool, names_only: bool, em: f32, head: ui.Key = 0) {
	f := &t.folder
	if empty_state(app, t, em) { return }
	// the cursor and the list's active row are the same row
	t.vl.sel = f.cursor
	labels := make([]string, len(f.shown), context.temp_allocator)
	for i, row in f.shown { labels[row] = f.listing.entries[i].name }
	// (the details: each row as wide as their columns at least)
	least: f32 = 0
	if !names_only { least = ui.table_min_width(&app.columns) }
	t.vl.list.no_typeahead = true   // (the letters typed go to the filter, File Pilot's: filter_field)
	rows, ok := ui.vlist("###list", &t.vl, f.ids[:], labels)
	if !ok { return }
	// (the layout is the panels' together; each tab keeps its own sideways scroll)
	defer if !names_only {
		app.columns.scroll_x = t.scroll_x
		ui.table_scroll_sync(&app.columns, head, &t.vl)
		t.scroll_x = app.columns.scroll_x
	}
	if t.focus_due == .List && t.vl.key != 0 {
		ui.set_focus(t.vl.key)
		t.focus_due = .None
	}
	clicked := false
	fold := ""   // a group's title clicked: folded once the rows are built
	look := row_look(app, focused, em)
	for row in rows.first ..< rows.last {
		e := &f.listing.entries[f.shown[row]]
		selected := f.selected[f.shown[row]]
		// a group's first row: its title above it (File Pilot's Group By)
		title := ""
		if f.group != .None && f.filter == "" {
			_, key := group_of(f, e^)
			prev := ""
			if row > 0 { _, prev = group_of(f, f.listing.entries[f.shown[row - 1]]) }
			if row == 0 || key != prev { title = key }
		}
		head := title != "" ? ui.dense(em * GROUP_HEAD_EM) : 0
		folded := title != "" && title in f.folded
		// (the list's own fill of the cursor's row is clear: the row draws its pill itself; a folded group: its title alone)
		ui.next({width = least > 0 ? ui.fill_least(least) : ui.fill(), height = ui.px(folded ? head : ui.dense(em * ROW_EM) + head), radius = 0, bg = ui.Color{}})
		if selected && focused { ui.push_tags("selected") }
		sig := ui.list_row(&t.vl, row, e.name)
		// (the wheel's click on a folder's row is the row's: it opens in a tab; on a file, on the empty part it scrolls, the
		// toolkit's autoscroll)
		if sig.box != nil && e.kind == .Directory { sig.box.flags += {.Middle_Click} }
		if selected && focused { ui.pop_tags() }
		// (its neighbours selected too: one pill over them)
		sel_up := row > 0 && f.selected[f.shown[row - 1]]
		sel_down := row + 1 < len(f.shown) && f.selected[f.shown[row + 1]]
		if !folded { row_paint(sig.box, look, selected, row == f.cursor && (!selected || f.count > 1), row & 1 == 1, head, sel_up, sel_down) }
		check := false
		if ui.parent(sig.box) {
			if title != "" {
				// (the title, then the row's cells under it)
				ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
				if ui.column(.Start, {}, "###grouped") {
					// (a click on the title folds the group, or unfolds it)
					ui.next({width = ui.fill(), height = ui.px(head)})
					if ui.row(.End, {.Draw_Side_Bottom, .Clickable, .Draw_Hot_Effects}, "###group") {
						gsig := ui.signal(ui.parent_box())
						ui.spacer(ui.px(em * ROW_INSET_EM))
						ui.push_tags("weak")
						ui.next({height = ui.px(head * 0.8)})
						glyph(app, folded ? lucide.CHEVRON_RIGHT : lucide.CHEVRON_DOWN, em * 1.3)
						ui.next({width = ui.fill(), height = ui.px(head * 0.8), font_size = em * 0.9})
						ui.label(fmt.tprintf("%s###g", title))
						ui.pop_tags()
						if gsig.clicked {
							fold = strings.clone(title, context.temp_allocator)   // (after the rows: they are being built)
							clicked = true
						}
						hover_tip(gsig, folded ? "Unfold the group" : "Fold the group")
					}
					if !folded {
						ui.next({width = ui.fill(), height = ui.fill()})
						if ui.row(.Center, {}, "###cells") { check = entry_cells(app, t, e, row, selected, names_only, em) }
					}
				}
			} else {
				check = entry_cells(app, t, e, row, selected, names_only, em)
			}
		}
		if row == t.vl.sel { t.cursor_rect = sig.box.rect }
		if !app.drag_started && !app.band.active { entry_tip(app, t, e, sig) }
		// (the icon is the row's box: a click on it checks the row, the others kept; a press there selects nothing yet)
		if check && sig.clicked && !app.drag_started {
			clicked = true
			folder_pick(f, row, toggle = true)
		} else if check && sig.pressed {
			clicked = true
			f.cursor = row
		} else if app.settings.single_click && sig.clicked && sig.mods == {} {
			folder_pick(f, row)
			act_open(app)
			return
		} else if sig.pressed && selected && sig.mods == {} && f.count > 1 {
			// (a press on the selection may drag it: the row alone is picked at the click)
			clicked = true
			f.cursor = row
		} else if sig.pressed {
			clicked = true
			if .Ctrl in sig.mods && .Shift not_in sig.mods {
				// (Ctrl: the row toggled, and a drag from it goes on doing the same to the rows it passes)
				base := slice.clone(f.selected[:], context.temp_allocator)
				folder_pick(f, row, toggle = true)
				band_begin_on_row(app, t, selected, base)
			} else {
				folder_pick(f, row, extend = .Shift in sig.mods, toggle = .Ctrl in sig.mods)
			}
		}
		if sig.clicked && !check && selected && sig.mods == {} && f.count > 1 && !app.drag_started { folder_pick(f, row) }
		drag_maybe(app, t, sig)
		if e.kind == .Directory {
			dir := fs.join(t.path, e.name, context.temp_allocator)
			drop_zone(app, sig.box.rect, dir)
			if app.drop_hover == dir { drop_mark(sig.box) }
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
		if sig.double_clicked {
			folder_pick(f, row)
			act_open(app)
			return
		}
	}
	if fold != "" { folder_fold(f, fold) }
	band_update(app, t, clicked)
	// a move of the list's own keys (Up, Down, Page Up, Home, type-ahead): the cursor's row alone is selected
	if t.vl.changed && !clicked && !app.band.active && t.vl.sel >= 0 { folder_pick(f, t.vl.sel) }
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
	top:      f32,   // a group's title above the row: its pill starts below it
	// the rows above and under it selected too: one pill over them all, its border around them only (no line between)
	joined_up, joined_down: bool,
}

// The height of a group's title above its first row, in ems.
GROUP_HEAD_EM :: 2.2

row_look :: proc(app: ^App, focused: bool, em: f32) -> ^Row_Look {
	look := ui.frame_new(Row_Look)
	sel := selection_color(app)
	look^ = {
		inset = em * ROW_INSET_EM, radius = max(1, ui.scale()) * 2 * corner_k(),
		line = ui.color("border") * {1, 1, 1, 0.7},
		fill = focused ? sel : sel * {1, 1, 1, 0.35},
		edge = focused ? ui.color("accent") : ui.color("accent") * {1, 1, 1, 0.45},
		ring = ui.color("accent"),
		focused = focused,
		stripes = app.settings.alternating_rows,
		// (opaque, mixed in sRGB: a few levels off the list; a tint of the text, blended in linear light, stood out)
		stripe = draw.hex(srgb_mix(surfaces(app).list, surfaces(app).head, STRIPE_SHARE)),
	}
	return look
}

// The box `b` (a row, a card) draws its pill and its ring under what it holds.
row_paint :: proc(b: ^ui.Box, look: ^Row_Look, selected, cursor: bool, odd := false, top: f32 = 0, joined_up := false, joined_down := false) {
	d := ui.frame_new(Row_Paint)
	d^ = {look, selected, cursor && look.focused, odd, top, selected && joined_up && top == 0, selected && joined_down}
	b.custom, b.custom_user = row_draw, d
}

@(private = "file")
row_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Row_Paint)(user)
	l := d.look
	r := b.rect
	r.min.y += d.top   // (a group's title above the row: not part of its pill)
	px := max(1, ui.scale())   // (a line of one device pixel at least, at every scale)
	inner := ui.Rect{{r.min.x + l.inset, r.min.y + px}, {r.max.x - l.inset, r.max.y - px}}
	if l.stripes && d.odd { draw.rect(dc, inner, l.stripe, radius = l.radius) }
	// the line under the row; none where a selection's pill is (its border is the line there: one, not two side by side)
	if !d.selected && !d.joined_down { draw.rect(dc, {{inner.min.x, r.max.y - px}, {inner.max.x, r.max.y}}, l.line) }
	if l.card.a > 0 && !d.selected { paint_raised(dc, inner, {base = l.card, edge = l.card_edge, radii = radii_all(l.radius)}) }
	if d.selected {
		// selected rows one under another are one pill: square and open where they meet, its border around them
		pill := inner
		if d.joined_up { pill.min.y = r.min.y }
		if d.joined_down { pill.max.y = r.max.y }
		radii := radii_all(l.radius)
		if d.joined_up { radii[0], radii[2] = 0, 0 }
		if d.joined_down { radii[1], radii[3] = 0, 0 }
		draw.rect_corners(dc, pill, {l.fill, l.fill, l.fill, l.fill}, radii)
		if l.edge.a > 0 {
			// (the border drawn past the sides that meet another row, cut there: their lines are not drawn)
			ring := pill
			if d.joined_up { ring.min.y -= 2 * px }
			if d.joined_down { ring.max.y += 2 * px }
			draw.push_clip(dc, pill)
			draw.rect_corners(dc, ring, {l.edge, l.edge, l.edge, l.edge}, radii, px)
			draw.pop_clip(dc)
		}
	}
	if d.cursor { draw.rect(dc, inner, l.ring, radius = l.radius, border = px) }
}

// How much of what was cut is see-through (its icon and its text; its row's pill stays as it is).
CUT_TRANSPARENCY :: 0.5

// A row's cells (entry_row), in a box that dims them while the entry is cut.
@(private = "file")
entry_cells :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, row: int, selected: bool, names_only: bool, em: f32) -> (check: bool) {
	if !entry_is_cut(app, t, e^) { return entry_row(app, t, e, row, selected, names_only, em) }
	ui.next({width = ui.fill(), height = ui.pct(1), transparency = CUT_TRANSPARENCY})
	if ui.row(.Center, {}, "###cut") { check = entry_row(app, t, e, row, selected, names_only, em) }
	return
}

// The cells of a row: its box, its icon, its name (or the field that renames it), its date, its type, its counts and its
// size. `names_only`: the icon and the name. True: its box was clicked.
@(private = "file")
entry_row :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, row: int, selected: bool, names_only: bool, em: f32) -> (check: bool) {
	l := &app.columns
	// the name's cell: the row's edge, the tree's chevron, the icon (its box too), the name; the name's column wide
	ui.next({width = names_only ? ui.fill() : ui.table_width(l, int(Detail.Name)), height = ui.pct(1)})
	if ui.row(.Center, {}, "###name_cell") {
		ui.spacer(ui.px(em * (ROW_INSET_EM + ROW_LEAD_EM)))
		tree_lead(app, t, e, em)
		check = icon_check(app, t, e^, row, selected, em)
		ui.spacer(ui.px(em * 0.5))
		entry_name(app, t, e, selected, em)
	}
	if names_only {
		ui.spacer(ui.px(em * ROW_INSET_EM))
		return
	}
	m: Measure
	measured := false
	if e.kind == .Directory { m, measured = measure_of(app, t, e^) }
	folders, files := entry_counts_text(app, t, e^)
	if !selected { ui.push_tags("weak") }
	// (at the titles' size: the toolkit's columns are in ems of it, a smaller text made them narrower than their titles)
	{
		// (each cell under its title: the toolkit's cells, their order and widths; a number at the right)
		for k in l.order {
			if k == int(Detail.Name) || !l.shown[k] { continue }
			switch Detail(k) {
			case .Name:
			case .Modified: ui.table_cell(l, k, date_text(app, e.mtime))
			case .Type:     ui.table_cell(l, k, type_text(app, e^))
			case .Folders:  ui.table_cell(l, k, folders)
			case .Files:    ui.table_cell(l, k, files)
			case .Size:
				size := "--"
				if e.size >= 0 { size = size_text(e.size) } else if measured && m.bytes > 0 { size = size_text(m.bytes) }
				ui.table_cell(l, k, size)
				// (File Pilot's: a thin bar under the size, its share of the largest row's)
				bytes := e.size >= 0 ? e.size : (measured ? m.bytes : 0)
				if cell := ui.parent_box().last; cell != nil && size_bar_shown(bytes, t.folder.size_max) {
					d := ui.frame_new(Size_Bar)
					d^ = {f32(f64(bytes) / f64(t.folder.size_max)), ui.color("accent") * {1, 1, 1, 0.55}, em}
					cell.custom, cell.custom_user = size_bar_draw, d
				}
			}
		}
	}
	if !selected { ui.pop_tags() }
	ui.table_row_end()
	return
}

// The Folders and Files cells of an entry: empty for a file; for a folder its counts once measured, "--" until then
// (or when it is not measured: a link, the measures off).
entry_counts_text :: proc(app: ^App, t: ^Tab, e: fs.Entry) -> (folders, files: string) {
	if e.kind != .Directory { return "", "" }
	m, measured := measure_of(app, t, e)
	if !measured { return "--", "--" }
	return count_text(m.folders), count_text(m.files)
}

// The name of an entry, or the field that renames it.
entry_name :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, selected: bool, em: f32) {
	r := &app.rename
	if r.active && r.tab == t.id && r.name == e.name {
		key := ui.key_from_string(ui.parent_box().key, "###rename")
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7))})
		ui.next_merge(control_look(em))
		// Tab, Shift+Tab: the name kept, then the next row's or the previous one's in the field (Explorer's); taken before
		// the field and the toolkit, which would move the keyboard to the next field
		step := 0
		if ui.focus_key() == key {
			if ui.key_press(.Tab) { step = 1 } else if ui.key_press(.Tab, {.Shift}) { step = -1 }
		}
		if r.refused { ui.push_tags("bad") }
		res := ui.line_edit("###rename", &r.field)
		if r.refused { ui.pop_tags() }
		if res.changed { r.refused = false }
		note_text_field(app, key)
		if r.focus_due {
			ui.set_focus(key)
			r.focus_due = false
		} else if step == 0 && !res.focused && ui.focus_key() != key {
			rename_commit(app)   // (the keyboard went elsewhere: what was typed stays)
			return
		}
		if res.committed || step != 0 { rename_commit(app, step) }
		if res.cancelled { rename_end(app) }
		return
	}
	hidden := .Hidden in e.flags && !selected
	needle := t.folder.filter
	if t.folder.tree && needle == "" {
		ui.next({width = ui.fill(), height = ui.pct(1)})
		if hidden { ui.push_tags("weak") }
		ui.label(fmt.tprintf("%s###n", shown_text(fs.base(e.name))))
		if hidden { ui.pop_tags() }
		return
	}
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

// `text` (a part of what `ranges` were found in, from `offset`) in pieces: the matched ones in the theme's colours of
// what a search found ("match" on "match_bg", as the toolkit's matched_label), the text's own on the selection.
@(private = "file")
match_text :: proc(text: string, ranges: []ui.Fuzzy_Range, offset: int, selected: bool) {
	at := 0
	piece :: proc(s: string, lit, selected: bool, n: int) {
		if s == "" { return }
		flags := ui.Box_Flags{.Draw_Text, .No_Text_Trunc}
		if lit && !selected { flags += {.Draw_Background} }
		ui.next({width = ui.text_size(0), height = ui.pct(1), text_pad = 0, fg = lit && !selected ? ui.color("match") : nil, bg = ui.color("match_bg"), radius = 0})
		ui.build_box(flags, fmt.tprintf("%s###p%d", shown_text(s), n))
	}
	n := 0
	for r in ranges {
		lo, hi := r[0] - offset, r[1] - offset
		if hi <= 0 || lo >= len(text) { continue }
		lo, hi = max(lo, 0), min(hi, len(text))
		if lo > at { piece(text[at:lo], false, selected, n); n += 1 }
		piece(text[lo:hi], true, selected, n)
		n += 1
		at = hi
	}
	piece(text[at:], false, selected, n)
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
		filter_field(app, t, focused, em)
		cell_rule()
		// the cursor's item (its name, type and size) or what is selected; the job at work in its place
		if _, running := jobs_progress(app); focused && running {
			ui.spacer(ui.fill())
		} else if ui.tags("weak") {
			ui.next({width = ui.fill(), height = ui.pct(1), font_size = em * 0.92, text_pad = em * 0.6})
			ui.label(fmt.tprintf("%s###item_info", footer_info(app, t)))
		}
		if focused {
			job_status(app, em)
			failed := 0
			for job in app.jobs.list { if sync.atomic_load(&job.state) == .Failed { failed += 1 } }
			if len(app.jobs.list) > 0 {
				// (while jobs run: their progress beside the button that shows them)
				if t, running := jobs_progress(app); running {
					ui.next({width = ui.text_size(em * 0.3), height = ui.pct(1)})
					ui.label(fmt.tprintf("%d%%###jobs_pct", int(t * 100)))
				}
				if ui.tags("weak") {
					if icon_action(app, "jobs", lucide.LAYERS_2, failed > 0 ? fmt.tprintf("The jobs: %d failed (%s)", failed, command_keys(app, command_find("jobs"))) : command_tip(app, "jobs"), em, on = failed > 0) { act_jobs(app) }
				}
				if b := ui.box_from_key(ui.key_from_string(ui.parent_box().key, "###jobs")); b != nil { app.jobs_view.anchor = b.rect }
			}
		}
		cell_rule()
		ui.next({width = ui.children_sum(), height = ui.pct(1)})
		if ui.row(.Center, {}, "###stats") {
			if ui.style({font_size = em * 0.92}) {
				// (of all: the hidden ones only while they are shown, their absence is no filter)
				folders, files, folders_shown, files_shown: int
				for e in f.listing.entries {
					if !f.show_hidden && (.Hidden in e.flags || .System in e.flags) { continue }
					if e.kind == .Directory { folders += 1 } else { files += 1 }
				}
				for i in f.shown { if f.listing.entries[i].kind == .Directory { folders_shown += 1 } else { files_shown += 1 } }
				if t.walk != nil { stat(app, "walk", lucide.LOADER, fmt.tprintf("%s…", count_text(i64(tab_walked(t)))), "Entries read so far", em) }
				if f.count > 0 {
					bytes, _ := folder_selection_size(f)
					stat(app, "sel", lucide.LAYERS_2, bytes > 0 ? fmt.tprintf("%d · %s", f.count, size_text(bytes)) : fmt.tprintf("%d", f.count), "Selected, and the size of their files", em)
				}
				stat(app, "fol", lucide.FOLDER, shown_count_text(folders_shown, folders), folders_shown < folders ? "Folders shown, of all: a filter leaves some out" : "Folders", em, lit = folders_shown < folders)
				stat(app, "fil", lucide.FILE, shown_count_text(files_shown, files), files_shown < files ? "Files shown, of all: a filter leaves some out" : "Files", em, lit = files_shown < files)
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

// The corners of the zoom's bar and its slider's parts, `thick` across: the settings' rounding (`round`: corner_k()),
// square at 0, as every box; never past a half of it (a pill).
@(private = "file")
zoom_radius :: proc(thick, round: f32) -> f32 { return min(thick * 0.22 * round, thick * 0.5) }

@(private = "file")
Zoom_Draw :: struct { t: f32, fill, track: ui.Color, round: f32 }   // round: corner_k(), read in the build

@(private = "file")
zoom_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Zoom_Draw)(user)
	r := b.rect
	rad := zoom_radius(r.max.y - r.min.y, d.round)
	draw.rect(dc, r, d.track, radius = rad)
	w := max((r.max.x - r.min.x) * d.t, (r.max.y - r.min.y) * 0.3)
	draw.rect(dc, {r.min, {r.min.x + w, r.max.y}}, d.fill, radius = rad)
}

// The zoom as File Pilot shows it: its percent on a bar of the accent, moving smoothly; a click opens the vertical slider
// above it (zoom_slider_build), a right click goes to the step before.
@(private = "file")
zoom_pill :: proc(app: ^App, t: ^Tab, em: f32) {
	z := ZOOMS[clamp(t.zoom, 0, len(ZOOMS) - 1)]
	d := ui.frame_new(Zoom_Draw)
	shown := ui.anim(ui.key_from_string(0, fmt.tprintf("classeur_zoom%d", t.id)), f32(z.percent) / 100, 22)
	d^ = {shown, selection_color(app), ui.color("border"), corner_k()}
	ui.next({width = ui.px(em * 4.6), height = ui.px(em * 1.5), axis = .X, cross = .Center})
	b := ui.custom("###zoom", zoom_draw, d, {.Clickable})
	// (the view's icon, then the percent, over the bar: boxes of their own, drawn after it; the icon says it is the view,
	// not a progress)
	if ui.parent(b) {
		fg: Maybe(ui.Color) = z.percent > 40 ? draw.hex(0xffffffff) : nil
		ui.spacer(ui.fill())
		glyph(app, ZOOM_ICONS[clamp(t.zoom, 0, len(ZOOMS) - 1)], em * 1.3, fg)
		ui.next({width = ui.text_size(em * 0.15), height = ui.pct(1), fg = fg})
		ui.label(fmt.tprintf("%d%%###pct", z.percent))
		ui.spacer(ui.fill())
	}
	sig := ui.signal(b)
	if sig.clicked { zoom_slider_open(app, t, b.rect) }
	if sig.right_clicked { tab_set_zoom(app, t, max(t.zoom - 1, 0)) }
	hover_tip(sig, "The view: a click shows the slider (Ctrl+wheel, Ctrl+= and Ctrl+- too)")
}

@(private = "file")
Slider_Draw :: struct { at: f32, steps: int, step_h: f32, track, fill, tick, knob: ui.Color, round: f32 }   // round: corner_k()

// The slider's track: from the middle of the top step's row to the middle of the bottom one's, a tick at each, the
// part below the zoom in the accent, the knob where it is (moving smoothly). The track and the knob are rounded as the
// zoom's bar (zoom_radius); the ticks, a pixel thick, stay square.
@(private = "file")
slider_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Slider_Draw)(user)
	r := b.rect
	cx := (r.min.x + r.max.x) * 0.5
	w := max(3, (r.max.x - r.min.x) * 0.14)
	top, bottom := r.min.y + d.step_h * 0.5, r.max.y - d.step_h * 0.5
	draw.rect(dc, {{cx - w * 0.5, top}, {cx + w * 0.5, bottom}}, d.track, radius = zoom_radius(w, d.round))
	y := bottom - (bottom - top) * d.at
	draw.rect(dc, {{cx - w * 0.5, y}, {cx + w * 0.5, bottom}}, d.fill, radius = zoom_radius(w, d.round))
	for i in 0 ..< d.steps {
		ty := bottom - (bottom - top) * f32(i) / f32(max(d.steps - 1, 1))
		draw.rect(dc, {{cx - w * 1.6, ty - 0.5}, {cx - w, ty + 0.5}}, d.tick)
		draw.rect(dc, {{cx + w, ty - 0.5}, {cx + w * 1.6, ty + 0.5}}, d.tick)
	}
	k := w * 2.2
	draw.rect(dc, {{cx - k, y - k * 0.4}, {cx + k, y + k * 0.4}}, d.knob, radius = zoom_radius(k * 0.8, d.round))
}

// What each step of the zoom is called, and its icon.
@(rodata)
ZOOM_NAMES := [?]string{"Details", "Names", "Columns", "Small cards", "Cards", "Large cards", "Huge cards"}
@(rodata)
ZOOM_ICONS := [?]string{lucide.TABLE_2, lucide.LIST, lucide.COLUMNS_2, lucide.LAYOUT_GRID, lucide.LAYOUT_GRID, lucide.IMAGE, lucide.IMAGE}

// The slider of the zoom (a panel over the footer's percent): a row per step, from the largest at the top to the
// details at the bottom, its icon, its name and its percent; a click on a row goes to that step, the track at the left
// is dragged from step to step (the view following smoothly), the wheel and Up, Down too.
zoom_slider_open :: proc(app: ^App, t: ^Tab, at: ui.Rect) {
	if app.zoom_slider_key == 0 { app.zoom_slider_key = ui.key_from_string(0, "classeur_zoom_slider") }
	app.zoom_slider_tab = t.id
	ui.ctx_menu_open_rect(app.zoom_slider_key, at)
}

zoom_slider_build :: proc(app: ^App, em: f32) {
	if app.zoom_slider_key == 0 { return }
	w := em * 16
	if ui.ctx_menu(app.zoom_slider_key, w) {
		t := find_tab(app, app.zoom_slider_tab)
		if t == nil { ui.ctx_menu_close(); return }
		n := len(ZOOMS)
		step_h := ui.dense(em * 2.2)
		ui.next({width = ui.px(w), height = ui.px(step_h * f32(n))})
		if ui.row(.Start, {}, "###zoom_steps") {
			d := ui.frame_new(Slider_Draw)
			d^ = {ui.anim(ui.key_from_string(0, "classeur_slider_at"), f32(t.zoom) / f32(n - 1), 22), n, step_h, ui.color("border"), selection_color(app), ui.color("weak text"), ui.color("text"), corner_k()}
			ui.next({width = ui.px(em * 2.6), height = ui.pct(1)})
			b := ui.custom("###slider", slider_draw, d, {.Clickable})
			sig := ui.signal(b)
			if sig.pressed || sig.dragging {
				top, bottom := b.rect.min.y + step_h * 0.5, b.rect.max.y - step_h * 0.5
				f := clamp((bottom - ui.mouse_pos().y) / max(bottom - top, 1), 0, 1)
				step := int(f * f32(n - 1) + 0.5)
				if step != t.zoom { tab_set_zoom(app, t, step) }
			}
			if sig.scrolled.y != 0 { tab_set_zoom(app, t, t.zoom + (sig.scrolled.y < 0 ? 1 : -1)) }
			// the steps, the largest at the top
			ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
			if ui.column(.Start, {}, "###zoom_names") {
				for k in 0 ..< n {
					step := n - 1 - k
					on := step == t.zoom
					if on { ui.push_tags("selected") }
					ui.next({width = ui.fill(), height = ui.px(step_h), radius = 0})
					flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects}
					if on { flags += {.Draw_Background} }
					rsig: ui.Signal
					if ui.row(.Center, flags, fmt.tprintf("###zstep%d", step)) {
						rsig = ui.signal(ui.parent_box())
						if !on { ui.push_tags("weak") }
						glyph(app, ZOOM_ICONS[step], em * 1.7)
						if !on { ui.pop_tags() }
						ui.spacer(ui.px(em * 0.3))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label(fmt.tprintf("%s###zn", ZOOM_NAMES[step]))
						ui.push_tags("weak")
						ui.next({width = ui.text_size(em * 0.5), height = ui.pct(1), font_size = em * 0.85})
						ui.label(fmt.tprintf("%d%%###zp", ZOOMS[step].percent))
						ui.pop_tags()
					}
					if on { ui.pop_tags() }
					if rsig.clicked { tab_set_zoom(app, t, step) }
				}
			}
		}
		if ui.key_press(.Up) { tab_set_zoom(app, t, t.zoom + 1) }
		if ui.key_press(.Down) { tab_set_zoom(app, t, t.zoom - 1) }
	}
}

// A count of the footer: its number alone ("7"), or "3/7" when a filter leaves rows out.
shown_count_text :: proc(shown, all: int) -> string {
	if shown >= all { return count_text(i64(all)) }
	return fmt.tprintf("%d/%s", shown, count_text(i64(all)))
}

// What the footer says at its left: the cursor's item (its name, its type, its size). Nothing when several rows are
// selected: the selection's count at the right says how many and their size.
footer_info :: proc(app: ^App, t: ^Tab) -> string {
	f := &t.folder
	if f.count > 1 { return "" }
	e := folder_cursor_entry(f)
	if e == nil { return "" }
	name := shown_text(fs.base(shown_name(app, e^)))
	if e.size < 0 { return fmt.tprintf("%s · %s", name, type_text(app, e^)) }   // (a folder not measured)
	return fmt.tprintf("%s · %s · %s", name, type_text(app, e^), size_text(e.size))
}

// A count of the footer: its icon and its number, its meaning in its tooltip. `lit`: in the accent (a filter leaves
// rows out).
@(private = "file")
stat :: proc(app: ^App, id, icon, text, tip: string, em: f32, lit := false) {
	ui.next({width = ui.children_sum(), height = ui.pct(1)})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable}, fmt.tprintf("###stat_%s", id)) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, icon, em * 1.5) }
		ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1), fg = lit ? ui.color("accent") : nil})
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
filter_field :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	// (a well, the whole height of the footer: darker than it; a line of the accent along its top while it searches
	// every folder below)
	ui.next({width = ui.px(em * FILTER_EM), height = ui.pct(1), bg = draw.hex(surfaces(app).top)})
	if ui.row(.Center, {.Draw_Background}, "###filterbox") {
		if t.flat { tab_flat_line(ui.parent_box()) }
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.5) }
		key := ui.key_from_string(ui.parent_box().key, "###filter")
		// text typed in the panel that has the keyboard, no field and no dialog taking it: into its filter (File
		// Pilot's); Space is the inspector's, not a letter
		if focused && app.no_dialog && !ui.key_pressed_peek(.Space) && !ui.ctx_menu_any_open() && ui.type_to_field(key) {
			t.filter_open = true
		}
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###filter", &t.filter, "Filter...", clearable = !t.flat) }
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
			if icon_action(app, "types", lucide.FILTER, "The types shown: files, folders, extensions", em, on = folder_types_filtered(&t.folder)) {
				types_menu_open(app, t)
			}
			if icon_action(app, "flat", lucide.FOLDER_TREE, command_tip(app, "flat"), em, on = t.flat) {
				t.flat = !t.flat
				tab_load(app, t)
				t.focus_due = .Filter
			}
			// (the field's own cross empties it; this one leaves the search of every folder below, its letters with it)
			if t.flat {
				if icon_action(app, "filter_clear", lucide.X, "Clear the filter, leave the search (Escape)", em) {
					ui.field_clear(&t.filter)
					if t.flat { t.flat = false; tab_load(app, t) }
				}
			}
		}
		ui.spacer(ui.px(em * 0.2))
	}
}

// The crumbs of a tab's path; under the home folder they start at it, named "Home".
home_crumbs :: proc(app: ^App, t: ^Tab) -> []fs.Crumb {
	parts := fs.crumbs(t.path)
	// (under a share: from its root, named by its URI, "smb://nas/docs"; both read with the folder, on the worker)
	if t.share_root != "" {
		for c, i in parts {
			if c.path != t.share_root { continue }
			out := parts[i:]
			out[0].name = t.share_uri
			return out
		}
	}
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

// A ring of the accent around the box a drop would go into, in the box's own corners (a crumb's, a tab's).
drop_mark :: proc(b: ^ui.Box) {
	prev, prev_user := b.custom, b.custom_user
	// (the radius worked out in the build: the drawing has no state of the toolkit to ask)
	Mark :: struct { prev: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context), user: rawptr, radius, width: f32, color: ui.Color }
	m := ui.frame_new(Mark)
	m^ = {prev, prev_user, ui.box_drawn_radius(ui.current_state(), b), max(2, ui.scale() * 2), ui.color("accent")}
	b.custom = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		m := (^Mark)(user)
		if m.prev != nil { m.prev(b, m.user, dc) }
		draw.rect(dc, b.rect, m.color, radius = m.radius, border = m.width)
	}
	b.custom_user = m
}

// What a row says when the pointer rests on it: its whole name (cut short in the row), its type, size and date; in the
// search of every folder below, the folder it is in.
entry_tip :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, sig: ui.Signal) {
	if !ui.hovered_for(sig, 0.8) { return }
	name := fs.base(e.name)
	where_ := ""
	if t.folder.flat && fs.parent(e.name) != "" { where_ = fmt.tprintf("In %s", home_path(app, fs.join(t.path, fs.parent(e.name), context.temp_allocator))) }
	facts := e.kind == .Directory ? fmt.tprintf("%s · %s", type_text(app, e^), date_text(app, e.mtime)) : fmt.tprintf("%s · %s · %s", type_text(app, e^), size_text(e.size), date_text(app, e.mtime))
	hover_tip(sig, name, facts, where_)
}


// The tree's lead of a row or a line, before its icon: a step in per level, a chevron that opens or closes a folder in
// place. Nothing outside the tree, or while filtering.
tree_lead :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, em: f32) {
	if !t.folder.tree || t.folder.filter != "" { return }
	ui.spacer(ui.px(em * 1.4 * f32(tree_depth(e.name))))
	if e.kind == .Directory {
		open := tab_tree_is_open(t, e.name)
		if ui.tags("weak") {
			if icon_action(app, fmt.tprintf("tree_%s", e.name), open ? lucide.CHEVRON_DOWN : lucide.CHEVRON_RIGHT, open ? "Close it here (Left)" : "Open it here (Right)", em * 0.8) {
				tab_tree_toggle(app, t, strings.clone(e.name, context.temp_allocator))
			}
		}
	} else {
		ui.spacer(ui.px(em * TREE_CHEVRON_EM))
	}
}
