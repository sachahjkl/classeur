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

### Layer 2: change files (done but undo)

- A queue of jobs (`src/jobs.odin`): copy, move, trash, delete, one at a time on a thread of their own; progress in
  atomics shown in the status bar (files, bytes, the current name, a bar, a cancel). A copy counts first, then copies
  (`fs.copy_file`: `copy_file_range` on Linux, `CopyFileExW` on Windows; mode and times kept; a cancelled copy leaves
  nothing). A move is a rename on its volume, else a copy then the source removed. A folder onto a folder merges.
- A name taken asks (`src/dialogs.odin`): replace, skip, keep both ("name 2.ext"), the same for the next ones; the job
  waits on a semaphore for the answer. Pasted into the folder it comes from, a copy keeps both without asking.
- The clipboard of files: Ctrl+C, Ctrl+X, Ctrl+V; a cut is a move for every file manager (gui_toolkit's
  `files_cut` / `clipboard_files_cut`: `x-special/gnome-copied-files`, `application/x-kde-cutselection`, Windows'
  `Preferred DropEffect`). Copy and move to the other panel (palette).
- The trash: Delete. Linux: the freedesktop.org specification (home trash on its volume, else `<top>/.Trash-<uid>`,
  a `.trashinfo` taken with O_EXCL); Windows: the Recycle Bin. Shift+Delete deletes for good after a confirmation.
- The folders of every tab are watched (`fs.Watch`: inotify, change notifications on Windows; changes close together
  come as one) and read again with the cursor and the selection kept.
- The look: File Pilot's, faithfully. One row at the top (the sidebar's head, each panel's tabs over it, the window's
  buttons); the sidebar with its filter and its sections (Recents, Bookmarks, Storage with a bar of how full each volume
  is, Places with coloured icons); a toolbar (back, forward, up, the history, the lock, the bookmark, the path as words,
  the panel's menu); a box per row, filled icons (drawn yellow folders, coloured kinds, white pages); the columns Name,
  Modified (wide panels), Type, Folders, Files, Size; the selection solid blue; a footer per panel (the filter, the
  selected, the folders and files shown of all, how full the volume is). No status bar: messages are toasts.
- File Pilot's zoom (Ctrl+wheel over a panel, Ctrl+= and Ctrl+-, the percent in the footer): 0 % the details, 10 % the
  names alone, 20 % the names in columns, 30 % to 100 % cards ever larger. Its look: the selection a pill of the accent
  in from the sides, the cursor a ring, a thin line under each row, the columns' titles parted by lines, the footer's
  filter and counts in two boxes. The grid (Ctrl+2; Ctrl+1 the details): cards in rows of a virtual list, the arrows
  move card by card; thumbnails of PNG, JPEG and BMP decoded and shrunk (256 px) on a pool of their own, their
  textures kept for the 400 last used (`src/thumbs.odin`, `src/view_grid.odin`).
- Folder measures (`src/measure.odin`): the folders shown are measured all the way down on a pool of their own (2
  threads): their folders, files and bytes, kept by path and date; a navigation drops the measures not started.

## Next

### Layer 2: what is left

1. **Undo** (Ctrl+Z) of the last rename, move, new folder and trash: a stack of what was done, each with its inverse.
2. **A popover of the jobs** (a click on the status bar): every job, its errors, a retry.

### Layer 3: see inside

1. **The inspector** (File Pilot's Space and Ctrl+I): a pane at the right of the panel. A text file: its first 64 KB in
   the monospaced font; an image: decoded on a worker (PNG, JPEG, BMP by `core:image`; later WebP, AVIF), fitted; a
   folder: its listing; other files: their size, dates, type, permissions.
2. **Sort by the measures** (Size, Folders, Files on folders) and a bar in the size column (TreeSize's view) as an option.
3. **The thumbnails' cache on the disk** (`$XDG_CACHE_HOME/classeur`), more formats (WebP, GIF, AVIF, videos' frames),
   the cards' size with Ctrl+wheel (File Pilot's zoom).

### File Pilot's details still missing

- The context menu's search field at its top ("Select a system command...") and its icons; several keys per item.
- The tabs dragged to reorder them and to another panel; the panels split below as well as beside.
- Bookmarks and recents saved (layer 5).

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
- Windows: the code compiles (`odin check src/fs -target:windows_amd64`) but has not run on Windows yet. Run the tests
  there first.
