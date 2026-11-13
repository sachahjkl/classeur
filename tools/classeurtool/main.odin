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
import classeur_licence "../../src/licence"
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
		// (every icon is named by its lucide constant: the subset holds them all, and the program 900 KB less)
		features = {.Lucide_Subset},
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

// classeur's licences (docs/licence.md of gui_toolkit). DEV_SEED is the development pair's private half, public on
// purpose: the tests, the screenshots and the shop's sandbox; only a debug build of classeur accepts its licences
// (src/licence/product.odin holds its public half). The real pair is made once with `licence keygen`, out of any git
// work tree.
DEV_SEED :: "Y2xhc3NldXItZGV2LWxpY2VuY2Utc2VlZC0wMDAxISE"

LICENCE_TOOL :: toolbox.Licence_Tool{
	product  = classeur_licence.PRODUCT,
	dev_seed = DEV_SEED,
	hint     = "Open this file with classeur (Settings > General > Licence > Choose a file), or paste the key there.",
	paddle   = {name = "classeur licence", description = "A personal, perpetual licence of classeur that supports its work.", amounts = "supporter=2900", currency = "EUR"},
}

// The program's catalogues: the texts of its code (src and its packages), one file per language in i18n/.
I18N :: toolbox.I18n_Catalogues{dirs = {"src"}, folder = "i18n"}

// The commands (main_test checks them).
commands :: proc() -> []toolbox.Command {
	p := project()
	r := release.commands({project = p, dist = "build/dist", files = RELEASE_FILES[:], check = proc() -> int { return run_check(nil) }, update = classeur_update.PRODUCT})
	l := toolbox.licence_commands(LICENCE_TOOL)
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list,
		toolbox.Command{name = "build", usage = "[release]: the toolkit's text library when its sources changed, then build/classeur", run = run_build},
		toolbox.Command{name = "test", usage = "[names]: the tests of the program, of its packages and of this tool", run = run_test},
		toolbox.Command{name = "check", usage = ": the changelog, the scopes, odin check of the program for this system and for Windows (-vet), the tests, then a release build", run = run_check},
		toolbox.logo_command(logo()),
		r[0], r[1], r[2],
		toolbox.Command{name = "update", usage = "keygen <file> | pubkey | manifest <program> <version> - <out> | verify <manifest> -: classeur's update key and manifests", run = proc(args: []string) -> int { return toolbox.update_command(classeur_update.PRODUCT, args) }},
		changelog.command(p),
		toolbox.i18n_command(I18N),
		l[0], l[1],
		toolbox.Command{name = "shop", usage = ": the shop's six pages written into site/ from shop() (shop.odin): again after it changes", run = run_shop},
		tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]}, extra = site_downloads}),
		toolbox.Command{name = "timed", usage = ": the tests that measure time (opt-in: a loaded machine fails them for nothing)", run = run_timed},
		toolbox.Command{name = "shots", usage = "[--out folder]: the pictures of the README, the program's own frames with no window of the system", run = run_shots},
	)
	return list[:]
}

main :: proc() {
	toolbox.tool_main("classeurtool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
