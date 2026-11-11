// classeur: a file manager for Linux and Windows, on gui_toolkit. Tabs in panels, a list that reads a folder of a
// hundred thousand files without a wait, the keyboard for everything (a command palette), a preview.
package classeur

import "core:fmt"
import "core:os"
import "core:path/filepath"

APP_VERSION :: "0.15.1"
APP_NAME    :: "classeur"

USAGE :: `classeur: a file manager

  classeur [folder...]        a window on these folders (one tab each), or on your home folder; a running classeur
                              opens them in tabs
  classeur --window <folder>  a window of its own (a tab torn off), with no session
  classeur --setup            install classeur for you, repair or upgrade the install, or uninstall it
  classeur install [--no-path]
                              the launcher in the applications menu, the icons, classeur on the PATH
  classeur uninstall          take them away
  classeur status             what is installed
  classeur version
`

main :: proc() {
	os.exit(run(os.args[1:]))
}

run :: proc(args: []string) -> int {
	if len(args) > 0 {
		switch args[0] {
		case "install":   return cmd_install(args[1:])
		case "uninstall": return cmd_uninstall(args[1:])
		case "status":    return cmd_status(args[1:])
		}
	}
	folders := make([dynamic]string, context.temp_allocator)
	setup_asked, standalone := false, false
	for a in args {
		switch a {
		case "--setup":
			setup_asked = true
			continue
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
	return app_run(folders[:], setup_asked, standalone)
}
