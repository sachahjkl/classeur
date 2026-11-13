# Development

## Build

```sh
git clone --recurse-submodules https://github.com/sachahjkl/classeur && cd classeur
nix develop
./build.sh            # build/classeur, debug
./build.sh release    # build/classeur, optimized
build/classeur ~/Downloads ~/Pictures
```

On Windows: Odin `dev-2026-11a` (`odin.version`) and MSVC, then `build.bat`.

## classeurtool

Every step is a command of `tools/classeurtool`, a list of the toolkit's `toolbox.Command`s (gui_toolkit
`docs/toolbox.md`):

| Command | |
|---|---|
| `build [release]` | the toolkit's text library when its sources changed (Linux); Windows: `build/classeur.com` (the console launcher, which classeur embeds) and the icon of `res/classeur.rc`; then `build/classeur` |
| `test` | `src` (the whole program, no window of the system: `-define:ODIN_TEST_THREADS=1`), `src/fs`, the tool |
| `check` | the changelog's fragments, the scopes (`toolbox.check_scopes`), `ODIN_OS` out of the interface, `odin check -vet` of the program for this system and for Windows (from Linux too: `toolbox.check_windows`), of the tool, the tests, a release build; Windows: `classeur.com version` gives classeur's output, `classeur.exe` has its icon |
| `logo` | `assets/logo*.png`, `assets/classeur.ico` (the exe's icon) and `.project/image.png`, drawn by gui_toolkit's `paint` |
| `changelog new <type> <text> -subject:<subject>` / `check` / `preview` | the fragments of `changelog.d/` |
| `package`, `notes <version>`, `ship <patch\|minor\|major\|x.y.z> [--dry-run]` | a release (gui_toolkit's `release.commands`) |
| `site build <site> <out>` / `check` / `card` | the site (gui_toolkit's `site.command`) |
| `shots [--out folder]` | `docs/screenshots/*.png`, from `test_shots` in `src/app_test.odin` |
| `timed` | the tests that measure time (`TIMED_TESTS`, `-define:CLASSEUR_TIMED=true`): opt-in, a loaded machine fails them for nothing |

## Tests

A test of the program opens it headless and drives it as a person would (`src/app_test.odin`). Its folders are made with
`testkit.temp_folder`; it waits for the workers with `wait_read`. What a failing test left (its last frame and its box
tree) is in `build/session/<test>/`.

One test alone:

```sh
odin test src -collection:gt=ext/gui_toolkit/src -vet -define:FONT_BACKEND=native \
  -extra-linker-flags:-Wl,--allow-multiple-definition -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=classeur.test_browse
```
