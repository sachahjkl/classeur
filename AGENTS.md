# classeur

A file manager for Linux and Windows, in Odin, on the `ext/gui_toolkit` submodule (collection `gt`). Its model is File
Pilot (filepilot.tech): tabs in panels, a command palette, fast search, an inspector, keyboard first.

Read first: [README.md](README.md), [docs/architecture.md](docs/architecture.md), [docs/roadmap.md](docs/roadmap.md)
(what is done, what comes next, in order), [docs/development.md](docs/development.md).

## Build and test

Every step is a command of `tools/classeurtool` (`help` lists them):

    odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -keep-executable -- <command>

- `build [release]` builds `build/classeur` (`build.sh` / `build.bat` are shortcuts).
- `test`: the tests of `src` (the whole program with no window of the system), `src/fs` and the tool.
- `check`: `odin check -vet` (and `src/fs` for the other system), the tests, a release build.
- `shots` makes the README's pictures from `test_shots`, `logo` the logo.
- Linux: `nix develop` first (`flake.nix`).

## Rules

- Every action is a command of `src/commands.odin` (title, icon, keys) with its procedure in `src/actions.odin`: the
  keyboard, the palette and the menus read that table. No key is read elsewhere unless it moves in a list or a field.
- Nothing slow runs on the interface's thread: reading a folder, measuring, copying are tasks of the workers
  (`src/pool.odin`); their results come back with `ui.post`.
- The tests never touch the person's files or desktop: they make their folders with `testkit.temp_folder`, and
  `open_system` starts nothing when the program is headless.
- What more than one program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; classeur then
  points to the toolkit's new commit.
- Automation is a command of `tools/classeurtool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

## Pitfalls met

- `if !ui.row(...) { return }` closes the row at once (the scope of a deferred procedure is the `if`): build children
  inside `if ui.row(...) { ... }`.
- A test that calls the program's procedures sets `context.allocator = runtime.heap_allocator()` first: what the program
  keeps must come from its own allocator, not from the test's tracking one.
