package classeur

// classeur on the user's desktop (gui_toolkit's desktop and setup, through prefs_page.Install): the copy installed in a
// folder of its own with a launcher in the application menu and its icons, classeur on the PATH, "Open folders with
// classeur" in the menus that offer it. Everything in the user's profile. The settings' Installation page shows the
// install and acts on it.
//
//   classeur --install     this copy installed for the user (no window)
//   classeur --uninstall   the install taken away; the settings stay (no window)
//   classeur --status      what is installed, and whether classeur runs (no window)
//   classeur --setup       the window, the install's dialog open
//
// On Windows a copy that is not installed offers the install at its start, once per version unless the person keeps it
// standalone; on Linux Nix installs it, or `classeur --install`.

import "core:fmt"
import "core:os"
import config "gt:config"
import desktop "gt:desktop"
import "gt:i18n"
import "gt:process"
import setup "gt:setup"
import prefs_page "gt:prefs_page"
import tasks "gt:tasks"
import "gt:ui"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

classeur_identity :: proc() -> desktop.Identity {
	return desktop.Identity{
		name = "Classeur", key = "Classeur", slug = APP_NAME,
		description = "A fast file manager: tabs in panels, a command palette, GoTo, batch rename, undo.",
		vendor = "Froment Software",
		entry_marker = "X-Classeur-Integration", registry_mark = "ClasseurIntegration", vendor_key = "FromentSoftware",
		manifest_name = "classeur_install.txt",
		generic_name = "File Manager", categories = "System;FileTools;FileManager;Utility;Core;",
		keywords = "folder;manager;explore;disk;filesystem;files;",
		env_prefix = "CLASSEUR_DESKTOP_",
		uninstall_arguments = "--setup",
	}
}

// classeur's own parts of an install: the PATH (on Windows with classeur.com, the console launcher the toolkit's build
// embeds: `classeur` typed in cmd or PowerShell gives its output and exit code).
classeur_parts :: proc(o: ^desktop.Integration_Options) {
	o.add_to_path = true
}

// The running copy's integration (desktop_follow): the places of a test come from the environment (CLASSEUR_DESKTOP_*).
@(private = "file")
integration_options :: proc() -> desktop.Integration_Options {
	o := desktop.options_make(classeur_identity())
	o.exe = process.executable_path()
	o.icons = ICON_PNGS[:]
	classeur_parts(&o)
	desktop.roots_from_env(&o, env_lookup)
	return o
}

@(private = "file")
env_lookup :: proc(name: string) -> string { return os.get_env(name, context.temp_allocator) }

////////////////////////////////
// The install (prefs_page.Install: the offer, the dialog, the settings' Installation page)

setup_options :: proc() -> setup.Setup_Options {
	return setup.Setup_Options{
		identity = classeur_identity(), version = APP_VERSION, install_folder = APP_NAME, icons = ICON_PNGS[:],
		choices = SETUP_CHOICES[:], square = true, running = app_running,
		prepare = proc(o: ^desktop.Integration_Options, choices: []bool, user: rawptr) {
			classeur_parts(o)
			if len(choices) == len(SETUP_CHOICES) { o.add_to_path = choices[0] }
			desktop.roots_from_env(o, env_lookup)   // (a test's places: nothing of the person's)
		},
	}
}

// (not rodata: i18n.later marks the labels for the catalogue; tr where they are shown)
@(private = "file")
SETUP_CHOICES := [?]setup.Choice{
	{label = i18n.later("classeur in the terminal (on the PATH)"), on = true},
}

// Once the start's reading of the install came (prefs_page.install_offer): whether this copy is the installed one (the
// updater's auto), and the switches of the menu and the session for it.
setup_follow :: proc(app: ^App) {
	if app.setup_known || !app.install.known { return }
	app.setup_known = true
	app.installed_copy = app.install.running_it
	updates_auto(app)
	app_frames(app)
}

////////////////////////////////
// The settings' general.menu and general.autostart (the toolkit's standard ones)

// The install (its dialog, its page, `classeur --install`) integrates a copy; the settings then say whether that copy is in
// the application menu and starts with the session, and desktop.apply makes it so. Only the integrated copy follows
// them: a build or a copy that is not integrated (Nix's, which Nix integrates) never installs anything because of a
// preference. So at the start, and after each change of the two, a worker reads the integration's status: when its parts
// are this copy's, it applies the two (the PATH part stays as the install left it), and the settings show
// their switches. `classeur --uninstall` and the Installation page's Uninstall stay the way to take the whole install away.
desktop_follow :: proc(app: ^App) {
	if app.headless || app.standalone { return }   // (the tests touch nothing of the person's; a torn-off tab's window owns nothing)
	job := new(Desktop_Follow)
	job^ = {app = app, menu = config.bool_of(&app.prefs, prefs_page.MENU_PREF), autostart = config.bool_of(&app.prefs, prefs_page.AUTOSTART_PREF)}
	// (the edits' worker: one at a time, in the order asked, so that the last change wins)
	tasks.add(&app.edit_pool, desktop_follow_run, job)
}

@(private = "file")
Desktop_Follow :: struct {
	app:        ^App,
	menu:       bool,
	autostart:  bool,
	integrated: bool,     // the worker's answer
	failed:     string,   // owned: what desktop.apply said went wrong
}

@(private = "file")
desktop_follow_run :: proc(data: rawptr) {
	job := (^Desktop_Follow)(data)
	o := integration_options()
	st := desktop.status(&o, context.temp_allocator)
	job.integrated = st.state != .Absent && st.error == .None && st.stale_exe == ""
	if job.integrated {
		o.add_to_path = st.parts[.Path].present
		o.start_menu, o.autostart = job.menu, job.autostart
		if r := desktop.apply(&o); r.error != .None {
			job.failed = fmt.aprintf("%s %s", desktop.error_text(r.error), r.detail)
		}
	}
	if !ui.post(&job.app.main.state, desktop_follow_done, job) {
		delete(job.failed)
		free(job)
	}
}

@(private = "file")
desktop_follow_done :: proc(data: rawptr, word: u64) {
	job := (^Desktop_Follow)(data)
	defer { delete(job.failed); free(job) }
	app := job.app
	names := [?]string{prefs_page.MENU_PREF, prefs_page.AUTOSTART_PREF}
	for name in names {
		if r := config.ref_of(&app.prefs, name); r != config.NO_REF { config.entry(&app.prefs, r).def.hidden = !job.integrated }
	}
	if job.failed != "" { say(app, i18n.tr("The desktop's launcher cannot be changed: %s"), job.failed) }
	app_frames(app)
}
