package classeur

// Layouts (File Pilot's): the panels and their tabs saved by name, opened again in place of the ones shown. Ctrl+Alt+S
// names the one shown; Ctrl+Alt+L lists them in a menu searched by typing (a submenu deletes one). Kept in
// <config>/classeur/layouts, a block per layout: a line `layout <name>`, then the session's panel lines (session.odin's
// panels_text). The tests keep theirs beside their session file.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import lucide "gt:lucide"
import "gt:platform"
import store "gt:store"
import "gt:ui"

Layout :: struct {
	name, text: string,   // owned
}

Layouts :: struct {
	list:      [dynamic]Layout,
	naming:    bool,           // the field that names the layout shown is open
	field:     ui.Text_Field,
	menu_key:  ui.Key,
}

layouts_free :: proc(l: ^Layouts) {
	for x in l.list { delete(x.name); delete(x.text) }
	delete(l.list)
	ui.field_destroy(&l.field)
	l^ = {}
}

layouts_file :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".layouts"}, context.temp_allocator) }
	if app.headless { return "" }
	return strings.concatenate({platform.user_dir(.Config, APP_NAME, context.temp_allocator), "/layouts"}, context.temp_allocator)
}

// Read once, on this thread: at the start, before the window is shown and the first frame (the changes are written on a
// worker: layouts_save).
layouts_load :: proc(app: ^App) {
	l := &app.layouts
	path := layouts_file(app)
	if path == "" { return }
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil { return }
	text := string(data)
	name := ""
	b := strings.builder_make(context.temp_allocator)
	flush :: proc(l: ^Layouts, name: string, b: ^strings.Builder) {
		if name != "" { append(&l.list, Layout{strings.clone(name), strings.clone(strings.to_string(b^))}) }
		strings.builder_reset(b)
	}
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "layout ") {
			flush(l, name, &b)
			name = strings.clone(line[len("layout "):], context.temp_allocator)
			continue
		}
		if line != "" { fmt.sbprintf(&b, "%s\n", line) }
	}
	flush(l, name, &b)
}

@(private = "file")
layouts_save :: proc(app: ^App) {
	b := strings.builder_make(context.temp_allocator)
	for x in app.layouts.list { fmt.sbprintf(&b, "layout %s\n%s", x.name, x.text) }
	store.writer_put(&app.layouts_writer, transmute([]u8)strings.to_string(b))
}

// Saves the panels shown as the layout `name` (a layout of that name is replaced).
layout_save :: proc(app: ^App, name: string) {
	l := &app.layouts
	b := strings.builder_make(context.temp_allocator)
	panels_text(app, &b)
	for &x in l.list {
		if x.name == name {
			delete(x.text)
			x.text = strings.clone(strings.to_string(b))
			layouts_save(app)
			announce(app, .Good, "Layout %s saved again.", name)
			return
		}
	}
	append(&l.list, Layout{strings.clone(name), strings.clone(strings.to_string(b))})
	slice.sort_by(l.list[:], proc(a, b: Layout) -> bool { return a.name < b.name })
	layouts_save(app)
	announce(app, .Good, "Layout %s saved.", name)
}

// Opens the layout `name` in place of the panels shown.
layout_open :: proc(app: ^App, name: string) -> bool {
	for x in app.layouts.list {
		if x.name != name { continue }
		text := strings.clone(x.text, context.temp_allocator)
		for p in app.panels { panel_destroy(p) }
		clear(&app.panels)
		if !panels_open(app, text) {
			first := new(Panel)
			append(&app.panels, first)
			tab_open(app, first, app.home)
		}
		return true
	}
	return false
}

layout_delete :: proc(app: ^App, name: string) {
	l := &app.layouts
	for x, i in l.list {
		if x.name != name { continue }
		delete(x.name)
		delete(x.text)
		ordered_remove(&l.list, i)
		layouts_save(app)
		announce(app, .Good, "Layout %s deleted.", name)
		return
	}
}

act_layout_save :: proc(app: ^App) {
	l := &app.layouts
	l.naming = true
	ui.field_set(&l.field, fmt.tprintf("Layout %d", len(l.list) + 1))
	ui.field_select_all(&l.field)
}

act_layout_open :: proc(app: ^App) {
	l := &app.layouts
	if len(l.list) == 0 {
		say(app, "No layout is saved: Ctrl+Alt+S saves the panels shown.")
		return
	}
	if l.menu_key == 0 { l.menu_key = ui.key_from_string(0, "classeur_layouts_menu") }
	em := ui.font_size()
	at := [2]f32{app.room * ui.scale() * 0.5 - em * MENU_WIDTH_EM * 0.5, em * 6}
	ui.ctx_menu_open(l.menu_key, at, from_keyboard = true, search = true)
}

layouts_build :: proc(app: ^App, em: f32) {
	l := &app.layouts
	if l.menu_key == 0 { l.menu_key = ui.key_from_string(0, "classeur_layouts_menu") }
	if ui.ctx_menu(l.menu_key, em * MENU_WIDTH_EM) {
		open := ""
		for x, i in l.list {
			if ui.menu_item(fmt.tprintf("%s###lay%d", ui.text_shown(x.name), i), icon = lucide.LAYOUT_GRID).clicked { open = x.name }
		}
		ui.menu_separator()
		if ui.menu_submenu("Delete a layout") {
			for x, i in l.list {
				if ui.menu_item(fmt.tprintf("%s###del%d", ui.text_shown(x.name), i)).clicked { layout_delete(app, strings.clone(x.name, context.temp_allocator)) }
			}
		}
		if open != "" { layout_open(app, strings.clone(open, context.temp_allocator)) }
	}
	if !l.naming { return }
	// (Enter in the field saves; an empty name saves nothing and keeps the question open)
	answer := ui.prompt("layout_name", &l.naming, &l.field, {
		title = "Save the panels shown as a layout",
		note = "Its name: Ctrl+Alt+L lists the layouts to open one again in place of the panels.",
		placeholder = "The layout's name", act = "Save",
	})
	if answer == .Confirmed {
		name := strings.trim_space(ui.field_string(&l.field))
		if name == "" { l.naming = true } else { layout_save(app, strings.clone(name, context.temp_allocator)) }
	}
}
