// classeurtool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package classeurtool

import changelog "gt:changelog"
import release "gt:release"
import tk_site "gt:site"
import toolbox "gt:toolbox"
import classeur_update "../../src/update"

REPOSITORY :: "https://github.com/sachahjkl/classeur"
when ODIN_OS == .Windows {
	PROGRAM :: "build/classeur.exe"
} else {
	PROGRAM :: "build/classeur"
}

// What classeur is to its tool and to the toolkit's standard commands. classeur.com is the console launcher classeur
// embeds (src/system_windows.odin): a folder (or none) opens a window and gives the prompt back; a command waits and
// gives its output and exit code through.
project :: proc() -> toolbox.Project {
	return {
		name = "classeur", repository = REPOSITORY, changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = PROGRAM,
		launcher = {out = "build/classeur.com", mark = "(classeur console launcher)", default_rule = "detach",
		            others = "install,uninstall,status,version,--version,help,-h,--help"},
	}
}

// What goes beside the program in a release's archive.
@(rodata)
RELEASE_FILES := [?][2]string{
	{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"},
	{"ext/gui_toolkit/src/lucide/LICENSE.txt", "LUCIDE-LICENSE.txt"},
}

// The commands (main_test checks them).
commands :: proc() -> []toolbox.Command {
	p := project()
	r := release.commands({project = p, dist = "build/dist", files = RELEASE_FILES[:], check = proc() -> int { return run_check(nil) }, update = classeur_update.PRODUCT})
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list,
		toolbox.Command{name = "build", usage = "[release]: the toolkit's text library when its sources changed, then build/classeur", run = run_build},
		toolbox.Command{name = "test", usage = "[names]: the tests of the program, of its packages and of this tool", run = run_test},
		toolbox.Command{name = "check", usage = ": the changelog, the scopes, odin check of the program for this system and for Windows (-vet), the tests, then a release build", run = run_check},
		toolbox.logo_command(logo()),
		r[0], r[1], r[2],
		toolbox.Command{name = "update", usage = "keygen <file> | pubkey | manifest <program> <version> - <out> | verify <manifest> -: classeur's update key and manifests", run = proc(args: []string) -> int { return toolbox.update_command(classeur_update.PRODUCT, args) }},
		changelog.command(p),
		tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]}, extra = site_downloads}),
		toolbox.Command{name = "timed", usage = ": the tests that measure time (opt-in: a loaded machine fails them for nothing)", run = run_timed},
		toolbox.Command{name = "shots", usage = "[--out folder]: the pictures of the README, the program's own frames with no window of the system", run = run_shots},
	)
	return list[:]
}

main :: proc() {
	toolbox.tool_main("classeurtool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
