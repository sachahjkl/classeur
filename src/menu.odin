package classeur

// The menu of the list: a right click on a row (or the Menu key, Shift+F10) gives what can be done with the selection;
// a right click on the empty part of the list gives what can be done in the folder. Every item is a command: its keys
// are shown beside it.

import "core:fmt"
import "gt:ui"

MENU_WIDTH_EM :: 17

Entry_Menu :: struct {
	key:      ui.Key,
	tab:      u64,
	on_entry: bool,   // opened on a row (else on the folder)
}

entry_menu_open :: proc(app: ^App, t: ^Tab, pos: ui.Vec2, from_keyboard := false, on_entry := true) {
	m := &app.menu
	if m.key == 0 { m.key = ui.key_from_string(0, "classeur_entry_menu") }
	m.tab, m.on_entry = t.id, on_entry
	ui.ctx_menu_open(m.key, pos, from_keyboard = from_keyboard)
}

// An item that runs a command, with its first key.
menu_command :: proc(app: ^App, id: string, enabled := true, checked := false) {
	c := command_find(id)
	if c == nil { return }
	if ui.menu_item(c.title, shortcut_text(c.keys[0]), checked = checked, icon = "", enabled = enabled).clicked { c.run(app) }
}

entry_menu_build :: proc(app: ^App, em: f32) {
	m := &app.menu
	if m.key == 0 { return }
	if !ui.ctx_menu(m.key, em * MENU_WIDTH_EM) { return }
	t := find_tab(app, m.tab)
	if t == nil { ui.ctx_menu_close(); return }
	if m.on_entry {
		e := folder_cursor_entry(&t.folder)
		folder := e != nil && e.kind == .Directory
		menu_command(app, "open")
		menu_command(app, "open_new_tab", enabled = folder)
		menu_command(app, "open_other_panel", enabled = folder)
		menu_command(app, "open_system")
		ui.menu_separator()
		menu_command(app, "rename", enabled = t.folder.count <= 1)
		menu_command(app, "copy_path")
		ui.menu_separator()
	}
	menu_command(app, "new_folder")
	menu_command(app, "select_all")
	menu_command(app, "refresh")
	ui.menu_separator()
	if ui.menu_submenu("Sort by") {
		s := t.folder.sort
		menu_command(app, "sort_name", checked = s.key == .Name)
		menu_command(app, "sort_modified", checked = s.key == .Modified)
		menu_command(app, "sort_size", checked = s.key == .Size)
		menu_command(app, "sort_type", checked = s.key == .Type)
		ui.menu_separator()
		menu_command(app, "folders_mixed", checked = !s.mixed)
	}
	menu_command(app, "hidden", checked = app.show_hidden)
}

////////////////////////////////
// The panel's menus: the history (the chevron of the toolbar) and the panel's own (its "...")

Panel_Menus :: struct {
	history_key: ui.Key,
	history_tab: u64,
	panel_key:   ui.Key,
}

history_menu_open :: proc(app: ^App, t: ^Tab, at: ui.Rect) {
	m := &app.panel_menus
	if m.history_key == 0 { m.history_key = ui.key_from_string(0, "classeur_history_menu") }
	m.history_tab = t.id
	ui.ctx_menu_open(m.history_key, ui.mouse_pos())
}

panel_menu_open :: proc(app: ^App, pos: ui.Vec2) {
	m := &app.panel_menus
	if m.panel_key == 0 { m.panel_key = ui.key_from_string(0, "classeur_panel_menu") }
	ui.ctx_menu_open(m.panel_key, pos)
}

panel_menus_build :: proc(app: ^App, em: f32) {
	history_menu_build(app, em)
	panel_menu_build(app, em)
}

@(private = "file")
history_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.history_key == 0 { return }
	if ui.ctx_menu(m.history_key, em * MENU_WIDTH_EM) {
		t := find_tab(app, m.history_tab)
		if t == nil { ui.ctx_menu_close(); return }
		// the last folder first
		#reverse for p, i in t.back {
			if ui.menu_item(fmt.tprintf("%s###h%d", shown_text(home_path(app, p)), i)).clicked {
				for len(t.back) > i + 1 { tab_back_quiet(t) }
				tab_back(app, t)
			}
		}
	}
}

@(private = "file")
panel_menu_build :: proc(app: ^App, em: f32) {
	m := &app.panel_menus
	if m.panel_key == 0 { return }
	if ui.ctx_menu(m.panel_key, em * MENU_WIDTH_EM) {
		t := current_tab(app)
		if t == nil { ui.ctx_menu_close(); return }
		menu_command(app, "new_folder")
		menu_command(app, "refresh")
		menu_command(app, "goto")
		ui.menu_separator()
		if ui.menu_submenu("Sort by") {
			s := t.folder.sort
			menu_command(app, "sort_name", checked = s.key == .Name)
			menu_command(app, "sort_modified", checked = s.key == .Modified)
			menu_command(app, "sort_size", checked = s.key == .Size)
			menu_command(app, "sort_type", checked = s.key == .Type)
			ui.menu_separator()
			menu_command(app, "folders_mixed", checked = !s.mixed)
		}
		menu_command(app, "hidden", checked = app.show_hidden)
		ui.menu_separator()
		menu_command(app, "panel_split")
		menu_command(app, "panel_close", enabled = len(app.panels) > 1)
	}
}
