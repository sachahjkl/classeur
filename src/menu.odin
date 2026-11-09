package classeur

// The menu of the list: a right click on a row (or the Menu key, Shift+F10) gives what can be done with the selection;
// a right click on the empty part of the list gives what can be done in the folder. Every item is a command: its keys
// are shown beside it.

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
@(private = "file")
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
