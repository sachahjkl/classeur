# GoTo and the path field: the deep search

GoTo (Ctrl+G) and the path field of a panel (Ctrl+L, or a click on the empty part of the crumbs) answer one question:
"where do I want to go?". Both give the same rows, from `goto_rows`. GoTo is a dialog; the path field shows its rows in a
list that drops down under it, in the panel's toolbar. A click on the toolbar never opens a dialog over the panel.

## What a text finds

- **An absolute path** (`/`, `~`, a drive): the entries of the folder it names so far, found by the letters after its last
  separator. Folders and files. Tab completes the path to the row chosen.
- **Anything else**: the recent folders, the bookmarks and the places whose path has the letters, then every file and
  folder **below the current folder, at any depth**, ranked by `gt:filesearch` (fff-search): typo-tolerant fuzzy
  matching and LMDB frecency.
  - A relative path that exists is placed first, even before the initial scan finishes.
  - Entries under a hidden folder (its name starts with a dot) are left out unless hidden files are shown or the text
    starts with a dot.

Enter goes to the row chosen; a file's row opens its folder with the file at the cursor (`tab_go`). Opening a file also
records it in the shared frecency store (`ui.palette_files_opened`).

## Why `gt:filesearch`, and where the index lives

`deep_find.odin` keeps one `filesearch.Index` for the current root folder, shared by GoTo, the path field, and the
command palette's `/` files source (`ui.Palette_Files`). Opening, searching, frecency updates, and closing all run on
background workers (`app.pool` / `ui.task`): the interface thread never touches disk or LMDB.

- Opening a new root closes the previous index on a worker and opens the new one with a monotonic `open_serial` (late
  opens for a root left behind are closed immediately).
- In normal runs, the index runs with `watch = true` and shares the vendor frecency store
  (`<data>/FromentSoftware/filesearch`) so files opened in `classeur` rank higher across the suite. Because the
  watcher keeps the index live, reopening GoTo in the same folder reuses the warm index instead of rescanning.
- Headless (tests), `watch` is off and `frecency_dir` is empty so tests never touch the person's database and shut down
  deterministically; reopening GoTo resets the index so newly created fixture files are picked up.
- Only one match is in flight; stale answers are dropped (`serial`). While the initial scan runs, a short timer wakes
  the frame to re-query as entries arrive.

Refused: a custom `fs.walk` + per-keystroke linear fuzzy scan over 400 000 entries (no typo tolerance, no frecency, no
live watcher, full re-walk on every GoTo open).
