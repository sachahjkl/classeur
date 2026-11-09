// classeurtool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package classeurtool

import "core:fmt"
import "core:os"
import "core:strings"
import toolbox "gt:toolbox"

EXIT_USAGE :: 2
ROOT_MARK  :: "odin.version"

Command :: struct {
	name, about: string,
	run:         proc(args: []string) -> int,
}

COMMANDS :: [?]Command{
	{name = "build", about = "[release]: the toolkit's text library when its sources changed, then build/classeur", run = run_build},
	{name = "test", about = "the tests of the program, of its packages and of this tool", run = run_test},
	{name = "check", about = "odin check of the program for this system and for Windows (-vet), the tests, then a release build", run = run_check},
	{name = "logo", about = "assets/logo*.png, drawn by the toolkit's paint package", run = run_logo},
	{name = "shots", about = "[--out folder]: the pictures of the README, the program's own frames with no window of the system", run = run_shots},
}

main :: proc() {
	if len(os.args) < 2 || os.args[1] == "help" || os.args[1] == "-h" || os.args[1] == "--help" { usage(); return }
	if !os.exists(ROOT_MARK) {
		root, code := toolbox.capture({"git", "rev-parse", "--show-toplevel"})
		if code != 0 { fmt.eprintln("classeurtool: not in the repository"); os.exit(EXIT_USAGE) }
		if os.set_working_directory(strings.trim_space(root)) != nil { fmt.eprintfln("classeurtool: cannot work in %s", root); os.exit(EXIT_USAGE) }
	}
	commands := COMMANDS
	for c in commands {
		if c.name == os.args[1] { os.exit(c.run(os.args[2:])) }
	}
	fmt.eprintfln("classeurtool: no command %s", os.args[1])
	usage()
	os.exit(EXIT_USAGE)
}

usage :: proc() {
	fmt.println("classeurtool <command> [arguments]")
	commands := COMMANDS
	for c in commands { fmt.printfln("  %-8s %s", c.name, c.about) }
}
