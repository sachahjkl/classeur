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

Every step is a command of `tools/classeurtool`:

| Command | |
|---|---|
| `build [release]` | the toolkit's text library when its sources changed (Linux), then `build/classeur` |
| `test` | `src` (the whole program, no window of the system: `-define:ODIN_TEST_THREADS=1`), `src/fs`, the tool |
| `check` | `odin check -vet` of the program, of `src/fs` for the other system and of the tool, the tests, a release build |
| `logo` | `assets/logo*.png` and `.project/image.png`, drawn by gui_toolkit's `paint` |
| `shots [--out folder]` | `docs/screenshots/*.png`, from `test_shots` in `src/app_test.odin` |

## Tests

A test of the program opens it headless and drives it as a person would (`src/app_test.odin`). Its folders are made with
`testkit.temp_folder`; it waits for the workers with `wait_read`. What a failing test left (its last frame and its box
tree) is in `build/session/<test>/`.

One test alone:

```sh
odin test src -collection:gt=ext/gui_toolkit/src -vet -define:FONT_BACKEND=native \
  -extra-linker-flags:-Wl,--allow-multiple-definition -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=classeur.test_browse
```
