package classeur

// Updates: the toolkit's (prefs_page.updates_*). Its Updater (gt:update) checks classeur's latest release a while after
// the start and then every day, downloads the program it names, checks it against its signed manifest (src/update:
// classeur's product and key) and puts it in place of this one; the new classeur runs at the next start (the settings'
// Restart now, or the next time). Only the installed copy does it by itself (update.auto): a build, or a copy run where
// it was unpacked, is updated when the settings' Check now asks. A copy from the Nix store is left to Nix (the Updater
// says so).

import "gt:platform"
import prefs_page "gt:prefs_page"
import update "gt:update"
import classeur_update "update"

updates_start :: proc(app: ^App) {
	if app.headless { return }   // (the tests reach no network)
	prefs_page.updates_start(&app.updates, {
		product = classeur_update.PRODUCT, repository = "sachahjkl/classeur", version = APP_VERSION,
		prefs = &app.prefs, install = &app.install, state = &app.main.state, window = app.main.win,
	})
}

updates_stop :: proc(app: ^App) { prefs_page.updates_stop(&app.updates) }

// Each frame: what changed is said once. The head bar's badge shows the phase (a version on offer, its download, a
// restart); the status line says only what the badge cannot (update.notice).
updates_follow :: proc(app: ^App) {
	if changed, st := prefs_page.updates_follow(&app.updates); changed {
		app_frames(app)   // (the badge shows the new phase)
		if words, _ := update.notice(st); words != "" { say(app, "%s", words) }
	}
}

// The new program takes over: started once this one has ended (it holds the single instance until then).
updates_restart :: proc(app: ^App) {
	app.restart = true
	platform.request_close(app.main.win)
}
