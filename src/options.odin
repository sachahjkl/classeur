package classeur

// The settings (Ctrl+,): the toolkit's settings page (gt:prefs_page) over the window, in a dialog the person resizes by
// its edges and corner. Every preference of the registry that is not the program's own has its line there: its title,
// what it does, its control; the search on the left finds them by their words. The themes are cards.

import config "gt:config"
import "gt:i18n"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:ui"

// Its size when first opened, and the least it can be made (em).
OPTIONS_PREFERRED_EM :: [2]f32{56, 40}
OPTIONS_MIN_EM :: [2]f32{34, 20}

Options :: struct {
	open: bool,
	page: prefs_page.Page,
	size: ui.Vec2,   // as the person resized it (logical px; {}: preferred)
	shown: bool,     // it was open at the last build (closed since: a slider's preview undone)
}

options_free :: proc(o: ^Options) {
	prefs_page.destroy(&o.page)
	o^ = {}
}

act_options :: proc(app: ^App) {
	o := &app.options
	o.open = !o.open
	if o.open { prefs_page.focus_search(&o.page) }
}

// The pages in their order: the toolkit's standard groups (docs/settings.md) and classeur's own (files, open); the look
// first, as the settings open on it.
// (not rodata: i18n.later marks the titles for the catalogue; options_page gives the page their translations)
@(private = "file")
OPTIONS_PAGES := [?]prefs_page.Page_Info{
	{category = "appearance", title = i18n.later("Appearance"), icon = lucide.PALETTE},
	{category = "window", title = i18n.later("Window"), icon = lucide.APP_WINDOW},
	{category = "files", title = i18n.later("Files"), icon = lucide.FILE},
	{category = "open", title = i18n.later("Opening"), icon = lucide.FOLDER_OPEN},
	{category = "scrolling", title = i18n.later("Scrolling"), icon = lucide.MOUSE},
	{category = "input", title = i18n.later("Input"), icon = lucide.KEYBOARD},
	{category = "timing", title = i18n.later("Delays and menus"), icon = lucide.TIMER},
	{category = "update", title = i18n.later("Updates"), icon = lucide.DOWNLOAD},
	{category = "rendering", title = i18n.later("Rendering"), icon = lucide.MONITOR},
	{category = "general", title = i18n.later("General"), icon = lucide.SETTINGS},
}

options_build :: proc(app: ^App) {
	o := &app.options
	if !o.open {
		// (closed while a slider was held: what it showed and did not write goes back to the preferences)
		if o.shown { o.shown = false; options_unpreview(app) }
		return
	}
	o.shown = true
	em := ui.font_size()
	if ui.modal_sized("options", OPTIONS_PREFERRED_EM * em, &o.size, &o.open, OPTIONS_MIN_EM * em) {
		// (Escape closes it, unless a field of the page has the keyboard: that Escape is the field's; read in its scope,
		// where an open dialog's keys are)
		if !prefs_page.editing(&o.page) && ui.key_press(.Escape) { o.open = false }
		ui.next({width = ui.fill(), height = ui.fill()})
		prefs_page.build(&o.page, &app.prefs, options_page(app))
	}
}

// What a held slider showed and did not write, back to the preferences' values.
@(private = "file")
options_unpreview :: proc(app: ^App) {
	ui.set_rounding(&app.main.state, f32(config.float_of(&app.prefs, "appearance.rounding")))
	settings_apply(app)
}

// The build of the README's pictures (classeurtool shots). They are made before a release sets its version: a version
// shown in them would be the last release's.
@(private = "file")
SHOTS_BUILD :: #config(CLASSEUR_SHOTS, false)

// The settings page's options: its build's, and the palette's list of the settings (palette.odin).
options_page :: proc(app: ^App) -> prefs_page.Options {
	// (the pages' titles in the person's language: the page shows them as given)
	pages := make([]prefs_page.Page_Info, len(OPTIONS_PAGES), context.temp_allocator)
	for p, i in OPTIONS_PAGES {
		pages[i] = p
		pages[i].title = i18n.tr(p.title)
	}
	return {
		version = SHOTS_BUILD ? "" : "classeur " + APP_VERSION,
		user = app,
		pages = pages,
		icon_font = app.icons, search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		file = SHOTS_BUILD ? "" : prefs_path(app),
		changed = proc(user: rawptr, name: string) {
			app := (^App)(user)
			settings_apply(app)
			if name == prefs_page.MENU_PREF || name == prefs_page.AUTOSTART_PREF { desktop_follow(app) }
		},
		// (a slider held: its value shown at once, written when it is let go; only what moves nothing: a text size
		// shown live moved the slider under the pointer, it comes when let go)
		preview = proc(user: rawptr, name: string, value: f64) {
			app := (^App)(user)
			switch name {
			case "appearance.rounding":         ui.set_rounding(&app.main.state, f32(value))
			case "appearance.inactive_opacity": app.settings.inactive_opacity = f32(value)
			}
			app_frames(app)
		},
		updater = app.updater,
		restart = proc(user: rawptr) { updates_restart((^App)(user)) },
		themes = themes(app), themes_light = app.theme_shown.light, themes_file = &app.themes_file,
		page_foot = proc(user: rawptr, category: string, em: f32) {
			if category == "general" { licence_section((^App)(user), em) }
		},
	}
}
