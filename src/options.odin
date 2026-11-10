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
	if !o.open { return }
	em := ui.font_size()
	// (Escape closes it, unless a field of the page has the keyboard: that Escape is the field's)
	if !prefs_page.editing(&o.page) && ui.key_press(.Escape) { o.open = false; return }
	if ui.modal_sized("options", OPTIONS_PREFERRED_EM * em, &o.size, &o.open, OPTIONS_MIN_EM * em) {
		ui.next({width = ui.fill(), height = ui.fill()})
		prefs_page.build(&o.page, &app.prefs, {
			user = app,
			pages = OPTIONS_PAGES[:],
			icon_font = app.icons, search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
			foot = "Ctrl+,: these settings",
			changed = proc(user: rawptr, name: string) {
				app := (^App)(user)
				prefs_save(app)
				settings_apply(app)
			},
			updater = app.updater, update_pref = "update.auto",
			restart = proc(user: rawptr) { updates_restart((^App)(user)) },
			custom_names = {"look.theme"},
			custom = proc(user: rawptr, name: string, em: f32) {
				app := (^App)(user)
				if at := prefs_page.theme_cards(themes(), app.settings.theme, app.theme_shown.light, em); at >= 0 {
					_ = config.set_from_string(&app.prefs, "look.theme", themes()[at].name, .User)
					prefs_save(app)
					settings_apply(app)
				}
			},
		})
	}
}
