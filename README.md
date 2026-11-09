<p align="center"><img src="assets/logo_128.png" width="96" alt="classeur logo"></p>

<h1 align="center">classeur</h1>

<p align="center"><b>A fast file manager for Linux and Windows.</b></p>

classeur shows your folders in tabs and panels, and does everything from the keyboard: a command palette, a filter as
you type, the path typed or clicked. It is one native program, written in [Odin](https://odin-lang.org) on
[gui_toolkit](https://github.com/sachahjkl/gui_toolkit), and its model is [File Pilot](https://filepilot.tech).

![classeur's window](docs/screenshots/main.png)

## Features

- **Fast**: a folder is read on worker threads with the system's fastest calls, and only the rows in view are built. The
  window never waits for the disk.
- **Tabs and panels**: tabs in each panel, panels side by side; open a folder in a new tab, in the other panel.
- **Command palette** (Ctrl+Shift+P): every action, found by a few letters, with its keys.
- **Filter** (Ctrl+F): the names that hold every word typed.
- **Natural order**: "photo 2" before "photo 10"; the case and the accents do not separate names.
- **Selection** with the mouse and the keyboard, kept through a sort, a filter and a refresh.
- **Rename in place** (F2), new folder (Ctrl+Shift+N), copy the paths (Ctrl+Shift+C).

| | |
|---|---|
| ![Two panels](docs/screenshots/panels.png) | ![The palette](docs/screenshots/palette.png) |
| Two panels | The command palette |

What comes next is in [docs/roadmap.md](docs/roadmap.md): copy, move and the trash with a queue of jobs, the inspector,
folder sizes, thumbnails, GoTo, the search of a whole volume.

## Keys

| Key | |
|---|---|
| Enter, double click | open |
| Backspace, Alt+Up | the parent folder |
| Alt+Left, Alt+Right | back, forward |
| Ctrl+L | type a path |
| Ctrl+F | filter |
| Ctrl+T, Ctrl+W, Ctrl+Shift+T | new tab, close it, open it again |
| Ctrl+Enter | the folder in a new tab |
| Ctrl+Shift+D, F6 | a new panel, the next panel |
| F2 | rename |
| Ctrl+Shift+N | new folder |
| Ctrl+H | hidden files |
| Ctrl+Shift+P, F1 | the command palette |

## Build

```sh
git clone --recurse-submodules https://github.com/sachahjkl/classeur && cd classeur
nix develop
./build.sh release      # build/classeur
```

Every step of the project is a command of `tools/classeurtool`: see [docs/development.md](docs/development.md).

## Licence

MIT, see [LICENSE](LICENSE). Icons: [Lucide](https://lucide.dev), ISC.
