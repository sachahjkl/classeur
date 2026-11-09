// classeur: a file manager for Linux and Windows, on gui_toolkit. Tabs in panels, a list that reads a folder of a
// hundred thousand files without a wait, the keyboard for everything (a command palette), a preview.
package classeur

import "core:fmt"
import "core:os"
import "core:path/filepath"

APP_VERSION :: "0.1.0"
APP_NAME    :: "classeur"

USAGE :: `classeur: a file manager

  classeur [folder...]        a window on these folders (one tab each), or on your home folder
  classeur version
`

main :: proc() {
	os.exit(run(os.args[1:]))
}

run :: proc(args: []string) -> int {
	folders := make([dynamic]string, context.temp_allocator)
	for a in args {
		switch a {
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
	return app_run(folders[:])
}
