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
- The command palette (Ctrl+K, Ctrl+Shift+P): every command, fuzzy, its keys shown.
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

### Layers 3 to 6: done so far

- Undo and redo (`src/undo.odin`): a stack of steps, each a list of (before, after) paths; the jobs record what they did
  (`Job.done`), renames go through free names in two steps, all or nothing; what an undo removes goes to the trash.
- GoTo (`src/goto.odin`): the folder a path names read on a worker, its folders found by the letters after the last
  separator; the recents, the bookmarks, the places by their path.
- Batch rename (`src/batch.odin`): a pattern with fields, find and replace, the case, names from the clipboard; the
  problems from the names read at the opening, never from the disk while typing.
- Drag and drop (`src/dnd.odin`): the system's (`platform.drag_start`, `drop_sync_set` for a drag of our own); the places
  that take a drop are noted each frame. Tabs dragged (`src/tab_drag.odin`); the rectangle selection (`src/band.odin`).
- The session (`src/session.odin`), one window per person (`gt:instance` `serve_start`), the types' popup, menus
  searched by typing (gui_toolkit's `ctx_menu_open(search)`), Open with, a terminal here (gui_toolkit's
  `desktop.open_terminal`), the system's icons (gui_toolkit's `desktop.file_icon`).
- The site (`site/`, `classeurtool site`, published by `.github/workflows/pages.yml` at classeur.froment.software).
- The settings on gui_toolkit's `prefs_page` (the rounding of the whole interface, the density, the animations, live
  sliders), updates by the toolkit's `update.Updater` (signed manifests in each release), the columns' filters, the
  icons as boxes, the sidebar's sections moved, tabs dragged with their feedback and torn off at the window's edge, the
  Windows icon and `classeur.com` (checked by the Windows CI).

### A pass of polish (0.16)

- The row's menu has every action of the row; the sidebar's rows have theirs; the trash puts back and empties.
- Back and Forward come back to the row and the scroll left (`Visit`, `src/tab.odin`); a refused rename keeps its name,
  Tab renames the next row; tabs too many for their row scroll, and a chevron lists them.
- Empty views say what to do (gui_toolkit's `ui.empty_state`); the questions are gui_toolkit's `ui.confirm` or laid out
  as it; the name taken shows both files.
- Short command titles with their words as tags, an icon each, the keyboard shortcuts on F1 (`ui.shortcuts_sheet`).
- F6 goes round the sidebar, the panels and the inspector; the list has the keys from the start; the letters go to the
  filter (`no_typeahead`).
- The jobs say their speed and the time left; cut rows are dimmed, pasted ones selected; the footer reads plainly.

## Next

5. The inspector: PDF and videos.
6. The thumbnails' cache on the disk, more formats.

## Debts

- The sessions of papier and classeur both have a shots command; papier's runs a headless sway, classeur's runs
  headless in a test. If papier moves to the headless test, nothing is left to share.
- Windows: the CI runs the tests and checks the icon and `classeur.com` there; a person's run found the Setup's
  "Repair" after an install (fixed in the toolkit). Drags between two real windows are tested by hand only.
