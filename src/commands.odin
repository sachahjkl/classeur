package classeur

// Every action of the program is a command of this table: its name, its icon, its keys. The keyboard runs them
// (commands_keys), the command palette lists and runs them (palette.odin), the menus show their keys. A new action is a
// line here and a procedure in actions.odin.

import "core:strings"
import lucide "gt:lucide"
import "gt:platform"
import "gt:ui"

Shortcut :: struct {
	key:  platform.Key,
	mods: platform.Modifiers,
}

Command :: struct {
	id:      string,
	title:   string,
	icon:    string,
	keys:    [2]Shortcut,
	in_text: bool,   // its keys work while a text field has the keyboard (they have Ctrl or Alt, or are function keys)
	run:     proc(app: ^App),
}

@(rodata)
COMMANDS := [?]Command{
	{id = "open", title = "Open", icon = lucide.FOLDER_OPEN, keys = {{.Return, {}}, {}}, run = act_open},
	{id = "open_new_tab", title = "Open in a new tab", icon = lucide.PLUS, keys = {{.Return, {.Ctrl}}, {}}, run = act_open_new_tab},
	{id = "open_other_panel", title = "Open in the other panel", icon = lucide.COLUMNS_2, keys = {{.Return, {.Shift}}, {}}, run = act_open_other_panel},
	{id = "up", title = "Go up to the parent folder", icon = lucide.ARROW_UP, keys = {{.Backspace, {}}, {.Up, {.Alt}}}, run = act_up},
	{id = "back", title = "Go back", icon = lucide.ARROW_LEFT, keys = {{.Left, {.Alt}}, {}}, in_text = true, run = act_back},
	{id = "forward", title = "Go forward", icon = lucide.ARROW_RIGHT, keys = {{.Right, {.Alt}}, {}}, in_text = true, run = act_forward},
	{id = "home", title = "Go to the home folder", icon = lucide.HOME, keys = {{.Home, {.Alt}}, {}}, in_text = true, run = act_home},
	{id = "refresh", title = "Refresh", icon = lucide.REFRESH_CW, keys = {{.F5, {}}, {.R, {.Ctrl}}}, in_text = true, run = act_refresh},
	{id = "goto_popup", title = "GoTo: a folder by its path or a few letters", icon = lucide.FOLDER_SEARCH, keys = {{.G, {.Ctrl}}, {}}, in_text = true, run = act_goto_popup},
	{id = "goto", title = "Type the path", icon = lucide.TEXT_CURSOR_INPUT, keys = {{.L, {.Ctrl}}, {.D, {.Alt}}}, in_text = true, run = act_goto},
	{id = "filter", title = "Filter this folder", icon = lucide.FILTER, keys = {{.F, {.Ctrl}}, {}}, in_text = true, run = act_filter},
	{id = "flat", title = "Search every folder below (flatten)", icon = lucide.FOLDER_TREE, keys = {{.F, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_flat},
	{id = "options", title = "Options", icon = lucide.SETTINGS, keys = {{.Comma, {.Ctrl}}, {}}, in_text = true, run = act_options},
	{id = "inspector", title = "Inspector: what the cursor is on, beside the list", icon = lucide.EYE, keys = {{.Space, {}}, {.I, {.Ctrl, .Shift}}}, run = act_inspector},
	{id = "palette", title = "Command palette", icon = lucide.COMMAND, keys = {{.P, {.Ctrl, .Shift}}, {.F1, {}}}, in_text = true, run = act_palette},

	{id = "tab_new", title = "New tab", icon = lucide.PLUS, keys = {{.T, {.Ctrl}}, {}}, in_text = true, run = act_tab_new},
	{id = "tab_close", title = "Close the tab", icon = lucide.X, keys = {{.W, {.Ctrl}}, {}}, in_text = true, run = act_tab_close},
	{id = "tab_reopen", title = "Open the closed tab again", icon = lucide.ROTATE_CCW, keys = {{.T, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_tab_reopen},
	{id = "tab_next", title = "Next tab", icon = lucide.CHEVRON_RIGHT, keys = {{.Tab, {.Ctrl}}, {.Page_Down, {.Ctrl}}}, in_text = true, run = act_tab_next},
	{id = "tab_previous", title = "Previous tab", icon = lucide.CHEVRON_LEFT, keys = {{.Tab, {.Ctrl, .Shift}}, {.Page_Up, {.Ctrl}}}, in_text = true, run = act_tab_previous},
	{id = "tab_duplicate", title = "Duplicate the tab", icon = lucide.COPY, keys = {{.K, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_tab_duplicate},
	{id = "panel_split", title = "Split: a new panel at the right", icon = lucide.COLUMNS_2, keys = {{.D, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_split},
	{id = "panel_close", title = "Close the panel", icon = lucide.X, keys = {{.W, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_close},
	{id = "panel_next", title = "Go to the next panel", icon = lucide.COLUMNS_2, keys = {{.F6, {}}, {}}, in_text = true, run = act_panel_next},

	{id = "select_all", title = "Select all", icon = lucide.CHECK, keys = {{.A, {.Ctrl}}, {}}, run = act_select_all},
	{id = "select_none", title = "Select none", icon = lucide.SQUARE, keys = {{.A, {.Ctrl, .Shift}}, {}}, run = act_select_none},
	{id = "select_invert", title = "Invert the selection", icon = lucide.ARROW_UP_DOWN, keys = {{.I, {.Ctrl}}, {}}, run = act_select_invert},

	{id = "copy", title = "Copy", icon = lucide.COPY, keys = {{.C, {.Ctrl}}, {}}, run = act_copy},
	{id = "cut", title = "Cut", icon = lucide.SCISSORS, keys = {{.X, {.Ctrl}}, {}}, run = act_cut},
	{id = "paste", title = "Paste", icon = lucide.CLIPBOARD_PASTE, keys = {{.V, {.Ctrl}}, {}}, run = act_paste},
	{id = "copy_to_other", title = "Copy to the other panel", icon = lucide.FOLDER_OUTPUT, run = act_copy_to_other},
	{id = "move_to_other", title = "Move to the other panel", icon = lucide.FOLDER_INPUT, run = act_move_to_other},
	{id = "trash", title = "Move to the trash", icon = lucide.TRASH_2, keys = {{.Delete, {}}, {}}, run = act_trash},
	{id = "delete", title = "Delete for good", icon = lucide.TRASH_2, keys = {{.Delete, {.Shift}}, {}}, run = act_delete},
	{id = "undo", title = "Undo the last change to files", icon = lucide.UNDO_2, keys = {{.Z, {.Ctrl}}, {}}, run = act_undo},
	{id = "jobs_cancel", title = "Cancel the copies and moves", icon = lucide.X, run = act_jobs_cancel},
	{id = "rename", title = "Rename", icon = lucide.PENCIL, keys = {{.F2, {}}, {}}, run = act_rename},
	{id = "new_folder", title = "New folder", icon = lucide.FOLDER_PLUS, keys = {{.N, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_new_folder},
	{id = "copy_path", title = "Copy the path", icon = lucide.CLIPBOARD, keys = {{.C, {.Ctrl, .Shift}}, {}}, run = act_copy_path},
	{id = "open_system", title = "Open with the system's application", icon = lucide.EXTERNAL_LINK, keys = {{.Return, {.Alt}}, {}}, run = act_open_system},

	{id = "bookmark", title = "Bookmark this folder, or remove its bookmark", icon = lucide.BOOKMARK, keys = {{.D, {.Ctrl}}, {}}, in_text = true, run = act_bookmark},
	{id = "lock", title = "Lock the tab (folders open in a new tab)", icon = lucide.LOCK, run = act_lock},
	{id = "hidden", title = "Show or hide the hidden files", icon = lucide.EYE, keys = {{.H, {.Ctrl}}, {.Period, {.Ctrl}}}, in_text = true, run = act_toggle_hidden},
	{id = "sidebar", title = "Show or hide the sidebar", icon = lucide.PANEL_LEFT, keys = {{.B, {.Ctrl}}, {}}, in_text = true, run = act_toggle_sidebar},
	{id = "view_details", title = "Details view", icon = lucide.LIST, keys = {{.N1, {.Ctrl}}, {}}, in_text = true, run = act_view_details},
	{id = "view_grid", title = "Grid view, with thumbnails", icon = lucide.LAYOUT_GRID, keys = {{.N2, {.Ctrl}}, {}}, in_text = true, run = act_view_grid},
	{id = "zoom_in", title = "Zoom in: the next view, larger items", icon = lucide.PLUS, keys = {{.Equal, {.Ctrl}}, {.Num_Add, {.Ctrl}}}, in_text = true, run = act_zoom_in},
	{id = "zoom_out", title = "Zoom out: the previous view, smaller items", icon = lucide.X, keys = {{.Minus, {.Ctrl}}, {.Num_Subtract, {.Ctrl}}}, in_text = true, run = act_zoom_out},
	{id = "sort_name", title = "Sort by name", icon = lucide.ARROW_UP_DOWN, run = act_sort_name},
	{id = "sort_modified", title = "Sort by date modified", icon = lucide.ARROW_UP_DOWN, run = act_sort_modified},
	{id = "sort_size", title = "Sort by size", icon = lucide.ARROW_UP_DOWN, run = act_sort_size},
	{id = "sort_type", title = "Sort by type", icon = lucide.ARROW_UP_DOWN, run = act_sort_type},
	{id = "folders_mixed", title = "Folders first, or among the files", icon = lucide.FOLDER, run = act_folders_mixed},
}

// The keys of the commands, before the interface sees them. `typing`: a text field has the keyboard, and only the
// commands marked `in_text` run.
commands_keys :: proc(app: ^App, typing: bool) {
	for &c in COMMANDS {
		if typing && !c.in_text { continue }
		for k in c.keys {
			if k.key == .None { continue }
			if ui.key_press(k.key, k.mods) {
				c.run(app)
				break
			}
		}
	}
}

command_find :: proc(id: string) -> ^Command {
	for &c in COMMANDS { if c.id == id { return &c } }
	return nil
}

// "Ctrl+Shift+P".
shortcut_text :: proc(s: Shortcut, allocator := context.temp_allocator) -> string {
	if s.key == .None { return "" }
	b := strings.builder_make(allocator)
	if .Ctrl in s.mods { strings.write_string(&b, "Ctrl+") }
	if .Alt in s.mods { strings.write_string(&b, "Alt+") }
	if .Shift in s.mods { strings.write_string(&b, "Shift+") }
	strings.write_string(&b, key_name(s.key))
	return strings.to_string(b)
}

// The names of platform.Key, in its order (from None to Equal).
@(private = "file", rodata)
KEY_NAMES := [?]string{
	"", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
	"Esc", "Enter", "Tab", "Space", "Backspace", "Delete", "Insert",
	"Left", "Right", "Up", "Down", "Home", "End", "PgUp", "PgDn",
	",", ".", "/", "-", "=",
}

@(private = "file")
key_name :: proc(k: platform.Key) -> string {
	i := int(k)
	return i < len(KEY_NAMES) ? KEY_NAMES[i] : "?"
}
