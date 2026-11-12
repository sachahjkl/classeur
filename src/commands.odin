package classeur

// Every action of the program is a command of this table: its name, its icon, its keys. The keyboard runs them
// (commands_keys), the command palette lists and runs them (palette.odin), the menus show their keys. A new action is a
// line here and a procedure in actions.odin.

import lucide "gt:lucide"
import "gt:ui"

// A key and its modifiers: the toolkit's (its names, ui.chord_text, ui.key_name).
Shortcut :: ui.Chord

Command :: struct {
	id:      string,
	title:   string,
	icon:    string,
	tags:    []string,   // words the palette finds it by that its title does not say (a short title keeps its old words here)
	keys:    [2]Shortcut,
	in_text: bool,   // its keys work while a text field has the keyboard (they have Ctrl or Alt, or are function keys)
	run:     proc(app: ^App),
}

@(rodata)
COMMANDS := [?]Command{
	{id = "open", title = "Open", icon = lucide.FOLDER_OPEN, keys = {{.Return, {}}, {}}, run = act_open},
	{id = "open_new_tab", title = "Open in new tab", icon = lucide.LAYERS_2, keys = {{.Return, {.Ctrl}}, {}}, run = act_open_new_tab},
	{id = "open_other_panel", title = "Open in other panel", icon = lucide.SEND_HORIZONTAL, keys = {{.Return, {.Shift}}, {}}, run = act_open_other_panel},
	{id = "up", title = "Go up", icon = lucide.ARROW_UP, tags = {"parent folder"}, keys = {{.Backspace, {}}, {.Up, {.Alt}}}, run = act_up},
	{id = "back", title = "Go back", icon = lucide.ARROW_LEFT, keys = {{.Left, {.Alt}}, {}}, in_text = true, run = act_back},
	{id = "forward", title = "Go forward", icon = lucide.ARROW_RIGHT, keys = {{.Right, {.Alt}}, {}}, in_text = true, run = act_forward},
	{id = "home", title = "Go home", icon = lucide.HOME, tags = {"home folder"}, keys = {{.Home, {.Alt}}, {}}, in_text = true, run = act_home},
	{id = "refresh", title = "Refresh", icon = lucide.REFRESH_CW, keys = {{.F5, {}}, {.R, {.Ctrl}}}, in_text = true, run = act_refresh},
	{id = "goto_popup", title = "Go to folder", icon = lucide.FOLDER_SEARCH, tags = {"goto", "path", "few letters"}, keys = {{.G, {.Ctrl}}, {}}, in_text = true, run = act_goto_popup},
	{id = "goto", title = "Type the path", icon = lucide.TEXT_CURSOR_INPUT, tags = {"address", "location"}, keys = {{.L, {.Ctrl}}, {.D, {.Alt}}}, in_text = true, run = act_goto},
	{id = "filter", title = "Filter this folder", icon = lucide.FILTER, keys = {{.F, {.Ctrl}}, {}}, in_text = true, run = act_filter},
	{id = "flat", title = "Search subfolders", icon = lucide.SEARCH, tags = {"every folder below", "flatten"}, keys = {{.F, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_flat},
	{id = "options", title = "Settings", icon = lucide.SETTINGS, tags = {"options", "preferences"}, keys = {{.Comma, {.Ctrl}}, {}}, in_text = true, run = act_options},
	{id = "inspector", title = "Inspector", icon = lucide.INFO, tags = {"what the cursor is on", "beside the list", "preview"}, keys = {{.Space, {}}, {.I, {.Ctrl, .Shift}}}, run = act_inspector},
	{id = "palette", title = "Command palette", icon = lucide.COMMAND, keys = {{.K, {.Ctrl}}, {.P, {.Ctrl, .Shift}}}, in_text = true, run = act_palette},
	{id = "shortcuts", title = "Keyboard shortcuts", icon = lucide.KEYBOARD, tags = {"keys", "help"}, keys = {{.F1, {}}, {}}, in_text = true, run = act_shortcuts},

	{id = "tab_new", title = "New tab", icon = lucide.PLUS, keys = {{.T, {.Ctrl}}, {}}, in_text = true, run = act_tab_new},
	{id = "tab_close", title = "Close tab", icon = lucide.X, keys = {{.W, {.Ctrl}}, {}}, in_text = true, run = act_tab_close},
	{id = "tab_reopen", title = "Reopen closed tab", icon = lucide.ROTATE_CCW, tags = {"open again"}, keys = {{.T, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_tab_reopen},
	{id = "tab_next", title = "Next tab", icon = lucide.CHEVRON_RIGHT, keys = {{.Tab, {.Ctrl}}, {.Page_Down, {.Ctrl}}}, in_text = true, run = act_tab_next},
	{id = "tab_previous", title = "Previous tab", icon = lucide.CHEVRON_LEFT, keys = {{.Tab, {.Ctrl, .Shift}}, {.Page_Up, {.Ctrl}}}, in_text = true, run = act_tab_previous},
	{id = "tab_duplicate", title = "Duplicate tab", icon = lucide.COPY, keys = {{.K, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_tab_duplicate},
	{id = "panel_split", title = "Split right", icon = lucide.COLUMNS_2, tags = {"new panel at the right"}, keys = {{.D, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_split},
	{id = "panel_split_below", title = "Split down", icon = lucide.ROWS_2, tags = {"new panel below"}, keys = {{.J, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_split_below},
	{id = "panel_close", title = "Close panel", icon = lucide.LOG_OUT, keys = {{.W, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_close},
	{id = "panel_next", title = "Next panel", icon = lucide.PANEL_RIGHT, tags = {"go to", "sidebar", "inspector"}, keys = {{.F6, {}}, {}}, in_text = true, run = act_panel_next},
	{id = "panel_previous", title = "Previous panel", icon = lucide.PANEL_RIGHT, tags = {"go to", "sidebar", "inspector", "back"}, keys = {{.F6, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_panel_previous},

	{id = "select_all", title = "Select all", icon = lucide.CHECK, keys = {{.A, {.Ctrl}}, {}}, run = act_select_all},
	{id = "select_none", title = "Select none", icon = lucide.SQUARE, keys = {{.A, {.Ctrl, .Shift}}, {}}, run = act_select_none},
	{id = "select_invert", title = "Invert selection", icon = lucide.LIST_CHECKS, keys = {{.I, {.Ctrl}}, {}}, run = act_select_invert},

	{id = "copy", title = "Copy", icon = lucide.CLIPBOARD_COPY, keys = {{.C, {.Ctrl}}, {}}, run = act_copy},
	{id = "cut", title = "Cut", icon = lucide.SCISSORS, keys = {{.X, {.Ctrl}}, {}}, run = act_cut},
	{id = "paste", title = "Paste", icon = lucide.CLIPBOARD_PASTE, keys = {{.V, {.Ctrl}}, {}}, run = act_paste},
	{id = "paste_into", title = "Paste into folder", icon = lucide.CLIPBOARD, tags = {"at the cursor"}, keys = {{.V, {.Ctrl, .Shift}}, {}}, run = act_paste_into},
	{id = "copy_to_other", title = "Copy to other panel", icon = lucide.FOLDER_OUTPUT, keys = {{.F5, {.Shift}}, {}}, run = act_copy_to_other},
	{id = "move_to_other", title = "Move to other panel", icon = lucide.FOLDER_INPUT, keys = {{.F6, {.Shift}}, {}}, run = act_move_to_other},
	{id = "trash", title = "Move to trash", icon = lucide.TRASH_2, keys = {{.Delete, {}}, {}}, run = act_trash},
	{id = "delete", title = "Delete permanently", icon = lucide.TRIANGLE_ALERT, tags = {"for good"}, keys = {{.Delete, {.Shift}}, {}}, run = act_delete},
	{id = "put_back", title = "Put back", icon = lucide.ARCHIVE_RESTORE, tags = {"restore", "items of the trash", "where they came from"}, keys = {{.R, {.Ctrl, .Alt}}, {}}, run = act_put_back},
	{id = "empty_trash", title = "Empty trash", icon = lucide.ARCHIVE, keys = {{.Delete, {.Ctrl, .Shift}}, {}}, run = act_empty_trash},
	{id = "undo", title = "Undo", icon = lucide.UNDO_2, tags = {"last change to files"}, keys = {{.Z, {.Ctrl}}, {}}, run = act_undo},
	{id = "redo", title = "Redo", icon = lucide.REDO_2, tags = {"do again what was undone"}, keys = {{.Y, {.Ctrl}}, {.Z, {.Ctrl, .Shift}}}, run = act_redo},
	{id = "jobs", title = "Jobs", icon = lucide.LOADER, tags = {"every copy move and trash", "what failed", "retry"}, keys = {{.J, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_jobs},
	{id = "jobs_cancel", title = "Cancel jobs", icon = lucide.X, tags = {"copies and moves"}, keys = {{.X, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_jobs_cancel},
	{id = "rename", title = "Rename", icon = lucide.PENCIL, keys = {{.F2, {}}, {}}, run = act_rename},
	{id = "new_folder", title = "New folder", icon = lucide.FOLDER_PLUS, keys = {{.N, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_new_folder},
	{id = "new_file", title = "New file", icon = lucide.FILE_PLUS, keys = {{.N, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_new_file},
	{id = "terminal", title = "Open terminal here", icon = lucide.SQUARE_TERMINAL, keys = {{.F4, {}}, {}}, in_text = true, run = act_terminal},
	{id = "terminal_in", title = "Open terminal in folder", icon = lucide.TERMINAL, tags = {"at the cursor"}, keys = {{.F4, {.Shift}}, {}}, run = act_terminal_in},
	{id = "side_up", title = "Move section up", icon = lucide.CHEVRON_UP, tags = {"sidebar"}, keys = {{.Up, {.Ctrl, .Alt, .Shift}}, {}}, run = act_side_up},
	{id = "side_down", title = "Move section down", icon = lucide.CHEVRON_DOWN, tags = {"sidebar"}, keys = {{.Down, {.Ctrl, .Alt, .Shift}}, {}}, run = act_side_down},
	{id = "tab_window", title = "Move tab to window", icon = lucide.APP_WINDOW, tags = {"of its own"}, keys = {{.N, {.Ctrl, .Shift, .Alt}}, {}}, in_text = true, run = act_tab_window},
	{id = "tab_close_others", title = "Close other tabs", icon = lucide.PIN, keys = {{.W, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_tab_close_others},
	{id = "tab_close_left", title = "Close tabs to left", icon = lucide.X, keys = {{.Page_Up, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_tab_close_left},
	{id = "tab_close_right", title = "Close tabs to right", icon = lucide.X, keys = {{.Page_Down, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_tab_close_right},
	{id = "copy_path", title = "Copy path", icon = lucide.LINK, keys = {{.C, {.Ctrl, .Shift}}, {}}, run = act_copy_path},
	{id = "open_system", title = "Open with default app", icon = lucide.EXTERNAL_LINK, tags = {"system's application"}, keys = {{.Return, {.Alt}}, {}}, run = act_open_system},

	{id = "bookmark", title = "Bookmark this folder", icon = lucide.BOOKMARK, tags = {"remove its bookmark"}, keys = {{.D, {.Ctrl}}, {}}, in_text = true, run = act_bookmark},
	{id = "bookmark_folder", title = "Bookmark folder at cursor", icon = lucide.STAR, tags = {"remove its bookmark"}, keys = {{.B, {.Ctrl, .Shift}}, {}}, run = act_bookmark_folder},
	{id = "recents_clear", title = "Clear recents", icon = lucide.HISTORY, keys = {{.H, {.Ctrl, .Shift, .Alt}}, {}}, in_text = true, run = act_recents_clear},
	{id = "lock", title = "Lock tab", icon = lucide.LOCK, tags = {"folders open in a new tab"}, keys = {{.L, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_lock},
	{id = "hidden", title = "Hidden files", icon = lucide.EYE, tags = {"show or hide"}, keys = {{.H, {.Ctrl}}, {.Period, {.Ctrl}}}, in_text = true, run = act_toggle_hidden},
	{id = "sidebar", title = "Sidebar", icon = lucide.PANEL_LEFT, tags = {"show or hide"}, keys = {{.B, {.Ctrl}}, {}}, in_text = true, run = act_toggle_sidebar},
	{id = "view_details", title = "Details view", icon = lucide.LAYOUT_LIST, keys = {{.N1, {.Ctrl}}, {}}, in_text = true, run = act_view_details},
	{id = "view_grid", title = "Grid view", icon = lucide.LAYOUT_GRID, tags = {"thumbnails"}, keys = {{.N2, {.Ctrl}}, {}}, in_text = true, run = act_view_grid},
	{id = "zoom_in", title = "Zoom in", icon = lucide.ZOOM_IN, tags = {"next view", "larger items"}, keys = {{.Equal, {.Ctrl}}, {.Num_Add, {.Ctrl}}}, in_text = true, run = act_zoom_in},
	{id = "zoom_out", title = "Zoom out", icon = lucide.ZOOM_OUT, tags = {"previous view", "smaller items"}, keys = {{.Minus, {.Ctrl}}, {.Num_Subtract, {.Ctrl}}}, in_text = true, run = act_zoom_out},
	{id = "sort_name", title = "Sort by name", icon = lucide.ARROW_UP_DOWN, keys = {{.N1, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_sort_name},
	{id = "sort_modified", title = "Sort by date modified", icon = lucide.CALENDAR_CLOCK, keys = {{.N2, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_sort_modified},
	{id = "sort_size", title = "Sort by size", icon = lucide.GAUGE, keys = {{.N3, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_sort_size},
	{id = "sort_type", title = "Sort by type", icon = lucide.FILE_TEXT, keys = {{.N4, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_sort_type},
	{id = "folders_mixed", title = "Folders first", icon = lucide.FOLDER_TREE, tags = {"or among the files"}, keys = {{.N0, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_folders_mixed},
	{id = "setup", title = "Setup", icon = lucide.PACKAGE, tags = {"install classeur", "repair", "upgrade", "uninstall"}, keys = {{.F12, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_setup},
	{id = "layout_save", title = "Save layout", icon = lucide.SAVE, tags = {"panels and tabs"}, keys = {{.S, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_layout_save},
	{id = "layout_open", title = "Open layout", icon = lucide.BLOCKS, keys = {{.L, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_layout_open},
	{id = "tree", title = "Tree view", icon = lucide.LIST_TREE, tags = {"folders opened in place"}, keys = {{.E, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_tree},
	{id = "group_date", title = "Group by date", icon = lucide.SUN_MOON, tags = {"again no groups"}, keys = {{.N5, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_group_date},
	{id = "group_type", title = "Group by type", icon = lucide.FILE_BOX, tags = {"again no groups"}, keys = {{.N6, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_group_type},
	{id = "group_size", title = "Group by size", icon = lucide.DATABASE, tags = {"again no groups"}, keys = {{.N7, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_group_size},
	{id = "view_list", title = "Names view", icon = lucide.LIST, keys = {{.N3, {.Ctrl}}, {}}, in_text = true, run = act_view_list},
	{id = "view_columns", title = "Names in columns", icon = lucide.TABLE_2, keys = {{.N4, {.Ctrl}}, {}}, in_text = true, run = act_view_columns},
	{id = "types", title = "Types shown", icon = lucide.SLIDERS_HORIZONTAL, tags = {"files", "folders", "extensions"}, keys = {{.Y, {.Ctrl, .Shift}}, {}}, in_text = true, run = act_types},
	{id = "files_only", title = "Show files only", icon = lucide.FILE, keys = {{.F, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_files_only},
	{id = "folders_only", title = "Show folders only", icon = lucide.FOLDER, keys = {{.D, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_folders_only},
	{id = "every_type", title = "Show every type", icon = lucide.FILES, tags = {"again"}, keys = {{.A, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_every_type},
	{id = "copy_name", title = "Copy names", icon = lucide.TEXT_QUOTE, keys = {{.C, {.Ctrl, .Alt}}, {}}, in_text = true, run = act_copy_name},
	{id = "open_folder", title = "Go to its folder", icon = lucide.CORNER_LEFT_UP, tags = {"item's own folder", "in a search"}, keys = {{.O, {.Alt}}, {}}, in_text = true, run = act_open_folder},
	{id = "tab_1", title = "Tab 1", icon = lucide.HASH, keys = {{.N1, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 0) }},
	{id = "tab_2", title = "Tab 2", icon = lucide.HASH, keys = {{.N2, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 1) }},
	{id = "tab_3", title = "Tab 3", icon = lucide.HASH, keys = {{.N3, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 2) }},
	{id = "tab_4", title = "Tab 4", icon = lucide.HASH, keys = {{.N4, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 3) }},
	{id = "tab_5", title = "Tab 5", icon = lucide.HASH, keys = {{.N5, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 4) }},
	{id = "tab_6", title = "Tab 6", icon = lucide.HASH, keys = {{.N6, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 5) }},
	{id = "tab_7", title = "Tab 7", icon = lucide.HASH, keys = {{.N7, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 6) }},
	{id = "tab_8", title = "Tab 8", icon = lucide.HASH, keys = {{.N8, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 7) }},
	{id = "tab_last", title = "Last tab", icon = lucide.HASH, keys = {{.N9, {.Alt}}, {}}, in_text = true, run = proc(app: ^App) { tab_pick(app, -1) }},
}

// The keys of the commands, before the interface sees them. `typing`: a text field has the keyboard, and only the
// commands marked `in_text` run.
commands_keys :: proc(app: ^App, typing: bool) {
	// (a sequence's first chord waits for its second a moment: SEQUENCE_MS)
	if app.keymap.pending.key != .None && ui.now_ms() > app.keymap.pending_until { app.keymap.pending = {} }
	for &c in COMMANDS {
		if typing && !c.in_text { continue }
		if bindings_pressed(app, &c) { c.run(app) }
	}
}

command_find :: proc(id: string) -> ^Command {
	for &c in COMMANDS { if c.id == id { return &c } }
	return nil
}

