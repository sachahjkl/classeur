package classeur

// A panel: its tabs, a toolbar (back, forward, up, the crumbs of the path or the path typed, the filter), the columns'
// header, the list of the folder (only the rows in view are built: a folder of any size costs the same per frame), and
// its footer.

import "core:fmt"
import "core:slice"
import "core:strings"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

// Heights in ems.
TABS_EM    :: 2.3
TOOLBAR_EM :: 2.5
HEADER_EM  :: 1.9
ROW_EM     :: 1.85
// The widths of the columns after the name, in ems.
COL_MODIFIED_EM :: 9.5
COL_TYPE_EM     :: 6.5
COL_SIZE_EM     :: 6.0
// A tab's most width, in ems.
TAB_MAX_EM :: 14

panel_build :: proc(app: ^App, p: ^Panel, index: int, em: f32) {
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
		tab_strip(app, p, index, focused, em)
		t := panel_tab(p)
		if t == nil { return }
		toolbar(app, t, em)
		ui.hline(ui.fill())
		header(app, t, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		folder_list(app, t, focused, em)
		footer(app, t, em)
	}
}

////////////////////////////////
// Tabs

@(private = "file")
tab_strip :: proc(app: ^App, p: ^Panel, index: int, focused: bool, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TABS_EM))})
	if ui.row(.Center, id = "###tabs") {
		ui.spacer(ui.px(em * 0.3))
		close := -1
		for t, i in p.tabs {
			on := i == p.active
			ui.next({width = ui.children_sum(), height = ui.px(ui.dense(em * 1.85)), radius = em * 0.45})
			flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
			if on { flags += {.Draw_Background} }
			if on { ui.push_tags(focused ? "selected" : "weak_selected") }
			sig: ui.Signal
			if ui.row(.Center, flags, fmt.tprintf("###tab%d", t.id)) {
				sig = ui.signal(ui.parent_box())
				ui.spacer(ui.px(em * 0.5))
				glyph(app, t.loading ? lucide.LOADER : lucide.FOLDER, em * 1.5, on ? ui.color("accent") : nil)
				ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1)})
				if !on { ui.push_tags("weak") }
				title := tab_title(app, t)
				title = cut_text(title, TAB_MAX_EM * 2)
				ui.label(fmt.tprintf("%s###title", shown_text(title)))
				if !on { ui.pop_tags() }
				if len(p.tabs) > 1 || len(app.panels) > 1 {
					ui.next({width = ui.px(em * 1.5), height = ui.px(em * 1.5), font = app.icons, radius = em * 0.3, font_size = em * 0.85})
					if ui.tags("ghost_button") {
						if ui.button(fmt.tprintf("%s###close", lucide.X)).clicked { close = i }
					}
				}
				ui.spacer(ui.px(em * 0.3))
			}
			if on { ui.pop_tags() }
			if sig.pressed { p.active = i; app.focus = index }
			if sig.middle_clicked { close = i }
			ui.spacer(ui.px(em * 0.2))
		}
		if icon_action(app, fmt.tprintf("newtab%d", index), lucide.PLUS, command_tip("tab_new"), em) {
			app.focus = index
			act_tab_new(app)
		}
		ui.spacer(ui.fill())
		if len(app.panels) > 1 {
			if icon_action(app, fmt.tprintf("closepanel%d", index), lucide.X, command_tip("panel_close"), em) {
				panel_close(app, p)
				return
			}
		}
		ui.spacer(ui.px(em * 0.3))
		if close >= 0 { tab_close(app, p, close) }
	}
}

////////////////////////////////
// The toolbar

@(private = "file")
toolbar :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOOLBAR_EM))})
	if ui.row(.Center, id = "###toolbar") {
		ui.spacer(ui.px(em * 0.3))
		if icon_action(app, "back", lucide.ARROW_LEFT, command_tip("back"), em, len(t.back) > 0) { tab_back(app, t) }
		if icon_action(app, "forward", lucide.ARROW_RIGHT, command_tip("forward"), em, len(t.forward) > 0) { tab_forward(app, t) }
		if icon_action(app, "up", lucide.ARROW_UP, command_tip("up"), em, fs.parent(t.path) != "") { tab_up(app, t) }
		if icon_action(app, "refresh", lucide.REFRESH_CW, command_tip("refresh"), em) { tab_load(app, t) }
		ui.spacer(ui.px(em * 0.3))
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.9)), radius = em * 0.45})
		if t.address_open {
			address_field(app, t, em)
		} else {
			crumbs(app, t, em)
		}
		ui.spacer(ui.px(em * 0.4))
		filter_field(app, t, em)
		ui.spacer(ui.px(em * 0.4))
	}
}

// The path as buttons, one per folder; a click on the empty part types the path instead.
@(private = "file")
crumbs :: proc(app: ^App, t: ^Tab, em: f32) {
	if ui.field_frame("###crumbs") {
		frame := ui.parent_box()
		frame.flags += {.Clickable, .Clip}
		parts := home_crumbs(app, t.path)
		// (a long path shows its end: the first crumbs go when the room is short)
		room := frame.size.x - em * 2
		first := 0
		widths := make([]f32, len(parts), context.temp_allocator)
		total: f32
		for c, i in parts {
			widths[i] = ui.text_width(ui.top_style().font, em, c.name) + em * 2.2
			total += widths[i]
		}
		for first < len(parts) - 1 && total > room && room > 0 {
			total -= widths[first]
			first += 1
		}
		ui.spacer(ui.px(em * 0.2))
		if first > 0 {
			if ui.tags("weak") { glyph(app, lucide.ELLIPSIS, em * 1.3) }
		}
		for c, i in parts[first:] {
			at := first + i
			if i > 0 || first > 0 {
				if ui.tags("weak") { glyph(app, lucide.CHEVRON_RIGHT, em * 1.0) }
			}
			last := at == len(parts) - 1
			ui.next({width = ui.text_size(em * 0.45), height = ui.px(ui.dense(em * 1.55)), radius = em * 0.35})
			sig: ui.Signal
			if last {
				sig = ui.button(fmt.tprintf("%s###crumb%d", shown_text(c.name), at))
			} else if ui.tags("ghost_button") {
				sig = ui.button(fmt.tprintf("%s###crumb%d", shown_text(c.name), at))
			}
			if sig.clicked && !last { tab_go(app, t, c.path) }
			if sig.middle_clicked { tab_open(app, current_panel(app), c.path, current_panel(app).active + 1) }
		}
		ui.spacer(ui.fill())
		if ui.signal(frame).clicked { act_goto(app) }
	}
}

@(private = "file")
address_field :: proc(app: ^App, t: ^Tab, em: f32) {
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
filter_field :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next({width = ui.px(em * 13), height = ui.px(ui.dense(em * 1.9)), radius = em * 0.45})
	if ui.field_frame("###filterbox") {
		if ui.tags("weak") { glyph(app, lucide.FILTER, em * 1.7) }
		key := ui.key_from_string(ui.parent_box().key, "###filter")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###filter", &t.filter, "Filter") }
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
header :: proc(app: ^App, t: ^Tab, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * HEADER_EM))})
	if ui.row(.Center, id = "###header") {
		if ui.style({font_size = em * 0.86}) {
			ui.spacer(ui.px(em * 0.4))
			column_head(app, t, .Name, "Name", ui.fill(), .Left, em)
			column_head(app, t, .Modified, "Modified", ui.px(em * COL_MODIFIED_EM), .Left, em)
			column_head(app, t, .Type, "Type", ui.px(em * COL_TYPE_EM), .Left, em)
			column_head(app, t, .Size, "Size", ui.px(em * COL_SIZE_EM), .Right, em)
			ui.spacer(ui.px(em * 0.9))
		}
	}
}

@(private = "file")
column_head :: proc(app: ^App, t: ^Tab, key: fs.Sort_Key, title: string, width: ui.Size, align: ui.Text_Align, em: f32) {
	s := t.folder.sort
	on := s.key == key
	ui.next({width = width, height = ui.pct(1), radius = em * 0.3})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects}, fmt.tprintf("###col_%s", title)) {
		sig = ui.signal(ui.parent_box())
		if align == .Right { ui.spacer(ui.fill()) }
		ui.spacer(ui.px(em * 0.4))
		if !on { ui.push_tags("weak") }
		ui.next({width = ui.text_size(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", title))
		if !on { ui.pop_tags() }
		if on { glyph(app, s.descending ? lucide.ARROW_DOWN : lucide.ARROW_UP, em * 1.2, ui.color("accent")) }
		ui.spacer(ui.px(em * 0.4))
	}
	if sig.clicked {
		folder_sort_by(&t.folder, key)
		app.default_sort = t.folder.sort
	}
}

////////////////////////////////
// The list

@(private = "file")
folder_list :: proc(app: ^App, t: ^Tab, focused: bool, em: f32) {
	f := &t.folder
	if !f.loaded || f.listing.error != .None || len(f.shown) == 0 {
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
		return
	}

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
	for row in rows.first ..< rows.last {
		e := &f.listing.entries[f.shown[row]]
		selected := f.selected[f.shown[row]]
		if selected && row != t.vl.sel { ui.push_tags(focused ? "weak_selected" : "weak_selected") }
		ui.next({height = ui.px(ui.dense(em * ROW_EM)), flags = selected && row != t.vl.sel ? {.Draw_Background} : {}})
		sig := ui.list_row(&t.vl, row, e.name)
		if selected && row != t.vl.sel { ui.pop_tags() }
		if ui.parent(sig.box) { entry_row(app, t, e, em) }
		if row == t.vl.sel { t.cursor_rect = sig.box.rect }
		if sig.pressed {
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
		if sig.double_clicked {
			folder_pick(f, row)
			act_open(app)
			return
		}
	}
	// a move of the list's own keys (Up, Down, Page Up, Home, type-ahead): the cursor's row alone is selected
	if t.vl.changed && !clicked && t.vl.sel >= 0 { folder_pick(f, t.vl.sel) }
	if t.vl.activated && !clicked { act_open(app) }
}

// The cells of a row: the icon, the name (or the field that renames it), the date, the type, the size.
@(private = "file")
entry_row :: proc(app: ^App, t: ^Tab, e: ^fs.Entry, em: f32) {
	ui.spacer(ui.px(em * 0.5))
	folder := e.kind == .Directory
	hidden := .Hidden in e.flags
	glyph(app, entry_icon(e^), em * 1.6, folder ? ui.color("accent") : nil)
	ui.spacer(ui.px(em * 0.3))
	r := &app.rename
	if r.active && r.tab == t.id && r.name == e.name {
		key := ui.key_from_string(ui.parent_box().key, "###rename")
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.55))})
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
		if hidden { ui.push_tags("weak") }
		ui.label(fmt.tprintf("%s###n", shown_text(e.name)))
		if hidden { ui.pop_tags() }
	}
	if ui.tags("weak") {
		if ui.style({font_size = em * 0.9}) {
			ui.next({width = ui.px(em * COL_MODIFIED_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###m", date_text(app, e.mtime)))
			ui.next({width = ui.px(em * COL_TYPE_EM), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###k", type_text(e^)))
			ui.next({width = ui.px(em * COL_SIZE_EM), height = ui.pct(1), text_align = .Right})
			ui.label(fmt.tprintf("%s###s", e.size >= 0 ? size_text(e.size) : ""))
		}
	}
	ui.spacer(ui.px(em * 0.9))
}

////////////////////////////////
// The footer

@(private = "file")
footer :: proc(app: ^App, t: ^Tab, em: f32) {
	f := &t.folder
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7))})
	if ui.row(.Center, id = "###footer") {
		ui.spacer(ui.px(em * 0.7))
		if ui.tags("weak") {
			if ui.style({font_size = em * 0.82}) {
				ui.next({width = ui.fill(), height = ui.pct(1)})
				text := ""
				if f.loaded && f.listing.error == .None {
					text = fmt.tprintf("%d items", len(f.shown))
					if f.count > 0 { text = fmt.tprintf("%s · %d selected", text, f.count) }
					if f.filter != "" { text = fmt.tprintf("%s · filtered", text) }
				}
				ui.label(fmt.tprintf("%s###foot", text))
				if t.has_space {
					ui.next({width = ui.text_size(em * 0.3), height = ui.pct(1)})
					ui.label(fmt.tprintf("%s free###free", size_text(t.space.free)))
				}
			}
		}
		ui.spacer(ui.px(em * 0.5))
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
