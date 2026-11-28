package classeur

// classeur on the user's desktop (gui_toolkit's desktop and setup, through prefs_page.Install): the copy installed in a
// folder of its own with a launcher in the application menu and its icons, classeur on the PATH, "Open folders with
// classeur" in the menus that offer it, and on request classeur in place of the system's file manager (Windows: the
// folders, the drives and Win+E). Everything in the user's profile. The settings' Installation page shows the install
// and acts on it.
//
//   classeur --install     this copy installed for the user (no window)
//   classeur --uninstall   the install taken away; the settings stay (no window)
//   classeur --status      what is installed, and whether classeur runs (no window)
//   classeur --setup       the window, the install's dialog open
//
// On Windows a copy that is not installed offers the install at its start, once per version unless the person keeps it
// standalone; on Linux Nix installs it, or `classeur --install`.

import "base:runtime"
import "core:os"
import "core:sync"
import desktop "gt:desktop"
import "gt:i18n"
import setup "gt:setup"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

// The identity's derived strings are allocated: they are made once, for the whole run (the workers and the setup's jobs
// share them).
@(private = "file") identity: desktop.Identity
@(private = "file") identity_once: sync.Once

classeur_identity :: proc() -> desktop.Identity {
	sync.once_do(&identity_once, proc() {
		id := desktop.identity_of("Froment Software", APP_TITLE, APP_NAME, runtime.heap_allocator())
		id.description = "File manager"
		id.generic_name, id.categories = "File Manager", "System;FileTools;FileManager;Utility;Core;"
		id.keywords = "folder;manager;explore;disk;filesystem;files;"
		id.uninstall_arguments = "--setup"
		identity = id
	})
	return identity
}

// classeur's own parts of an install: the PATH (on Windows with classeur.com, the console launcher the toolkit's build
// embeds: `classeur` typed in cmd or PowerShell gives its output and exit code).
classeur_parts :: proc(o: ^desktop.Integration_Options) {
	o.add_to_path = true
}

// (the places of a test come from the environment: CLASSEUR_DESKTOP_*)
@(private = "file")
env_lookup :: proc(name: string) -> string { return os.get_env(name, context.temp_allocator) }

////////////////////////////////
// The install (prefs_page.Install: the offer, the dialog, the settings' Installation page)

setup_options :: proc() -> setup.Setup_Options {
	return setup.Setup_Options{
		identity = classeur_identity(), version = APP_VERSION, icons = ICON_PNGS[:],
		vendor_url = "https://froment.software",
		choices = SETUP_CHOICES[:], square = true, running = app_running, quit = app_quit,
		prepare = proc(o: ^desktop.Integration_Options, choices: []bool, user: rawptr) {
			classeur_parts(o)
			if len(choices) == len(SETUP_CHOICES) { o.add_to_path, o.default_file_manager = choices[0], choices[1] }
			desktop.roots_from_env(o, env_lookup)   // (a test's places: nothing of the person's)
		},
	}
}

// (not rodata: i18n.later marks the labels for the catalogue; tr where they are shown)
// Each box is tied to its part: with an install there, it shows what the system has (a default file manager another
// program took back shows unticked), and what is ticked is what Install writes. The second box's words are the system's
// (SETUP_FILE_MANAGER_WORDS, system_<os>.odin).
@(private = "file")
SETUP_CHOICES := [?]setup.Choice{
	{label = i18n.later("Classeur in the terminal (on the PATH)"), on = true, parts = {.Path}},
	{label = SETUP_FILE_MANAGER_WORDS, on = false, parts = {.File_Manager}},
}

