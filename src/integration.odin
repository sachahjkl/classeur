package classeur

// classeur on the user's desktop (gui_toolkit's desktop and setup): a launcher in the application menu with its icons,
// classeur on the PATH, "Open folders with classeur" in the menus that offer it. Everything in the user's profile.
//
//   classeur install [--no-path]   the running copy integrated where it is (a build, a Nix profile's)
//   classeur uninstall             the integration taken away
//   classeur status                what is installed
//   classeur --setup               the Setup: the copy installed in a folder of its own, repaired, upgraded, uninstalled
//
// On Windows a copy that is not installed offers the Setup at its start, once per version unless the person keeps it
// standalone; on Linux `classeur install` integrates the copy where it is, and Nix installs it.

import "core:fmt"
import "core:os"
import "core:strings"
import desktop "gt:desktop"
import "gt:platform"
import "gt:process"
import "gt:render"
import setup "gt:setup"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

classeur_identity :: proc() -> desktop.Identity {
	return desktop.Identity{
		name = "Classeur", key = "Classeur", slug = APP_NAME, aumid = "FromentSoftware.Classeur",
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

// classeur's own parts of an install: the PATH.
classeur_parts :: proc(o: ^desktop.Options) {
	o.add_to_path = true
}

@(private = "file")
integration_options :: proc(args: []string) -> desktop.Options {
	o := desktop.options_make(classeur_identity())
	o.exe = process.executable_path()
	o.icons = ICON_PNGS[:]
	classeur_parts(&o)
	for a in args { if a == "--no-path" { o.add_to_path = false } }
	desktop.roots_from_env(&o, proc(name: string) -> string { return os.get_env(name, context.temp_allocator) })
	return o
}

cmd_install :: proc(args: []string) -> int {
	o := integration_options(args)
	if r := desktop.install(&o); r.error != .None {
		fmt.eprintfln("classeur: %s %s", desktop.error_text(r.error), r.detail)
		return 1
	}
	fmt.printfln("classeur: installed for %s (%s)", o.exe, desktop.targets(false))
	return 0
}

cmd_uninstall :: proc(args: []string) -> int {
	o := integration_options(args)
	if r := desktop.remove(&o); r.error != .None {
		fmt.eprintfln("classeur: %s %s", desktop.error_text(r.error), r.detail)
		return 1
	}
	fmt.println("classeur: the launcher, the icons and the link are gone")
	return 0
}

cmd_status :: proc(args: []string) -> int {
	o := integration_options(args)
	s := desktop.status(&o)
	defer desktop.status_destroy(&s)
	fmt.printfln("%s", desktop.describe(&s))
	for part in s.wanted {
		ps := s.parts[part]
		state := ps.present ? (ps.stale ? "points to another program" : ps.partial ? "incomplete" : "present") : "absent"
		fmt.printfln("  %v: %s", part, state)
	}
	return s.state == .Installed ? 0 : 1
}

////////////////////////////////
// The Setup (a window of its own over the page)

setup_config :: proc() -> setup.Config {
	return setup.Config{
		identity = classeur_identity(), version = APP_VERSION, install_folder = APP_NAME, icons = ICON_PNGS[:],
		choices = SETUP_CHOICES[:], square = true,
		prepare = proc(o: ^desktop.Options, choices: []bool, user: rawptr) {
			classeur_parts(o)
			if len(choices) == len(SETUP_CHOICES) { o.add_to_path = choices[0] }
		},
	}
}

@(private = "file", rodata)
SETUP_CHOICES := [?]setup.Choice{
	{label = "classeur in the terminal (on the PATH)", on = true},
}

// What the person answered the Setup (setup.CHOICE_*), kept in <config>/classeur/setup.
@(private = "file")
setup_choice_file :: proc() -> string {
	return strings.concatenate({platform.config_dir(context.temp_allocator), "/", APP_NAME, "/setup"}, context.temp_allocator)
}

@(private = "file")
setup_choice_read :: proc() -> string {
	data, err := os.read_entire_file(setup_choice_file(), context.temp_allocator)
	return err == nil ? strings.trim_space(string(data)) : ""
}

@(private = "file")
setup_choice_write :: proc(choice: string) {
	path := setup_choice_file()
	_ = os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	_ = os.write_entire_file(path, transmute([]u8)choice)
}

// At a start with the window: the Setup when there is something to do (Windows), unless the person answered for this
// version or keeps this copy standalone; `asked`: classeur --setup.
setup_offer :: proc(app: ^App, asked: bool) {
	if app.headless { return }
	if asked {
		setup.open(&app.setup, setup_config())
		return
	}
	when ODIN_OS == .Windows {
		if setup.wanted(setup.facts(setup_config()), APP_VERSION, setup_choice_read()) { setup.open(&app.setup, setup_config()) }
	}
}

act_setup :: proc(app: ^App) { setup.open(&app.setup, setup_config()) }

setup_build :: proc(app: ^App, em: f32) {
	if !app.setup.open { return }
	if !app.logo_made {
		img, ok := platform.clipboard_image_decode("image/png", ICON_PNGS[3].png, context.temp_allocator)
		if ok {
			app.logo = render.create_texture_rgba(&app.shared.r, img.size.x, img.size.y)
			render.update_texture_rgba(&app.shared.r, app.logo, 0, 0, img.size.x, img.size.y, img.rgba)
			app.logo_made = true
		}
	}
	logo: Maybe(setup.Logo)
	if app.logo_made { logo = setup.Logo{app.logo, {128, 128}} }
	switch setup.dialog(&app.setup, setup_config(), em, logo) {
	case .Installed:       setup_choice_write(setup.CHOICE_INSTALLED)
	case .Kept_Standalone: setup_choice_write(setup.CHOICE_STANDALONE)
	case .Dismissed:       setup_choice_write(setup.choice_dismissed(APP_VERSION))
	case .Launched:
		// (the installed copy starts once this one has ended: app_run's end)
		delete(app.launch_after)
		app.launch_after = strings.clone(app.setup.installed)
		platform.request_close(app.main.win)
	case .Uninstalled, .None:
	}
}
