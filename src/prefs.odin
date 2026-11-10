package classeur

// The preferences: one registry (gt:config), its user file at <config>/classeur/prefs, read at the start and written at
// each change made in the options (options.odin). `settings_apply` copies the values where the program reads them.

import "core:strings"
import config "gt:config"
import "gt:platform"
import "gt:ui"

PREF_DEFS := [?]config.Def{
	{name = "look.rounding", description = "The rounding of every corner of the interface: buttons, fields, menus, dialogs, the rows' selection, the boxes (0: square).", kind = .Float, default = {f = ROUNDING}, min = 0, max = 2, bounded = true},
	{name = "look.density", description = "Compact rows and bars fit more on the screen at the same text size.", kind = .String, default = {s = "comfortable"}, choices = {"comfortable", "compact"}},
	{name = "look.animations", description = "The interface's animations: the system's setting, always, or never.", kind = .String, default = {s = "system"}, choices = {"system", "on", "off"}},
	{name = "look.smooth_scroll", description = "Scrolling glides to where the wheel or the keys send it, even when the animations are off.", kind = .Bool, default = {b = true}},
	{name = "look.autohide_scrollbars", description = "The scroll bars show only while the pointer is over what they scroll.", kind = .Bool, default = {b = false}},
	{name = "look.follow_system", description = "Follows the system's light or dark scheme as it changes; off, classeur stays dark.", kind = .Bool, default = {b = false}},
	{name = "look.theme", description = "The colours of every part of the window.", kind = .String, default = {s = "Graphite"}},
	{name = "look.alternating_rows", description = "Paints every other row a shade lighter, to tell the rows apart.", kind = .Bool, default = {b = true}},
	{name = "look.inactive_opacity", description = "Dims the contents of the panels that do not have the keyboard, so that the one that has it stands out.", kind = .Float, default = {f = 0.8}, min = 0.3, max = 1, bounded = true},
	{name = "look.font_size", description = "The size of the text, in logical pixels.", kind = .Float, default = {f = 13.5}, min = 10, max = 22, bounded = true},
	{name = "files.show_extensions", description = "Shows the extensions of the files' names.", kind = .Bool, default = {b = true}},
	{name = "files.show_hidden", description = "Shows the hidden files (their names start with a dot; on Windows, their attribute).", kind = .Bool, default = {b = false}},
	{name = "files.folders_first", description = "Lists the folders before the files, whatever the sort.", kind = .Bool, default = {b = true}},
	{name = "files.measure_folders", description = "Measures the folders shown: what they hold all the way down, in the Folders, Files and Size columns.", kind = .Bool, default = {b = true}},
	{name = "view.columns", description = "The columns of the details, in their order (modified, type, counts, size).", kind = .String, default = {s = "modified,type,counts,size"}, hidden = true},
	{name = "keys.custom", description = "The person's keys of the commands (palette: Ctrl+Enter).", kind = .String, default = {s = ""}, hidden = true},
	{name = "keys.aliases", description = "The aliases of the commands (palette: Alt+Enter).", kind = .String, default = {s = ""}, hidden = true},
	{name = "palette.width", description = "The palette's width as last resized (logical pixels; 0: its own).", kind = .Int, default = {i = 0}, hidden = true},
	{name = "palette.height", description = "The palette's height as last resized (logical pixels; 0: its own).", kind = .Int, default = {i = 0}, hidden = true},
	{name = "side.order", description = "The sidebar's sections in their order.", kind = .String, default = {s = "recents,bookmarks,storage,places"}, hidden = true},
	{name = "palette.recent", description = "The commands run last from the palette.", kind = .String, default = {s = ""}, hidden = true},
	{name = "open.single_click", description = "Opens an item with one click instead of two.", kind = .Bool, default = {b = false}},
	{name = "update.auto", category = "updates", description = "The installed classeur checks for a newer one once a day and installs it; it runs at the next start. A copy installed by a package manager (Nix) is updated by it.", kind = .Bool, default = {b = true}},
}

// The values the program reads, copied out of the registry.
Settings :: struct {
	rounding:         f32,
	compact:          bool,
	animations:       string,   // "system", "on", "off" (in the registry)
	smooth_scroll:    bool,
	follow_system:    bool,
	theme:            string,   // in the registry (valid until the next change)
	alternating_rows: bool,
	inactive_opacity: f32,
	font_size:        f32,
	show_extensions:  bool,
	measure_folders:  bool,
	single_click:     bool,
}

prefs_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.config_dir(context.temp_allocator), "/", APP_NAME, "/prefs"}, allocator)
}

// The registry with the user's file read in (headless: the defaults alone, the person's file untouched).
prefs_open :: proc(app: ^App) {
	app.prefs = config.prefs_make()
	// (the theme's choices are the themes' names)
	defs := PREF_DEFS
	names := make([]string, len(themes()))
	for t, i in themes() { names[i] = t.name }
	app.theme_names = names
	for &d in defs { if d.name == "look.theme" { d.choices = names } }
	config.register(&app.prefs, defs[:])
	if !app.headless { config.load_file(&app.prefs, prefs_file(), .User) }
	settings_apply(app)
}

prefs_close :: proc(app: ^App) {
	config.prefs_destroy(&app.prefs)
	delete(app.theme_names)
}

// Writes the user's changes (never in the tests).
prefs_save :: proc(app: ^App) {
	if app.headless { return }
	_ = config.save_user(&app.prefs, prefs_file())
}

// The values where the program reads them, the program changed to follow them.
settings_apply :: proc(app: ^App) {
	p := &app.prefs
	s := &app.settings
	s.rounding = f32(config.float_of(p, "look.rounding"))
	s.compact = config.string_of(p, "look.density") == "compact"
	s.animations = config.string_of(p, "look.animations")
	s.smooth_scroll = config.bool_of(p, "look.smooth_scroll")
	s.follow_system = config.bool_of(p, "look.follow_system")
	s.theme = config.string_of(p, "look.theme")
	s.alternating_rows = config.bool_of(p, "look.alternating_rows")
	s.inactive_opacity = f32(config.float_of(p, "look.inactive_opacity"))
	s.font_size = f32(config.float_of(p, "look.font_size"))
	s.show_extensions = config.bool_of(p, "files.show_extensions")
	s.measure_folders = config.bool_of(p, "files.measure_folders")
	s.single_click = config.bool_of(p, "open.single_click")
	columns_read(app, config.string_of(p, "view.columns"))
	side_order_read(app, config.string_of(p, "side.order"))
	keymap_read(app, config.string_of(p, "keys.custom"), config.string_of(p, "keys.aliases"))
	ui.set_rounding(&app.main.state, s.rounding)
	ui.set_density(&app.main.state, s.compact ? DENSITY_COMPACT : DENSITY)
	ui.set_scrollbar_autohide(&app.main.state, config.bool_of(p, "look.autohide_scrollbars"))
	updates_auto(app)
	hidden := config.bool_of(p, "files.show_hidden")
	if hidden != app.show_hidden {
		app.show_hidden = hidden
		for q in app.panels { for t in q.tabs { folder_set_show_hidden(&t.folder, hidden) } }
	}
	mixed := !config.bool_of(p, "files.folders_first")
	if mixed != app.default_sort.mixed {
		app.default_sort.mixed = mixed
		for q in app.panels {
			for t in q.tabs {
				s := t.folder.sort
				s.mixed = mixed
				folder_set_sort(&t.folder, s)
			}
		}
	}
}

// A preference changed by the program (a key, a toggle): the registry, the file, what follows.
pref_set_bool :: proc(app: ^App, name: string, v: bool) {
	config.set_bool(&app.prefs, config.ref_of(&app.prefs, name), v)
	prefs_save(app)
	settings_apply(app)
}
