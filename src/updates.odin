package classeur

// Updates: the toolkit's Updater (gt:update) checks classeur's latest release a while after the start and then every
// day, downloads the program it names, checks it against its signed manifest (src/update: classeur's product and key) and
// puts it in place of this one; the new classeur runs at the next start (the settings' Restart now, or the next time).
// Only the installed copy does it by itself (update.auto): a build, or a copy run where it was unpacked, is updated when
// the settings' Check now asks. A copy from the Nix store is left to Nix (the Updater says so).

import "core:fmt"
import config "gt:config"
import "core:strings"
import "gt:platform"
import prefs_page "gt:prefs_page"
import setup "gt:setup"
import tasks "gt:tasks"
import update "gt:update"
import classeur_update "update"

// The folder of the latest release's files: its manifests (update-<platform>.json and .sig) and its programs.
UPDATE_FOLDER :: "https://github.com/sachahjkl/classeur/releases/latest/download/"

updates_start :: proc(app: ^App) {
	if app.headless { return }   // (the tests reach no network)
	// (app.installed_copy comes with the start's reading of the install, on a task: setup_follow; updates_auto again then)
	// (update.base_url, read at the start: another server's releases)
	folder, _ := prefs_page.update_source(&app.prefs)
	app.updater = update.updater_start({
		product = classeur_update.PRODUCT, folder = folder != "" ? folder : UPDATE_FOLDER, current = APP_VERSION,
		exe = app.exe, user_agent = fmt.tprintf("classeur/%s", APP_VERSION),
		// (the updater's thread: the loop wakes, and updates_follow reads the state)
		news = proc(user: rawptr) { platform.wake((^App)(user).main.win) }, user = app,
	})
	updates_auto(app)
}

updates_stop :: proc(app: ^App) {
	if app.updater == nil { return }
	update.updater_stop(app.updater)
	app.updater = nil
}

// update.auto, read again when the preferences change.
updates_auto :: proc(app: ^App) {
	if app.updater == nil { return }
	auto := config.bool_of(&app.prefs, prefs_page.UPDATE_AUTO_PREF) && app.installed_copy
	update.set_auto(app.updater, auto ? .Install : .Off)
}

// Each frame: what changed is said once (asked, or something to know: not each check that found nothing).
updates_follow :: proc(app: ^App) {
	if app.updater == nil { return }
	st := update.status(app.updater)
	if st.serial == app.update_serial { return }
	app.update_serial = st.serial
	if st.asked || st.phase == .Installed || st.phase == .Available { say(app, "%s", update.status_words(st)) }
	// (the installed copy: its manifest and Settings > Apps say the new version; written on a worker)
	if st.phase == .Installed {
		version := new_clone(strings.clone(st.version))
		tasks.add(&app.pool, proc(data: rawptr) {
			version := (^string)(data)
			defer { delete(version^); free(version) }
			if ok, why := setup.updated(setup_options(), version^); !ok { fmt.eprintfln("classeur: the update is in place, but %s", why) }
		}, version)
	}
}

// The new program takes over: started once this one has ended (it holds the single instance until then).
updates_restart :: proc(app: ^App) {
	delete(app.launch_after)
	app.launch_after = strings.clone(app.exe)
	platform.request_close(app.main.win)
}
