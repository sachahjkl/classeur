package classeur

// The settings (Ctrl+,): the toolkit's settings page (gt:prefs_page) over the window, in a dialog the person resizes by
// its edges and corner. Every preference of the registry that is not the program's own has its line there: its title,
// what it does, its control; the search on the left finds them by their words. The themes are cards.

import config "gt:config"
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

@(private = "file", rodata)
OPTIONS_PAGES := [?]prefs_page.Page_Info{
	{category = "look", title = "Appearance", icon = lucide.PALETTE},
	{category = "files", title = "Files", icon = lucide.FILE},
	{category = "open", title = "Opening", icon = lucide.FOLDER_OPEN},
	{category = "updates", title = "Updates", icon = lucide.DOWNLOAD},
}

options_build :: proc(app: ^App) {
	o := &app.options
	if !o.open {
		// (closed while a slider was held: what it showed and did not write goes back to the preferences)
		if o.shown { o.shown = false; settings_apply(app) }
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

@(private = "file", rodata)
OPTIONS_CUSTOM := [?]string{"look.theme"}   // (the themes: cards, drawn by the page's custom)

// The settings page's options: its build's, and the palette's list of the settings (palette.odin).
options_page :: proc(app: ^App) -> prefs_page.Options {
	return {
		version = "classeur " + APP_VERSION,
		user = app,
		pages = OPTIONS_PAGES[:],
		icon_font = app.icons, search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		foot = "Ctrl+,: these settings",
		changed = proc(user: rawptr, name: string) {
			app := (^App)(user)
			prefs_save(app)
			settings_apply(app)
		},
		// (a slider held: its value shown at once, written when it is let go; only what moves nothing: a text size
		// shown live moved the slider under the pointer, it comes when let go)
		preview = proc(user: rawptr, name: string, value: f64) {
			app := (^App)(user)
			switch name {
			case "look.rounding":         ui.set_rounding(&app.main.state, f32(value))
			case "look.inactive_opacity": app.settings.inactive_opacity = f32(value)
			}
			app_frames(app)
		},
		updater = app.updater, update_pref = "update.auto",
		restart = proc(user: rawptr) { updates_restart((^App)(user)) },
		custom_names = OPTIONS_CUSTOM[:],
		custom = proc(user: rawptr, name: string, em: f32) {
			app := (^App)(user)
			if at := prefs_page.theme_cards(themes(), app.settings.theme, app.theme_shown.light, em); at >= 0 {
				_ = config.set_from_string(&app.prefs, "look.theme", themes()[at].name, .User)
				prefs_save(app)
				settings_apply(app)
			}
		},
	}
}
