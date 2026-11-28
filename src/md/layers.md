# The layers

classeur is built in layers: each layer adds to a program that works. Its model is File Pilot (filepilot.tech): copy its
behaviour where it is good, with no shame. Two constraints hold for every layer:

- A folder of 100 000 files must read and scroll without a wait.
- The program is the same on Linux and Windows.

This file keeps, per layer, the decisions that the code does not explain. The planned work is in
[ROADMAP.md](../../ROADMAP.md); the map of the code is [docs/architecture.md](../../docs/architecture.md).

## Layer 1: browse

- A folder is read on the workers (`fs.list`: getdents64 + statx on Linux, FindFirstFileExW on Windows); the answer
  comes through `ui.post`; only the last read asked counts.
- The details view is a virtual list: only the rows in view are built.
- The natural sort: digits by value, case and Latin accents ignored.
- The selection survives a sort, a filter and a refresh: it is a flag per entry, and a new listing gets it back by name.
- Backspace and Alt+Up put the cursor on the folder we came from. A typed path that names a file opens its folder with the
  file at the cursor.
- The crumbs start at Home under the home folder; the first crumbs go when the room is short. The room is reckoned
  with each crumb's button as the toolkit lays it out (`ui.button_width`) and its chevron, and a last name wider than
  the row alone is cut with "…": the empty part at the end always stays, as it is what a click turns into the path
  field. The text and 2 em ran short by half an em a crumb, and on a deep path the crumbs covered the empty part.
  Refused: the width of the last layout. A crumb cut there measures short, the next build does not cut it, and the
  name flickers between whole and cut at each frame.
- The tests drive the whole program with no window of the system (`src/app_test.odin`); the README's pictures come from a
  test.

## Layer 2: change files

- **Jobs.** Copy, move, trash, delete run one at a time on a thread of their own (`src/jobs.odin`); progress is in
  atomics. A copy counts first, then copies. A cancelled copy leaves nothing. A move is a rename on its volume, else a
  copy then the source removed. A folder onto a folder merges.
- **A name taken** asks (`src/dialogs.odin`): replace, skip, keep both ("name 2.ext"), the same for the next ones; the job
  waits on a semaphore for the answer. Pasted into the folder it comes from, a copy keeps both without asking.
- **The clipboard of files.** A cut is a move for every file manager: gui_toolkit's `files_cut` writes
  `x-special/gnome-copied-files`, `application/x-kde-cutselection` and Windows' `Preferred DropEffect`. A paste asks
  with `platform.clipboard_request` and starts its job when the files come: a program that holds the clipboard and does
  not answer never freezes the window.
- **The trash.** Linux: the freedesktop.org specification (home trash on its volume, else `<top>/.Trash-<uid>`, a
  `.trashinfo` taken with `O_EXCL`). Windows: the Recycle Bin. Shift+Delete deletes for good after a confirmation.
  - Undo needs the item's place in the Recycle Bin, its `$R` file. On Windows, `IFileOperation` gives it to the sink of
    the delete (`PostDeleteItem`, its new item). Refused: the search of the `$I` records written since the trash began,
    by path and date. A clock or a timestamp off by a moment, or a record not yet seen, lost it now and then. The
    trash then left no undo step, and each Ctrl+Z after it undid a step older than the one the person meant.
  - An item that the shell deletes for good (a drive without a Recycle Bin) has no new item: no undo step.
- **Watching.** Changes close together come as one; a folder read again keeps its cursor and its selection.
- **The look** is File Pilot's, faithfully. No status bar: messages are toasts. The zoom goes from the details (0 %) to
  names alone (10 %), names in columns (20 %), then cards ever larger (30 % to 100 %).
- **Thumbnails** are decoded and shrunk to 256 px on a pool of their own; the 400 last used are kept. See "The
  thumbnails" below: the cache is the toolkit's now.
- **Folder measures** run on a pool of their own (2 threads), kept by path and date; a navigation drops the measures not
  started.

## Layers 3 to 6

- **Undo and redo** (`src/undo.odin`): a stack of steps, each a list of (before, after) paths. The jobs record what they
  did (`Job.done`). Renames go through free names in two steps, all or nothing. What
  an undo removes goes to the trash, never deleted for good.
- **GoTo** (`src/goto.odin`): the folder a path names is read on a worker; its folders are found by the letters after the
  last separator.
- **Batch rename** (`src/batch.odin`): the problems come from the names read at the opening, never from the disk while
  typing.
- **Drag and drop** (`src/dnd.odin`): the places that take a drop are noted each frame. Tabs dragged and torn off at the
  window's edge (`src/tab_drag.odin`); the rectangle selection (`src/band.odin`).
- **What the toolkit now holds.** gui_toolkit 0.329 took classeur's file view into its table (its
  `src/md/features/view-modes.md`). Classeur keeps its own model (tabs, groups, the tree, its look, its drag and drop),
  so its grid and its columns view stay its own, but it no longer keeps copies of what the toolkit has:
  - the rectangle is `ui.Item_Band`. `src/band.odin` adds only what the folder has and the toolkit's band does not
    know: one band for the window (`Band.tab`: the other panels' lists are left alone while it runs), the folder's menu
    on a right click in the empty part, and the selection's bytes kept row by row through `Item_Band.changed` (a count
    over the folder at each frame of a drag was refused). Escape gives the selection back (`item_band_cancel`).
    In Details and List a press on the empty part of a row (after the name's text, between the cells) waits
    (`Item_Band.pending`): past the drag threshold it is a rectangle, let go before it is a click that picks the row. A
    press on the name or the icon drags the files. A full list would otherwise have no place to start a rectangle; half
    a row of empty space stays at its end too (`Virtual_List.end_space`). A pending press is a gesture: no file is
    dragged by it, and Escape ends it. A band whose list is shown no more (`Band.frame`) does not block another tab's.
    In Columns the rectangle moves the cursor, but the view follows the pointer and does not reveal the cursor.
  - a row's box checks on its way (`check_progress`, `src/view_panel.odin`): it fills at once, at its size, and its tick is
    drawn stroke by stroke in 225 ms, gentle at both ends (a tween: an easing that tends to its end put the whole move in
    50 ms, which nobody saw). Refused: a fill that grows past its size, and a halo: the box that grows looked ugly;
    what was missing was a tick slow enough to be seen. No empty outline shows
    first, and an unchecked row gets its icon back at once: both read as a delay. A rectangle drawn over the
    rows then checks them one after the other as it reaches them. Its state is the box shown checked (the row
    selected among others), not the selection: a row selected alone shows its icon. Only the rows built ask for it (one `ui.tween` each, by tab and row id): a row scrolled into view
    starts at its state, and no frame passes over the folder. The Animations setting off: at once.
  - a folded group's title row cannot be selected (`Folder.selectable`, given in `folder_rows`, made with the rows in
    `folder_refilter`). The row stands for a group whose files are not shown: no click, key, Select all, Invert
    selection or rectangle takes its first file, which an action would then act on unseen. The band, the clicks and
    the keys read the same rule from `Item_Rows.selectable`.
  - the keys' moves in the grid and the columns view are `ui.item_move_target` (Lines of a row's cards, Columns of a
    column's names); what a move does to the selection was already `item_selection_move`.
  - a card's name is cut by `ui.table_card_name` (its middle, its extension kept).
  - the tab strip uses the toolkit's tab face (`ui.tabs_over(.Folder, ...)`, `ui.tab_face`, `ui.tab_body`,
    `ui.tab_strip_start`, `ui.tab_line_draw`; `src/view.odin`, `src/view_panel.odin`, `src/tab_drag.odin`): fixed-width
    tabs, drags, drop zones and close buttons stay classeur's, while the Folder silhouette, concave feet, strip line,
    hover fill and focused-panel top accent (`mark`) come from the toolkit. Refused: keeping a local `tab_paint` copy.
  - About Classeur (`Shift+F1`, `src/dialogs.odin`, `src/program_actions.odin`) uses `ui.about_modal`: classeur's
    drawn folder logo, version, toolkit version, licence, prioritized built-in "What's new" button (opening Settings >
    What's new), Website, Online release notes, Copy version, and Copy diagnostics (renderer adapter and theme from
    in-memory state, never blocking). Links open through `launch` so workers, elevation restrictions and headless tests
    stay unified.
- **One window per person** (`gt:instance` `serve_start`), the session (`src/session.odin`).
- Back and Forward come back to the row and the scroll left (`Visit`, `src/tab.odin`). A refused rename keeps its name.
- The letters typed go to the panel's filter (`no_typeahead`), not to a jump in the list.

## The thumbnails

- **The cache is the toolkit's** `ui.Thumb_Cache` (gui_toolkit's `src/md/features/thumbnails.md`): only the cards built
  ask (`thumb_cache_get`), the asks leave newest first and `THUMB_THREADS` at a time, one whose card was not built for
  `ui.THUMB_STALE_FRAMES` builds is dropped before it is read, the least used go over the budget (`THUMBS_KEPT`; the
  bytes limit is that many full thumbnails, so the count decides), a texture is made at its first draw. The key is the
  file's path, size and date (`ui.thumb_key`). Classeur's own cache, with a frame counter shared with its workers for
  the stale test, was refused once the toolkit had the same rules on the interface's thread.
- **A thumbnail is made by the toolkit** (`ui.file_thumbnail_make`, the local source's rules: what `gt:image` reads is
  decoded and reduced; another type, a picture over 64 MB, or one `gt:image` cannot read gets the system's thumbnail),
  on classeur's own pool (`app.thumb_pool`), one call per ask. Classeur passes `app.system_thumbs` as its `system`: off
  headless, so a test never reads nor writes the person's cache.
- **Clear thumbnails** is `ui.thumb_cache_clear`: the cache frees the entries once no draw reads them, and the asks in
  flight land as any answer.
- The inspector shows a PDF's first page and a frame of a video: the system's large thumbnail, said so under it
  (gui_toolkit's `desktop.thumbnail`). Its pictures are decoded with `gt:image` in the inspector's own job, not by
  `file_thumbnail_make`: the pane says the picture's own size, which that call does not give.
- A large picture's thumbnail (over 2 MB) is read from the system's cache first and kept there once decoded.

## Known gaps

- The sessions of papier and classeur both have a shots command; papier's runs a headless sway, classeur's runs
  headless in a test. If papier moves to the headless test, nothing is left to share.
- Windows: the CI runs the tests and checks the icon and `classeur.com` there. Drags between two real windows are tested
  by hand only.
