# Roadmap

classeur is built in layers: each layer adds to a program that works. Its model is File Pilot (filepilot.tech): copy its
behaviour where it is good, with no shame; keep the program fast (a folder of 100 000 files must read and scroll without
a wait) and the same on Linux and Windows.

The state of each item: done, in progress, or next. Work from the top of "Next". When an item is done, move it to "Done"
with one line on how it is made, and update [architecture.md](architecture.md).

## Done

### Layer 1: browse

- Read a folder on the workers (`fs.list`: getdents64 + statx on Linux, FindFirstFileExW on Windows); the answer through
  `ui.post`; only the last read asked counts.
- The details view: icon, name, date (local time), type, size; a virtual list (only the rows in view are built).
- Sort by name (natural, case and accents ignored), date, size, type; folders first or mixed; a click on a column.
- The filter of a folder (Ctrl+F): every word in the name; Enter opens the first row, Up and Down move from the field.
- Selection: click, Ctrl+click, Shift+click, Shift+arrows, Ctrl+A, Ctrl+Shift+A, Ctrl+I, Ctrl+Space. It survives a sort,
  a filter and a refresh (by name).
- Navigation: Enter, double click, Backspace and Alt+Up (the cursor on the folder we came from), Alt+Left, Alt+Right,
  Alt+Home, the crumbs (Home and its folders under the home folder; the first crumbs go when the room is short), the
  path typed (Ctrl+L; a file's path opens its folder with the file at the cursor).
- Tabs per panel: Ctrl+T, Ctrl+W, Ctrl+Shift+T (reopen), Ctrl+Tab, Ctrl+Shift+K (duplicate), Ctrl+Enter and a middle
  click (a folder in a new tab), a middle click on a tab closes it.
- Panels side by side: Ctrl+Shift+D (split), Ctrl+Shift+W, F6 (the next panel), Shift+Enter (open in the other panel).
- The command palette (Ctrl+Shift+P, F1): every command, fuzzy, its keys shown.
- Rename in place (F2: the name without its extension selected), new folder (Ctrl+Shift+N, then named in place),
  copy the paths (Ctrl+Shift+C), open with the system's application.
- The sidebar: the person's folders, the volumes (Linux: the root and /media, /run/media, /mnt; Windows: the drives).
- The free space of the volume, the time a read took.
- Tests of the whole program with no window of the system (`src/app_test.odin`), the README's pictures from a test.

## Next

### Layer 2: change files

1. **A queue of jobs** (`src/jobs.odin`): copy, move, delete, on a thread of their own, one at a time, with their
   progress (bytes, files, the current name), a pause and a cancel; shown in the status bar and in a popover of the
   jobs. A job reads what it must do (the sources, the destination) when it starts, and asks the interface (a post) when
   a name is already there: replace, skip, keep both ("name (2).ext"), the same for every next conflict.
2. **The clipboard of files**: Ctrl+C and Ctrl+X put the selection on the system's clipboard
   (`platform.clipboard_set_files`; a cut is marked for the file managers: `x-special/gnome-copied-files`, Windows'
   `Preferred DropEffect`), Ctrl+V pastes what is there into the folder (a copy, or a move after a cut).
3. **Delete**: Delete sends to the trash (Linux: the freedesktop.org trash specification, `$XDG_DATA_HOME/Trash` or the
   volume's `.Trash-$uid`, with its `.trashinfo`; Windows: `IFileOperation` with `FOFX_RECYCLEONDELETE`); Shift+Delete
   deletes for good after a confirmation dialog.
4. **Undo** (Ctrl+Z) of the last rename, move, new folder and trash.
5. **Watch the folders shown** (inotify on Linux, `ReadDirectoryChangesW` on Windows, on a thread): a change in a
   folder shown reads it again (at most every 200 ms), and keeps the cursor and the selection.

### Layer 3: see inside

1. **The inspector** (File Pilot's Space and Ctrl+I): a pane at the right of the panel. A text file: its first 64 KB in
   the monospaced font; an image: decoded on a worker (PNG, JPEG, BMP by `core:image`; later WebP, AVIF), fitted; a
   folder: its listing; other files: their size, dates, type, permissions.
2. **Folder sizes**: measured on the workers for the folders shown (an option: always, on demand with a command), the
   column shows them as they come; a bar in the size column (TreeSize's view) as an option.
3. **The grid view** with thumbnails (Ctrl+1 details, Ctrl+2 list, Ctrl+3 grid), the thumbnails made on the workers and
   kept in a cache on the disk (`$XDG_CACHE_HOME/classeur`).

### Layer 4: find

1. **GoTo** (Ctrl+G, and a click on the empty part of the crumbs): a field with completion from the folders of the path
   typed, the recent folders, the places; fuzzy.
2. **The flat search** (Ctrl+Shift+F): every file under the folder (a whole volume), read on the workers in parallel,
   shown as it comes in the same list with a path column, fuzzy, filtered by extension.
3. **Recent folders** and **bookmarks** (Ctrl+D) in the sidebar, saved.

### Layer 5: keep it the person's

1. **Preferences** with gui_toolkit's `config` and `prefs_page` (Ctrl+,): theme, mode, density, font size, folders first,
   hidden files, date format, single click to open, what Space does.
2. **The session**: the tabs and panels again at the next start; **layouts** saved by name.
3. **Keys of one's own**: in the palette, a key for any command (saved in the preferences).
4. **One window per process** (`gt:instance`): a second `classeur <folder>` opens a tab in the running one.

### Layer 6: more

- Drag and drop: rows to a folder, to another panel, to a tab, to the sidebar; to and from other programs
  (`platform.drag_start`, `drop_target_enable`).
- Batch rename (File Pilot's): a text with the names, one per line, edited; numbers and dates as fields.
- "Open with" (`gt:desktop`'s handlers), open a terminal here, the properties of a file.
- Archives as folders (zip, tar), read only.
- The site (gui_toolkit's `site`), the release (`classeurtool ship`, as papier's), the package for Windows (`gt:setup`).

## Debts

- The sessions of papier and classeur both have a shots command; papier's runs a headless sway, classeur's runs
  headless in a test. If papier moves to the headless test, nothing is left to share.
- gui_toolkit: classeur points to a local commit of the toolkit (`lucide`: the icons classeur draws). Push it and tag a
  release, then point the submodule to the tag.
