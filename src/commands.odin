package classeur

// Every action of the program is a command of this table: its name, its icon, its keys. The keyboard runs them
// (commands_keys), the command palette lists and runs them (palette.odin), the menus show their keys. A new action is a
// line here and a procedure in actions.odin.

import "gt:i18n"
import lucide "gt:lucide"
import "gt:ui"

// A key and its modifiers: the toolkit's (its names, ui.chord_text, ui.key_name).
Shortcut :: ui.Chord

Command :: struct {
	id:      string,
	title:   string,
	icon:    string,
	tags:    []string,   // words the palette finds it by that its title does not say (a short title keeps its old words here)
	keys:    []Shortcut,   // its chords, any number (the first is the one shown)
	in_text: bool,   // its keys work while a text field has the keyboard (they have Ctrl or Alt, or are function keys)
	run:     proc(app: ^App),
	enabled: proc(app: ^App) -> bool,   // nil: always; else, when it says false, its keys do nothing and the palette hides it
}

// (not rodata: i18n.later marks the titles for the catalogue, a call the compiler does not fold)
COMMANDS := [?]Command{
	{id = "open", title = i18n.later("Open"), icon = lucide.FOLDER_OPEN, keys = {{.Return, {}}}, run = act_open},
	{id = "open_new_tab", title = i18n.later("Open in new tab"), icon = lucide.LAYERS_2, keys = {{.Return, {.Ctrl}}}, run = act_open_new_tab},
	{id = "open_other_panel", title = i18n.later("Open in other panel"), icon = lucide.SEND_HORIZONAL, keys = {{.Return, {.Shift}}}, run = act_open_other_panel},
	{id = "up", title = i18n.later("Go up"), icon = lucide.ARROW_UP, tags = {"parent folder"}, keys = {{.Backspace, {}}, {.Up, {.Alt}}}, run = act_up},
	{id = "back", title = i18n.later("Go back"), icon = lucide.ARROW_LEFT, keys = {{.Left, {.Alt}}}, in_text = true, run = act_back},
	{id = "forward", title = i18n.later("Go forward"), icon = lucide.ARROW_RIGHT, keys = {{.Right, {.Alt}}}, in_text = true, run = act_forward},
	{id = "home", title = i18n.later("Go home"), icon = lucide.HOME, tags = {"home folder"}, keys = {{.Home, {.Alt}}}, in_text = true, run = act_home},
	{id = "refresh", title = i18n.later("Refresh"), icon = lucide.REFRESH_CW, keys = {{.F5, {}}, {.R, {.Ctrl}}}, in_text = true, run = act_refresh},
	{id = "goto_popup", title = i18n.later("Go to folder"), icon = lucide.FOLDER_SEARCH, tags = {"goto", "path", "few letters"}, keys = {{.G, {.Ctrl}}}, in_text = true, run = act_goto_popup},
	{id = "goto", title = i18n.later("Type the path"), icon = lucide.TEXT_CURSOR_INPUT, tags = {"address", "location"}, keys = {{.L, {.Ctrl}}, {.D, {.Alt}}}, in_text = true, run = act_goto},
	{id = "filter", title = i18n.later("Filter this folder"), icon = lucide.FILTER, keys = {{.F, {.Ctrl}}}, in_text = true, run = act_filter},
	{id = "flat", title = i18n.later("Search subfolders"), icon = lucide.SEARCH, tags = {"every folder below", "flatten"}, keys = {{.F, {.Ctrl, .Shift}}}, in_text = true, run = act_flat},
	{id = "options", title = i18n.later("Settings"), icon = lucide.SETTINGS, tags = {"options", "preferences"}, keys = {{.Comma, {.Ctrl}}}, in_text = true, run = act_options},
	{id = "inspector", title = i18n.later("Inspector"), icon = lucide.INFO, tags = {"what the cursor is on", "beside the list", "preview"}, keys = {{.Space, {}}, {.I, {.Ctrl, .Shift}}}, run = act_inspector},
	{id = "palette", title = i18n.later("Command palette"), icon = lucide.COMMAND, keys = {{.K, {.Ctrl}}, {.P, {.Ctrl, .Shift}}}, in_text = true, run = act_palette},
	{id = "shortcuts", title = i18n.later("Keyboard shortcuts"), icon = lucide.KEYBOARD, tags = {"keys", "help"}, keys = {{.F1, {}}}, in_text = true, run = act_shortcuts},

	{id = "tab_new", title = i18n.later("New tab"), icon = lucide.PLUS, keys = {{.T, {.Ctrl}}}, in_text = true, run = act_tab_new},
	{id = "tab_close", title = i18n.later("Close tab"), icon = lucide.X, keys = {{.W, {.Ctrl}}}, in_text = true, run = act_tab_close},
	{id = "tab_reopen", title = i18n.later("Reopen closed tab"), icon = lucide.ROTATE_CCW, tags = {"open again"}, keys = {{.T, {.Ctrl, .Shift}}}, in_text = true, run = act_tab_reopen},
	{id = "tab_next", title = i18n.later("Next tab"), icon = lucide.CHEVRON_RIGHT, keys = {{.Tab, {.Ctrl}}, {.Page_Down, {.Ctrl}}}, in_text = true, run = act_tab_next},
	{id = "tab_previous", title = i18n.later("Previous tab"), icon = lucide.CHEVRON_LEFT, keys = {{.Tab, {.Ctrl, .Shift}}, {.Page_Up, {.Ctrl}}}, in_text = true, run = act_tab_previous},
	{id = "tab_duplicate", title = i18n.later("Duplicate tab"), icon = lucide.COPY, keys = {{.K, {.Ctrl, .Shift}}}, in_text = true, run = act_tab_duplicate},
	{id = "panel_split", title = i18n.later("Split right"), icon = lucide.COLUMNS_2, tags = {"new panel at the right"}, keys = {{.D, {.Ctrl, .Shift}}}, in_text = true, run = act_panel_split},
	{id = "panel_split_below", title = i18n.later("Split down"), icon = lucide.ROWS_2, tags = {"new panel below"}, keys = {{.J, {.Ctrl, .Shift}}}, in_text = true, run = act_panel_split_below},
	{id = "panel_close", title = i18n.later("Close panel"), icon = lucide.LOG_OUT, keys = {{.W, {.Ctrl, .Shift}}}, in_text = true, run = act_panel_close},
	{id = "panel_next", title = i18n.later("Next panel"), icon = lucide.PANEL_RIGHT, tags = {"go to", "sidebar", "inspector"}, keys = {{.F6, {}}}, in_text = true, run = act_panel_next},
	{id = "panel_previous", title = i18n.later("Previous panel"), icon = lucide.PANEL_RIGHT, tags = {"go to", "sidebar", "inspector", "back"}, keys = {{.F6, {.Ctrl, .Shift}}}, in_text = true, run = act_panel_previous},

	{id = "select_all", title = i18n.later("Select all"), icon = lucide.CHECK, keys = {{.A, {.Ctrl}}}, run = act_select_all},
	{id = "select_none", title = i18n.later("Select none"), icon = lucide.SQUARE, keys = {{.A, {.Ctrl, .Shift}}}, run = act_select_none},
	{id = "select_invert", title = i18n.later("Invert selection"), icon = lucide.LIST_CHECKS, keys = {{.I, {.Ctrl}}}, run = act_select_invert},

	{id = "copy", title = i18n.later("Copy"), icon = lucide.CLIPBOARD_COPY, keys = {{.C, {.Ctrl}}}, run = act_copy},
	{id = "cut", title = i18n.later("Cut"), icon = lucide.SCISSORS, keys = {{.X, {.Ctrl}}}, run = act_cut},
	{id = "paste", title = i18n.later("Paste"), icon = lucide.CLIPBOARD_PASTE, keys = {{.V, {.Ctrl}}}, run = act_paste},
	{id = "paste_into", title = i18n.later("Paste into folder"), icon = lucide.CLIPBOARD, tags = {"at the cursor"}, keys = {{.V, {.Ctrl, .Shift}}}, run = act_paste_into},
	{id = "copy_to_other", title = i18n.later("Copy to other panel"), icon = lucide.FOLDER_OUTPUT, keys = {{.F5, {.Shift}}}, run = act_copy_to_other},
	{id = "move_to_other", title = i18n.later("Move to other panel"), icon = lucide.FOLDER_INPUT, keys = {{.F6, {.Shift}}}, run = act_move_to_other},
	{id = "trash", title = i18n.later("Move to trash"), icon = lucide.TRASH_2, keys = {{.Delete, {}}}, run = act_trash},
	{id = "delete", title = i18n.later("Delete permanently"), icon = lucide.ALERT_TRIANGLE, tags = {"for good"}, keys = {{.Delete, {.Shift}}}, run = act_delete},
	{id = "put_back", title = i18n.later("Put back"), icon = lucide.ARCHIVE_RESTORE, tags = {"restore", "items of the trash", "where they came from"}, keys = {{.R, {.Ctrl, .Alt}}}, run = act_put_back},
	{id = "empty_trash", title = i18n.later("Empty trash"), icon = lucide.ARCHIVE, keys = {{.Delete, {.Ctrl, .Shift}}}, run = act_empty_trash},
	{id = "undo", title = i18n.later("Undo"), icon = lucide.UNDO_2, tags = {"last change to files"}, keys = {{.Z, {.Ctrl}}}, run = act_undo},
	{id = "redo", title = i18n.later("Redo"), icon = lucide.REDO_2, tags = {"do again what was undone"}, keys = {{.Y, {.Ctrl}}, {.Z, {.Ctrl, .Shift}}}, run = act_redo},
	{id = "jobs", title = i18n.later("Jobs"), icon = lucide.LOADER, tags = {"every copy move and trash", "what failed", "retry"}, keys = {{.J, {.Ctrl, .Alt}}}, in_text = true, run = act_jobs},
	{id = "jobs_cancel", title = i18n.later("Cancel jobs"), icon = lucide.X, tags = {"copies and moves"}, keys = {{.X, {.Ctrl, .Alt}}}, in_text = true, run = act_jobs_cancel},
	{id = "rename", title = i18n.later("Rename"), icon = lucide.PENCIL, keys = {{.F2, {}}}, run = act_rename},
	{id = "new_folder", title = i18n.later("New folder"), icon = lucide.FOLDER_PLUS, keys = {{.N, {.Ctrl, .Shift}}}, in_text = true, run = act_new_folder},
	{id = "new_file", title = i18n.later("New file"), icon = lucide.FILE_PLUS, keys = {{.N, {.Ctrl, .Alt}}}, in_text = true, run = act_new_file},
	{id = "terminal", title = i18n.later("Open terminal here"), icon = lucide.SQUARE_TERMINAL, keys = {{.F4, {}}}, in_text = true, run = act_terminal},
	{id = "terminal_in", title = i18n.later("Open terminal in folder"), icon = lucide.TERMINAL, tags = {"at the cursor"}, keys = {{.F4, {.Shift}}}, run = act_terminal_in},
	{id = "side_up", title = i18n.later("Move section up"), icon = lucide.CHEVRON_UP, tags = {"sidebar"}, keys = {{.Up, {.Ctrl, .Alt, .Shift}}}, run = act_side_up},
	{id = "side_down", title = i18n.later("Move section down"), icon = lucide.CHEVRON_DOWN, tags = {"sidebar"}, keys = {{.Down, {.Ctrl, .Alt, .Shift}}}, run = act_side_down},
	{id = "network_find", title = i18n.later("Find network devices"), icon = lucide.NETWORK, tags = {"network devices nas smb share discover scan"}, keys = {{.F5, {.Ctrl, .Shift}}}, in_text = true, run = act_network_find},
	{id = "tab_window", title = i18n.later("Move tab to window"), icon = lucide.APP_WINDOW, tags = {"of its own"}, keys = {{.N, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_tab_window},
	{id = "tab_close_others", title = i18n.later("Close other tabs"), icon = lucide.PIN, keys = {{.W, {.Ctrl, .Alt}}}, in_text = true, run = act_tab_close_others},
	{id = "tab_close_left", title = i18n.later("Close tabs to left"), icon = lucide.X, keys = {{.Page_Up, {.Ctrl, .Alt}}}, in_text = true, run = act_tab_close_left},
	{id = "tab_close_right", title = i18n.later("Close tabs to right"), icon = lucide.X, keys = {{.Page_Down, {.Ctrl, .Alt}}}, in_text = true, run = act_tab_close_right},
	{id = "copy_path", title = i18n.later("Copy path"), icon = lucide.LINK, keys = {{.C, {.Ctrl, .Shift}}}, run = act_copy_path},
	{id = "open_system", title = i18n.later("Open with default app"), icon = lucide.EXTERNAL_LINK, tags = {"system's application"}, keys = {{.Return, {.Alt}}}, run = act_open_system},

	{id = "bookmark", title = i18n.later("Bookmark this folder"), icon = lucide.BOOKMARK, tags = {"remove its bookmark"}, keys = {{.D, {.Ctrl}}}, in_text = true, run = act_bookmark},
	{id = "bookmark_folder", title = i18n.later("Bookmark folder at cursor"), icon = lucide.STAR, tags = {"remove its bookmark"}, keys = {{.B, {.Ctrl, .Shift}}}, run = act_bookmark_folder},
	{id = "recents_clear", title = i18n.later("Clear recents"), icon = lucide.HISTORY, keys = {{.H, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_recents_clear},
	{id = "lock", title = i18n.later("Lock tab"), icon = lucide.LOCK, tags = {"folders open in a new tab"}, keys = {{.L, {.Ctrl, .Shift}}}, in_text = true, run = act_lock},
	{id = "hidden", title = i18n.later("Hidden files"), icon = lucide.EYE, tags = {"show or hide"}, keys = {{.H, {.Ctrl}}, {.Period, {.Ctrl}}}, in_text = true, run = act_toggle_hidden},
	{id = "sidebar", title = i18n.later("Sidebar"), icon = lucide.PANEL_LEFT, tags = {"show or hide"}, keys = {{.B, {.Ctrl}}}, in_text = true, run = act_toggle_sidebar},
	{id = "view_details", title = i18n.later("Details view"), icon = lucide.LAYOUT_LIST, keys = {{.N1, {.Ctrl}}}, in_text = true, run = act_view_details},
	{id = "view_grid", title = i18n.later("Grid view"), icon = lucide.LAYOUT_GRID, tags = {"thumbnails"}, keys = {{.N2, {.Ctrl}}}, in_text = true, run = act_view_grid},
	{id = "zoom_in", title = i18n.later("Zoom in"), icon = lucide.ZOOM_IN, tags = {"next view", "larger items"}, keys = {{.Equal, {.Ctrl}}, {.Num_Add, {.Ctrl}}}, in_text = true, run = act_zoom_in},
	{id = "zoom_out", title = i18n.later("Zoom out"), icon = lucide.ZOOM_OUT, tags = {"previous view", "smaller items"}, keys = {{.Minus, {.Ctrl}}, {.Num_Subtract, {.Ctrl}}}, in_text = true, run = act_zoom_out},
	{id = "sort_name", title = i18n.later("Sort by name"), icon = lucide.ARROW_UP_DOWN, keys = {{.N1, {.Ctrl, .Alt}}}, in_text = true, run = act_sort_name},
	{id = "sort_modified", title = i18n.later("Sort by date modified"), icon = lucide.CALENDAR_CLOCK, keys = {{.N2, {.Ctrl, .Alt}}}, in_text = true, run = act_sort_modified},
	{id = "sort_size", title = i18n.later("Sort by size"), icon = lucide.GAUGE, keys = {{.N3, {.Ctrl, .Alt}}}, in_text = true, run = act_sort_size},
	{id = "sort_type", title = i18n.later("Sort by type"), icon = lucide.FILE_TEXT, keys = {{.N4, {.Ctrl, .Alt}}}, in_text = true, run = act_sort_type},
	{id = "folders_mixed", title = i18n.later("Folders first"), icon = lucide.FOLDER_TREE, tags = {"or among the files"}, keys = {{.N0, {.Ctrl, .Alt}}}, in_text = true, run = act_folders_mixed},
	{id = "layout_save", title = i18n.later("Save layout"), icon = lucide.SAVE, tags = {"panels and tabs"}, keys = {{.S, {.Ctrl, .Alt}}}, in_text = true, run = act_layout_save},
	{id = "layout_open", title = i18n.later("Open layout"), icon = lucide.BLOCKS, keys = {{.L, {.Ctrl, .Alt}}}, in_text = true, run = act_layout_open},
	{id = "tree", title = i18n.later("Tree view"), icon = lucide.LIST_TREE, tags = {"folders opened in place"}, keys = {{.E, {.Ctrl, .Shift}}}, in_text = true, run = act_tree},
	{id = "group_date", title = i18n.later("Group by date"), icon = lucide.SUN_MOON, tags = {"again no groups"}, keys = {{.N5, {.Ctrl, .Alt}}}, in_text = true, run = act_group_date},
	{id = "group_type", title = i18n.later("Group by type"), icon = lucide.FILE_BOX, tags = {"again no groups"}, keys = {{.N6, {.Ctrl, .Alt}}}, in_text = true, run = act_group_type},
	{id = "group_size", title = i18n.later("Group by size"), icon = lucide.DATABASE, tags = {"again no groups"}, keys = {{.N7, {.Ctrl, .Alt}}}, in_text = true, run = act_group_size},
	{id = "view_list", title = i18n.later("Names view"), icon = lucide.LIST, keys = {{.N3, {.Ctrl}}}, in_text = true, run = act_view_list},
	{id = "view_columns", title = i18n.later("Names in columns"), icon = lucide.TABLE_2, keys = {{.N4, {.Ctrl}}}, in_text = true, run = act_view_columns},
	{id = "types", title = i18n.later("Types shown"), icon = lucide.SLIDERS_HORIZONTAL, tags = {"files", "folders", "extensions"}, keys = {{.Y, {.Ctrl, .Shift}}}, in_text = true, run = act_types},
	{id = "files_only", title = i18n.later("Show files only"), icon = lucide.FILE, keys = {{.F, {.Ctrl, .Alt}}}, in_text = true, run = act_files_only},
	{id = "folders_only", title = i18n.later("Show folders only"), icon = lucide.FOLDER, keys = {{.D, {.Ctrl, .Alt}}}, in_text = true, run = act_folders_only},
	{id = "every_type", title = i18n.later("Show every type"), icon = lucide.FILES, tags = {"again"}, keys = {{.A, {.Ctrl, .Alt}}}, in_text = true, run = act_every_type},
	{id = "copy_name", title = i18n.later("Copy names"), icon = lucide.TEXT_QUOTE, keys = {{.C, {.Ctrl, .Alt}}}, in_text = true, run = act_copy_name},
	{id = "open_folder", title = i18n.later("Go to its folder"), icon = lucide.CORNER_LEFT_UP, tags = {"item's own folder", "in a search"}, keys = {{.O, {.Alt}}}, in_text = true, run = act_open_folder},
	{id = "tab_1", title = i18n.later("Tab 1"), icon = lucide.HASH, keys = {{.N1, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 0) }},
	{id = "tab_2", title = i18n.later("Tab 2"), icon = lucide.HASH, keys = {{.N2, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 1) }},
	{id = "tab_3", title = i18n.later("Tab 3"), icon = lucide.HASH, keys = {{.N3, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 2) }},
	{id = "tab_4", title = i18n.later("Tab 4"), icon = lucide.HASH, keys = {{.N4, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 3) }},
	{id = "tab_5", title = i18n.later("Tab 5"), icon = lucide.HASH, keys = {{.N5, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 4) }},
	{id = "tab_6", title = i18n.later("Tab 6"), icon = lucide.HASH, keys = {{.N6, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 5) }},
	{id = "tab_7", title = i18n.later("Tab 7"), icon = lucide.HASH, keys = {{.N7, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 6) }},
	{id = "tab_8", title = i18n.later("Tab 8"), icon = lucide.HASH, keys = {{.N8, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, 7) }},
	{id = "tab_last", title = i18n.later("Last tab"), icon = lucide.HASH, keys = {{.N9, {.Alt}}}, in_text = true, run = proc(app: ^App) { tab_pick(app, -1) }},

	// The program itself (program_actions.odin): the palette's Program group
	{id = "app_quit", title = i18n.later("Quit"), icon = lucide.POWER, tags = {"exit", "close", "leave"}, keys = {{.Q, {.Ctrl}}}, in_text = true, run = act_app_quit},
	{id = "app_restart", title = i18n.later("Restart classeur"), icon = lucide.ZAP, tags = {"relaunch", "reload", "reboot", "start again"}, keys = {{.Q, {.Ctrl, .Shift}}}, in_text = true, run = act_app_restart, enabled = can_restart},
	{id = "app_new_window", title = i18n.later("New window"), icon = lucide.APP_WINDOW, tags = {"another window", "open"}, keys = {{.N, {.Ctrl}}}, in_text = true, run = act_app_new_window},
	{id = "app_minimize", title = i18n.later("Minimize window"), icon = lucide.ARROW_DOWN, tags = {"hide", "iconify", "taskbar"}, keys = {{.F9, {.Alt}}}, in_text = true, run = act_app_minimize},
	{id = "app_maximize", title = i18n.later("Maximize window"), icon = lucide.MONITOR, tags = {"restore", "whole screen", "zoom window"}, keys = {{.F10, {.Alt}}}, in_text = true, run = act_app_maximize},
	{id = "app_full_screen", title = i18n.later("Full screen"), icon = lucide.FILM, tags = {"fullscreen", "kiosk", "whole screen"}, keys = {{.F11, {}}}, in_text = true, run = act_app_full_screen},
	{id = "app_update_check", title = i18n.later("Check for updates"), icon = lucide.DOWNLOAD, tags = {"upgrade", "new version", "release"}, keys = {{.U, {.Ctrl, .Alt}}}, in_text = true, run = act_app_update_check, enabled = has_updater},
	{id = "app_update_install", title = i18n.later("Install the update"), icon = lucide.HARD_DRIVE_DOWNLOAD, tags = {"upgrade", "download", "new version"}, keys = {{.U, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_update_install, enabled = update_available},
	{id = "app_update_restart", title = i18n.later("Restart to update"), icon = lucide.FILE_DOWN, tags = {"relaunch", "upgrade", "new version"}, keys = {{.Q, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_restart, enabled = update_installed},
	{id = "app_about", title = i18n.later("About classeur"), icon = lucide.LIGHTBULB, tags = {"version", "credits", "info"}, keys = {{.F1, {.Shift}}}, in_text = true, run = act_app_about},
	{id = "app_website", title = i18n.later("Open the website"), icon = lucide.GLOBE, tags = {"site", "home page", "web"}, keys = {{.F1, {.Ctrl}}}, in_text = true, run = act_app_website},
	{id = "app_report", title = i18n.later("Report a problem"), icon = lucide.BUG, tags = {"bug", "issue", "feedback", "help"}, keys = {{.F1, {.Ctrl, .Shift}}}, in_text = true, run = act_app_report},
	{id = "app_changelog", title = i18n.later("Release notes"), icon = lucide.SCROLL_TEXT, tags = {"changelog", "what is new", "changes", "releases"}, keys = {{.F2, {.Shift}}}, in_text = true, run = act_app_changelog},
	{id = "app_settings_folder", title = i18n.later("Open settings folder"), icon = lucide.WRENCH, tags = {"configuration", "config", "preferences file", "session"}, keys = {{.Comma, {.Ctrl, .Shift}}}, in_text = true, run = act_app_settings_folder},
	{id = "app_version_copy", title = i18n.later("Copy the version"), icon = lucide.CODE, tags = {"about", "number", "clipboard"}, keys = {{.V, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_version_copy},
	{id = "app_theme_next", title = i18n.later("Next theme"), icon = lucide.PALETTE, tags = {"color", "colour", "dark", "light", "look"}, keys = {{.Period, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_theme_next},
	{id = "app_theme_previous", title = i18n.later("Previous theme"), icon = lucide.PALETTE, tags = {"color", "colour", "dark", "light", "look"}, keys = {{.Comma, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_theme_previous},
	{id = "app_density", title = i18n.later("Compact rows"), icon = lucide.MENU, tags = {"density", "comfortable", "spacing"}, keys = {{.D, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_density},
	{id = "app_animations", title = i18n.later("Animations"), icon = lucide.PLAY, tags = {"motion", "transitions", "on or off"}, keys = {{.A, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_animations},
	{id = "app_text_bigger", title = i18n.later("Larger text"), icon = lucide.TYPE, tags = {"font size", "bigger", "interface", "scale"}, keys = {{.Equal, {.Ctrl, .Alt}}}, in_text = true, run = act_app_text_bigger},
	{id = "app_text_smaller", title = i18n.later("Smaller text"), icon = lucide.TYPE, tags = {"font size", "interface", "scale"}, keys = {{.Minus, {.Ctrl, .Alt}}}, in_text = true, run = act_app_text_smaller},
	{id = "app_text_reset", title = i18n.later("Default text size"), icon = lucide.TYPE, tags = {"font size", "reset", "interface", "scale"}, keys = {{.N0, {.Ctrl}}}, in_text = true, run = act_app_text_reset},
	{id = "app_reload_all", title = i18n.later("Reload all folders"), icon = lucide.REFRESH_CW, tags = {"refresh every tab", "read again"}, keys = {{.F5, {.Ctrl}}}, in_text = true, run = act_app_reload_all},
	{id = "app_layout_reset", title = i18n.later("Reset the layout"), icon = lucide.PANEL_BOTTOM, tags = {"one panel", "close all tabs", "start over"}, keys = {{.L, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_layout_reset},
	{id = "app_thumbs_clear", title = i18n.later("Clear thumbnails"), icon = lucide.IMAGE, tags = {"pictures", "cache", "previews"}, keys = {{.I, {.Ctrl, .Shift, .Alt}}}, in_text = true, run = act_app_thumbs_clear},
}

// The keys of the commands, before the interface sees them. `typing`: a text field has the keyboard, and only the
// commands marked `in_text` run.
commands_keys :: proc(app: ^App, typing: bool) {
	// (a sequence's first chord waits for its second a moment: SEQUENCE_MS)
	if app.keymap.pending.key != .None && ui.now_ms() > app.keymap.pending_until { app.keymap.pending = {} }
	for &c in COMMANDS {
		if typing && !c.in_text { continue }
		if c.enabled != nil && !c.enabled(app) { continue }
		if bindings_pressed(app, &c) { c.run(app) }
	}
}

command_find :: proc(id: string) -> ^Command {
	for &c in COMMANDS { if c.id == id { return &c } }
	return nil
}

