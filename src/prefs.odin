package classeur

// The preferences: one registry (gt:config), its user file at <config>/classeur/prefs, read at the start and written at
// each change made in the options (options.odin). `settings_apply` copies classeur's values where the program reads
// them; the toolkit's standard ones go to the toolkit by themselves (prefs_page.standard_watch).

import vmem "core:mem/virtual"
import "core:strings"
import config "gt:config"
import "gt:font"
import "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

// classeur's own preferences. The look, the text, the scrolling, the hand's feel, the updates and the desktop are the
// toolkit's standard ones (prefs_page.standard_register, docs/settings.md of gui_toolkit): one name per concept. The
// titles and descriptions shown are marked by i18n.later for the catalogue (a hidden one is never shown); a title is
// the one its name gave, written out: one made from the name is in no catalogue.
PREF_DEFS := [?]config.Def{
	{name = "appearance.alternating_rows", title = i18n.later("Alternating rows"), tags = {"zebra", "stripes"}, description = i18n.later("Paints every other row a shade lighter, to tell the rows apart."), kind = .Bool, default = {b = false}},
	{name = "appearance.inactive_opacity", title = i18n.later("Inactive opacity"), tags = {"dim", "panels", "focus"}, description = i18n.later("Dims the contents of the panels that do not have the keyboard, so that the one that has it stands out."), kind = .Float, default = {f = 0.8}, min = 0.3, max = 1, bounded = true},
	{name = "files.show_extensions", title = i18n.later("Show extensions"), tags = {"suffix", "names"}, description = i18n.later("Shows the extensions of the files' names."), kind = .Bool, default = {b = true}},
	{name = "files.show_hidden", title = i18n.later("Show hidden"), tags = {"dotfiles", "hidden"}, description = i18n.later("Shows the hidden files (their names start with a dot; on Windows, their attribute)."), kind = .Bool, default = {b = false}},
	{name = "files.folders_first", title = i18n.later("Folders first"), tags = {"directories", "sort", "order"}, description = i18n.later("Lists the folders before the files, whatever the sort."), kind = .Bool, default = {b = true}},
	{name = "files.date_format", title = i18n.later("Date format"), tags = {"dates", "time", "modified", "relative"}, description = i18n.later("How the dates read: 2026-11-09 21:40; Today 21:40, Yesterday, the weekday for the last week, then 9 Nov 2026; or 9 Nov 2026 21:40."), kind = .String, default = {s = "ISO"}, choices = {"ISO", "relative", "day month year"}, choice_labels = {i18n.later("ISO"), i18n.later("Relative"), i18n.later("Day month year")}},
	{name = "files.measure_folders", title = i18n.later("Measure folders"), tags = {"size", "du", "count"}, description = i18n.later("Measures the folders shown: what they hold all the way down, in the Folders, Files and Size columns."), kind = .Bool, default = {b = true}},
	{name = "view.columns", description = "The columns of the details shown after the name, in their order.", kind = .String, default = {s = DETAIL_COLUMNS_DEFAULT}, hidden = true},
	{name = "view.column_widths", description = "The widths of the details' columns the person changed (ems).", kind = .String, default = {s = ""}, hidden = true},
	{name = "keys.custom", description = "The person's keys of the commands (palette: Ctrl+Enter).", kind = .String, default = {s = ""}, hidden = true},
	{name = "keys.aliases", description = "The aliases of the commands (palette: Alt+Enter).", kind = .String, default = {s = ""}, hidden = true},
	{name = "palette.width", description = "The palette's width as last resized (ems; 0: its own).", kind = .Float, default = {f = 0}, hidden = true},
	{name = "palette.height", description = "The palette's height as last resized (ems; 0: its own).", kind = .Float, default = {f = 0}, hidden = true},
	{name = "inspector.width", description = "The inspector's width as last dragged (logical pixels).", kind = .Int, default = {i = INSPECTOR_DEFAULT_PX}, hidden = true},
	{name = "side.order", description = "The sidebar's sections in their order.", kind = .String, default = {s = "recents,bookmarks,storage,network,places"}, hidden = true},
	{name = "open.single_click", title = i18n.later("Single click"), tags = {"click", "double click"}, description = i18n.later("Opens an item with one click instead of two."), kind = .Bool, default = {b = false}},
}

// classeur's texts in other languages (docs/i18n.md of gui_toolkit), embedded: `classeurtool i18n fr` writes them.
CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}

// classeur's identity in the standard settings: its theme and its name. The rest is the toolkit's, as in its other
// programs (prefs_page.STANDARD_DEFAULTS).
@(private = "file")
standard_defaults :: proc() -> prefs_page.Standard_Defaults {
	d := prefs_page.STANDARD_DEFAULTS
	d.theme, d.app_name = "Graphite", APP_NAME
	return d
}

// The values the program reads, copied out of the registry.
Settings :: struct {
	compact:          bool,     // appearance.density below 1 (the Density command's two steps)
	animations:       string,   // "system", "on", "off" (in the registry)
	system_title:     bool,   // the system draws the title bar (the tabs under it, no window buttons of classeur's)
	theme:            string,   // in the registry (valid until the next change)
	mode:             ui.Theme_Mode,
	finish:           ui.Finish,
	glow:             f32,
	alternating_rows: bool,
	inactive_opacity: f32,
	font_size:        f32,
	show_extensions:  bool,
	date_format:      Date_Format,
	measure_folders:  bool,
	single_click:     bool,
}

prefs_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_NAME, context.temp_allocator), "/prefs"}, allocator)
}

// Where the changes are written: the person's file; the tests', beside their session file (none: headless).
prefs_path :: proc(app: ^App) -> string {
	if app.session_path != "" { return strings.concatenate({app.session_path, ".prefs"}, context.temp_allocator) }
	if app.headless { return "" }
	return prefs_file()
}

// The registry with the user's file read in (headless: the defaults alone, the person's file untouched). (Read on this
// thread: at the start, before the window is shown and the first frame.)
prefs_open :: proc(app: ^App) {
	app.prefs = config.prefs_make()
	// (the toolkit's standard preferences first: their descriptions live in prefs_words, as long as the registry)
	_ = vmem.arena_init_growing(&app.prefs_words)
	prefs_page.standard_register(&app.prefs, prefs_page.STANDARD_ALL, standard_defaults(), vmem.arena_allocator(&app.prefs_words))
	if r := config.ref_of(&app.prefs, prefs_page.SYSTEM_TITLE_PREF); r != config.NO_REF {
		e := config.entry(&app.prefs, r)
		// (offered where the system can draw a title bar: Windows, X11, a Wayland compositor with server-side ones;
		// classeur changes its title bar at once: settings_apply)
		e.def.hidden = !platform.system_title_available(app.main.win)
	}
	// (the launcher and the start with the session apply to the copy that is integrated: their switches show once a
	// worker found this copy is it, desktop_follow)
	desktop_owned := [?]string{prefs_page.MENU_PREF, prefs_page.AUTOSTART_PREF}
	for name in desktop_owned {
		if r := config.ref_of(&app.prefs, name); r != config.NO_REF { config.entry(&app.prefs, r).def.hidden = true }
	}
	config.register(&app.prefs, PREF_DEFS[:])
	if !app.headless {
		config.load_file(&app.prefs, prefs_file(), .User)
		// (general.language read, before any text is formatted for the window; the tests stay in English whatever the
		// machine's language: they compare the texts)
		prefs_page.language_start(&app.prefs, CATALOGUES)
	}
	// (the person's own themes, beside the preferences; none in the tests)
	themes_path := ""
	if !app.headless { themes_path = themes_file() }
	prefs_page.themes_file_init(&app.themes_file, themes_path, ui.THEMES[:])
	fonts_apply(app)
	settings_apply(app)
	// (the toolkit's settings to the toolkit, now and at each change: the feel, the zoom, the density, the corners, the
	// motion, the scrolling, the text's rendering)
	prefs_page.standard_watch(&app.standard, &app.prefs, &app.main.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &app.main.partial_redraw})
	if path := prefs_path(app); path != "" { config.user_writer_start(&app.prefs_writer, &app.prefs, path) }
}

prefs_close :: proc(app: ^App) {
	prefs_page.standard_unwatch(&app.standard)
	prefs_page.themes_file_destroy(&app.themes_file)
	config.prefs_destroy(&app.prefs)
	vmem.arena_destroy(&app.prefs_words)
}

// The person's own themes ([Name] sections of colours): made from the toolkit's template at the settings' first click.
themes_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_NAME, context.temp_allocator), "/themes.txt"}, allocator)
}

// The fonts the person named (appearance.text.*), read at the start: the system's family in place of classeur's.
@(private = "file")
fonts_apply :: proc(app: ^App) {
	if app.headless { return }   // (the tests' fonts are compiled in)
	p := &app.prefs
	fonts := &app.shared.fonts
	if family := config.string_of(p, prefs_page.UI_FONT_PREF); family != "" {
		if id, ok := font.load_system(fonts, family); ok { app.shared.font = id }
	}
	if family := config.string_of(p, prefs_page.MONO_FONT_PREF); family != "" {
		if id, ok := font.load_system(fonts, family); ok { app.mono = id }
	}
	if path := config.string_of(p, prefs_page.EMOJI_FONT_PREF); path != "" { font.set_emoji_source(fonts, path) }
}

// Each round of the loop: the user's changes since the last text handed to the writer's thread, which writes them (config.User_Writer:
// the interface's thread never waits for the disk; many changes, one write).
prefs_tidy :: proc(app: ^App) {
	config.user_writer_save(&app.prefs_writer, &app.prefs)
	if config.user_writer_failed(&app.prefs_writer) { say(app, i18n.tr("The settings cannot be written to %s"), prefs_path(app)) }
}

// The values where the program reads them, the program changed to follow them.
settings_apply :: proc(app: ^App) {
	p := &app.prefs
	s := &app.settings
	s.compact = config.float_of(p, "appearance.density") < 1
	s.animations = config.string_of(p, "appearance.animations")
	s.system_title = config.bool_of(p, prefs_page.SYSTEM_TITLE_PREF)
	if !app.headless { platform.set_integrated_title(app.main.win, !s.system_title) }
	look := prefs_page.appearance_read(p, context.temp_allocator)
	s.theme = config.string_of(p, prefs_page.THEME_PREF)   // (the registry's: valid until the next change)
	s.mode, s.finish, s.glow, s.font_size = look.mode, look.finish, look.glow, look.font_size
	s.alternating_rows = config.bool_of(p, "appearance.alternating_rows")
	s.inactive_opacity = f32(config.float_of(p, "appearance.inactive_opacity"))
	s.show_extensions = config.bool_of(p, "files.show_extensions")
	switch config.string_of(p, "files.date_format") {
	case "relative":       s.date_format = .Relative
	case "day month year": s.date_format = .Day_Month_Year
	case:                  s.date_format = .ISO
	}
	s.measure_folders = config.bool_of(p, "files.measure_folders")
	s.single_click = config.bool_of(p, "open.single_click")
	app.announcer.mode = prefs_page.announce_mode(p)
	columns_read(app, config.string_of(p, "view.columns"), config.string_of(p, "view.column_widths"))
	side_order_read(app, config.string_of(p, "side.order"))
	keymap_read(app, config.string_of(p, "keys.custom"), config.string_of(p, "keys.aliases"))
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
	config.set_bool(&app.prefs, name, v)
	settings_apply(app)
}
