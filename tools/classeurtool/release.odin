package classeurtool

// A release (gui_toolkit's release package): `package [version]` the archive of the release build and its SHA-256,
// `notes <version>` the changelog's section, `ship <version> [--dry-run]` the changelog dated, APP_VERSION set, the
// checks, a commit, the tag, the push. The release workflow (.github/workflows/release.yml) builds and publishes a tag.

import "core:os"
import release "gt:release"
import classeur_update "../../src/update"

@(private = "file")
release_config :: proc() -> release.Config {
	@(static) files := [?][2]string{
		{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"},
		{"ext/gui_toolkit/src/lucide/LICENSE.txt", "LUCIDE-LICENSE.txt"},
	}
	return release.Config{
		name = "classeur", repository = REPOSITORY, changelog = CHANGELOG,
		version_file = "src/main.odin", version_line = "APP_VERSION :: ",
		program = PROGRAM, dist = "build/dist", files = files[:], check = proc() -> int { return run_check(nil) },
		update = classeur_update.PRODUCT,
	}
}

run_package :: proc(args: []string) -> int { return release.package_(release_config(), args) }
run_notes :: proc(args: []string) -> int { return release.notes(release_config(), args) }
run_ship :: proc(args: []string) -> int { return release.ship(release_config(), args) }

// The version src/main.odin says (APP_VERSION), "" when it cannot be read.
app_version :: proc() -> string {
	source, err := os.read_entire_file("src/main.odin", context.temp_allocator)
	return err == nil ? release.version_of(string(source), "APP_VERSION :: ") : ""
}
