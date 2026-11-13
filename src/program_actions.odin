package classeur

// What the program's own commands do (commands.odin, the "Program" group of the palette): quit and restart, the window,
// the updates, about classeur, the look's settings a key away, the layout and the caches.

import "core:fmt"
import "core:strings"
import "core:sync"
import config "gt:config"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:render"
import setup "gt:setup"
import tasks "gt:tasks"
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

// A window of its own on the home folder, as a torn-off tab's (classeur --window), started on a worker: a start may wait.
// Headless (the tests), nothing starts: it is noted in `app.opened`.
act_app_new_window :: proc(app: ^App) {
	if app.headless { append(&app.opened, strings.concatenate({"window:", app.home})) }
	job := new(New_Window)
	job^ = {app = app, exe = strings.clone(app.exe), path = strings.clone(app.home), headless = app.headless}
	tasks.add(&app.pool, new_window_run, job)
}

@(private = "file")
New_Window :: struct {
	app:      ^App,
	exe:      string,   // owned
	path:     string,   // owned
	headless: bool,
}

@(private = "file")
new_window_run :: proc(data: rawptr) {
	job := (^New_Window)(data)
	ok := job.headless || setup.launch(job.exe, {"--window", job.path})
	sync.atomic_store(&job.app.launched_on, sync.current_thread_id())
	if ok || !ui.post(&job.app.main.state, new_window_failed, job) { new_window_free(job) }
}

// On the interface's thread: why no window came.
@(private = "file")
new_window_failed :: proc(data: rawptr, word: u64) {
	job := (^New_Window)(data)
	defer new_window_free(job)
	say(job.app, "No window could be started.")
	app_frames(job.app)
}

@(private = "file")
new_window_free :: proc(job: ^New_Window) {
	delete(job.exe)
	delete(job.path)
	free(job)
}

act_app_minimize :: proc(app: ^App) { platform.minimize(app.main.win) }
act_app_maximize :: proc(app: ^App) { platform.toggle_maximize(app.main.win) }
act_app_full_screen :: proc(app: ^App) { platform.set_fullscreen(app.main.win, !platform.is_fullscreen(app.main.win)) }

////////////////////////////////
// Updates (updates.odin)

act_app_update_check :: proc(app: ^App) { if app.updater != nil { update.check_now(app.updater) } }
act_app_update_install :: proc(app: ^App) { if app.updater != nil { update.install_now(app.updater) } }

has_updater :: proc(app: ^App) -> bool { return app.updater != nil }
update_available :: proc(app: ^App) -> bool { return app.updater != nil && update.status(app.updater).phase == .Available }
update_installed :: proc(app: ^App) -> bool { return app.updater != nil && update.status(app.updater).phase == .Installed }

////////////////////////////////
// About classeur

act_app_about :: proc(app: ^App) {
	say(app, "classeur %s, on gui_toolkit %s. %s", APP_VERSION, ui.VERSION, SITE_URL)
}

act_app_website :: proc(app: ^App) { launch(app, .Open, SITE_URL) }
act_app_report :: proc(app: ^App) { launch(app, .Open, REPOSITORY_URL + "/issues") }
act_app_changelog :: proc(app: ^App) { launch(app, .Open, REPOSITORY_URL + "/releases") }

// Where the settings, the session, the layouts are (prefs_file's folder).
act_app_settings_folder :: proc(app: ^App) {
	launch(app, .Open, platform.user_dir(.Config, APP_NAME, context.temp_allocator))
}

act_app_version_copy :: proc(app: ^App) {
	platform.set_clipboard(app.main.win, "classeur " + APP_VERSION)
	announce(app, .Good, "The version is copied.")
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
	say(app, "Theme: %s.", name)
}

act_app_density :: proc(app: ^App) {
	if app.settings.compact {
		_ = config.reset(&app.prefs, "appearance.density")
		settings_apply(app)
	} else {
		pref_set_string(app, "appearance.density", fmt.tprintf("%v", DENSITY_COMPACT))
	}
	say(app, app.settings.compact ? "Compact rows." : "Comfortable rows.")
}

// Never, or always: "system" (the default) leaves it to the system, which a key cannot tell, so it goes to never first.
act_app_animations :: proc(app: ^App) {
	off := app.settings.animations == "off"
	pref_set_string(app, "appearance.animations", off ? "on" : "off")
	say(app, off ? "Animations on." : "Animations off.")
}

// The text's size by a point, within the setting's bounds.
TEXT_STEP :: 1

act_app_text_bigger :: proc(app: ^App) { text_size_step(app, TEXT_STEP) }
act_app_text_smaller :: proc(app: ^App) { text_size_step(app, -TEXT_STEP) }

act_app_text_reset :: proc(app: ^App) {
	_ = config.reset(&app.prefs, prefs_page.FONT_SIZE_PREF)
	settings_apply(app)
	say(app, "Text size: %v.", app.settings.font_size)
}

@(private = "file")
text_size_step :: proc(app: ^App, by: f32) {
	size := clamp(app.settings.font_size + by, prefs_page.FONT_SIZE_MIN, prefs_page.FONT_SIZE_MAX)
	if size == app.settings.font_size { return }
	pref_set_string(app, prefs_page.FONT_SIZE_PREF, fmt.tprintf("%v", size))
	say(app, "Text size: %v.", app.settings.font_size)
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

// The thumbnails made so far are forgotten: the cards shown ask for theirs again. One asked stays: its job answers it.
act_app_thumbs_clear :: proc(app: ^App) {
	gone := make([dynamic]string, context.temp_allocator)
	for k, th in app.thumbs { if th.state != .Asked { append(&gone, k) } }
	for k in gone {
		key, th := delete_key(&app.thumbs, k)
		if th.state == .Ready { render.destroy_texture(&app.shared.r, th.tex) }
		delete(key)
	}
	announce(app, .Good, "The thumbnails are cleared.")
	app_frames(app)
}
