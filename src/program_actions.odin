package classeur

// What the program's own commands do (commands.odin, the "Program" group of the palette): quit and restart, the window,
// the updates, about classeur, the look's settings a key away, the layout and the caches.

import "core:fmt"
import "core:strings"
import config "gt:config"
import "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import update "gt:update"
import "gt:ui"

SITE_URL       :: "https://classeur.froment.software/"
REPOSITORY_URL :: "https://github.com/sachahjkl/classeur"

////////////////////////////////
// Quit and restart

// As the window's close: app_run's loop ends, the session is saved.
act_app_quit :: proc(app: ^App) { platform.request_close(app.main.win) }

// The new copy starts once this one has ended (app_run's end): until then this one holds the single instance, and a copy
// started before would hand its start to it and end. The session saved at the close brings the tabs back.
act_app_restart :: proc(app: ^App) { updates_restart(app) }

// (a window of a torn-off tab has no session: a restart would open another window on the home folder)
can_restart :: proc(app: ^App) -> bool { return !app.standalone }

////////////////////////////////
// The window

// A new in-process window on the home folder, sharing host.Shared with this window.
act_app_new_window :: proc(app: ^App) {
	if app.window_fails {
		say(app, i18n.tr("No window could be started."))
		app_frames(app)
		return
	}
	if app.hub != nil {
		if hub_open_window(app.hub, {folders = {app.home}, home = app.home, standalone = true, headless = app.headless}) == nil {
			say(app, i18n.tr("No window could be started."))
			app_frames(app)
			return
		}
	}
	if app.headless { append(&app.opened, strings.concatenate({"window:", app.home})) }
	app_frames(app)
}

act_app_minimize :: proc(app: ^App) { platform.minimize(app.main.win) }
act_app_maximize :: proc(app: ^App) { platform.toggle_maximize(app.main.win) }
act_app_full_screen :: proc(app: ^App) { platform.set_fullscreen(app.main.win, !platform.is_fullscreen(app.main.win)) }

////////////////////////////////
// Updates (updates.odin)

act_app_update_check :: proc(app: ^App) { if app.updates.updater != nil { update.check_now(app.updates.updater) } }
act_app_update_install :: proc(app: ^App) { if app.updates.updater != nil { update.install_now(app.updates.updater) } }

has_updater :: proc(app: ^App) -> bool { return app.updates.updater != nil }
update_available :: proc(app: ^App) -> bool { return app.updates.updater != nil && update.status(app.updates.updater).phase == .Available }
update_installed :: proc(app: ^App) -> bool { return app.updates.updater != nil && update.status(app.updates.updater).phase == .Installed }

////////////////////////////////
// About classeur

act_app_about :: proc(app: ^App) {
	app.about_open = true
}

act_app_website :: proc(app: ^App) { launch(app, .Open, SITE_URL) }
act_app_report :: proc(app: ^App) { launch(app, .Open, REPOSITORY_URL + "/issues") }
act_app_changelog :: proc(app: ^App) { launch(app, .Open, REPOSITORY_URL + "/releases") }

// Where the settings, the session, the layouts are (prefs_file's folder).
act_app_settings_folder :: proc(app: ^App) {
	launch(app, .Open, platform.user_dir(.Config, APP_FOLDER, context.temp_allocator))
}

act_app_version_copy :: proc(app: ^App) {
	platform.set_clipboard(app.main.win, APP_TITLE + " " + APP_VERSION)
	announce(app, .Good, i18n.tr("The version is copied."))
}

////////////////////////////////
// The look: the settings' values, a key away

act_app_theme_next :: proc(app: ^App) { theme_step(app, 1) }
act_app_theme_previous :: proc(app: ^App) { theme_step(app, -1) }

// The theme after or before this one, in the settings' order (their cards').
@(private = "file")
theme_step :: proc(app: ^App, by: int) {
	list := themes(app)
	n := len(list)
	if n == 0 { return }
	at := 0
	for t, i in list { if t.name == app.settings.theme { at = i } }
	name := list[((at + by) % n + n) % n].name
	pref_set_string(app, prefs_page.THEME_PREF, name)
	say(app, i18n.tr("Theme: %s."), name)
}

act_app_density :: proc(app: ^App) {
	if app.settings.compact {
		_ = config.reset(&app.prefs, "appearance.density")
		settings_apply(app)
	} else {
		pref_set_string(app, "appearance.density", fmt.tprintf("%v", DENSITY_COMPACT))
	}
	say(app, app.settings.compact ? i18n.tr("Compact rows.") : i18n.tr("Comfortable rows."))
}

// Never, or always: "system" (the default) leaves it to the system, which a key cannot tell, so it goes to never first.
act_app_animations :: proc(app: ^App) {
	off := app.settings.animations == "off"
	pref_set_string(app, "appearance.animations", off ? "on" : "off")
	say(app, off ? i18n.tr("Animations on.") : i18n.tr("Animations off."))
}

// The text's size by a point, within the setting's bounds.
TEXT_STEP :: 1

act_app_text_bigger :: proc(app: ^App) { text_size_step(app, TEXT_STEP) }
act_app_text_smaller :: proc(app: ^App) { text_size_step(app, -TEXT_STEP) }

act_app_text_reset :: proc(app: ^App) {
	_ = config.reset(&app.prefs, prefs_page.FONT_SIZE_PREF)
	settings_apply(app)
	say(app, i18n.tr("Text size: %v."), app.settings.font_size)
}

@(private = "file")
text_size_step :: proc(app: ^App, by: f32) {
	size := clamp(app.settings.font_size + by, prefs_page.FONT_SIZE_MIN, prefs_page.FONT_SIZE_MAX)
	if size == app.settings.font_size { return }
	pref_set_string(app, prefs_page.FONT_SIZE_PREF, fmt.tprintf("%v", size))
	say(app, i18n.tr("Text size: %v."), app.settings.font_size)
}

@(private = "file")
pref_set_string :: proc(app: ^App, name, text: string) {
	_ = config.set_from_string(&app.prefs, name, text, .User)
	settings_apply(app)
}

////////////////////////////////
// The layout and the caches

// Every tab read again (F5 for them all).
act_app_reload_all :: proc(app: ^App) {
	for p in app.panels { for t in p.tabs { tab_load(app, t) } }
}

// One panel, one tab on the home folder. The tabs closed can be opened again (Ctrl+Shift+T), but those of the other panels.
act_app_layout_reset :: proc(app: ^App) {
	for len(app.panels) > 1 { panel_close(app, app.panels[len(app.panels) - 1]) }
	app.focus = 0
	p := app.panels[0]
	p.below = false
	// (the last tab closed opens one at home: tab_close)
	for i := len(p.tabs) - 1; i >= 0; i -= 1 { tab_close(app, p, i) }
	p.active = 0
	if t := current_tab(app); t != nil { t.focus_due = .List }
}

// The thumbnails made so far are forgotten: the cards shown ask for theirs again. One asked stays: its answer lands.
act_app_thumbs_clear :: proc(app: ^App) {
	ui.thumb_cache_clear(&app.thumbs)
	announce(app, .Good, i18n.tr("The thumbnails are cleared."))
	app_frames(app)
}
