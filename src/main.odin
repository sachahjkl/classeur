// classeur: a file manager for Linux and Windows, on gui_toolkit. Tabs in panels, a list that reads a folder of a
// hundred thousand files without a wait, the keyboard for everything (a command palette), a preview.
package classeur

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "gt:process"
import setup "gt:setup"

APP_VERSION :: "0.20.1"
APP_NAME    :: "classeur"

USAGE :: `classeur: a file manager

  classeur [folder...]        a window on these folders (one tab each), or on your home folder; a running classeur
                              opens them in tabs
  classeur --window <folder>  a window of its own (a tab torn off), with no session
  classeur --setup            the window, the install's dialog open: install classeur for you, repair or upgrade the
                              install, or uninstall it (also in the settings: Installation)
  classeur --install          install this copy for you: the program, its launcher in the applications menu, its
                              icons, classeur on the PATH
  classeur --uninstall        take the install away (your settings stay)
  classeur --status           what is installed, and whether classeur runs (exit 0 installed, 2 to repair,
                              1 not installed)
  classeur version
  --pref name=value           a preference for this run only
`

main :: proc() {
	os.exit(run(os.args[1:]))
}

run :: proc(given: []string) -> int {
	// (--install, --uninstall and --status: no window; --setup: the window, the install's dialog open)
	cmd, args := setup.command_of(given)
	if setup.command_alone(cmd) { return setup.command_run(cmd, setup_options(), process.console_write) }
	folders := make([dynamic]string, context.temp_allocator)
	// (the toolkit's `--pref name=value`, as every program takes it: kept for the registry, which app_run makes, and
	// never read as a folder)
	pref_args := make([dynamic]string, context.temp_allocator)
	setup_asked, standalone := cmd == .Setup, false
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		if a == "--pref" && i + 1 < len(args) {
			append(&pref_args, a, args[i + 1])
			i += 1
			continue
		}
		if strings.has_prefix(a, "--pref=") {
			append(&pref_args, a)
			continue
		}
		switch a {
		case "--window":
			standalone = true
			continue
		case "version", "--version":
			fmt.printfln("classeur %s", APP_VERSION)
			return 0
		case "help", "-h", "--help":
			fmt.print(USAGE)
			return 0
		}
		// (absolute: a second start hands them to the first, which runs in another folder)
		abs, err := filepath.abs(a, context.temp_allocator)
		append(&folders, err == nil ? abs : a)
	}
	return app_run(folders[:], setup_asked, standalone, pref_args[:])
}
