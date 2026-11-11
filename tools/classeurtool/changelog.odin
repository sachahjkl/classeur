package classeurtool

// The changelog's fragments (the toolkit's changelog package): a change a person sees adds one file to changelog.d/, and
// `ship` assembles them into the version's section of CHANGELOG.md.
//   changelog new <type> <subject> <text>   writes changelog.d/<yyyyMMdd-HHmmss>-<subject>.md
//   changelog check                         every fragment well formed, the version as the last release says (check runs it)

import "core:fmt"
import changelog "gt:changelog"

changelog_options :: proc() -> changelog.Options {
	return {link = REPOSITORY + "/releases/tag/v%s", version = proc(root: string) -> string { return app_version() }}
}

run_changelog :: proc(args: []string) -> int {
	if len(args) == 4 && args[0] == "new" {
		path, why := changelog.new_fragment("", args[1], args[2], args[3])
		if why != "" {
			fmt.eprintln("changelog:", why)
			return 1
		}
		fmt.println(path)
		return 0
	}
	if len(args) == 1 && args[0] == "check" { return changelog_check() ? 0 : 1 }
	fmt.eprintln("changelog new <Added|Changed|Deprecated|Removed|Fixed|Security> <subject> <text> | check")
	return 1
}

changelog_check :: proc() -> bool {
	errors, n := changelog.check(changelog_options())
	for e in errors { fmt.eprintln("changelog:", e) }
	if len(errors) == 0 { fmt.printfln("changelog: %d fragments, all well formed", n) }
	return len(errors) == 0
}
