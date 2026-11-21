# Architecture

classeur is one process and one window. The interface is built again at every frame from the program's data (gui_toolkit
is immediate-mode); the data changes only on the interface's thread. This page is the map of the code; the reasons behind
it (the decisions, the refused alternatives, the subtle points) are in [src/md](../src/md/README.md).

## Packages and files

| Where | What |
|---|---|
| `src/fs/` | The file system, the same interface on every system. `list` reads a folder into a `Listing` (one array of `Entry`, the names in one arena). Linux: `getdents64` into 64 KB, then one `statx` per entry relative to the folder's descriptor. Windows: `FindFirstFileExW` with the basic level and large fetches (no call per file). `stat`, `space`, `volumes`, the operations (`copy_file`, `copy_link`, `rename` that never replaces, `make_folder`, `remove`, `trash`, `free_name`), `Watch`, the paths (`clean`, `join`, `parent`, `base`, `crumbs`), the devices of the network (`network_devices`, `dns_parse`) and the natural sort (`name_compare`: digits by value, case and Latin accents ignored; `sort_order`: a stable merge sort of indices). |
| `src/folder.odin` | A folder as a panel shows it: the listing, its order, the rows shown (filter, hidden files), the selection (the toolkit's `Item_Selection` over the rows' ids, the hashes of their names, so that it survives a sort, a filter or a new listing) and its cursor. No interface. |
| `src/tab.odin` | Tabs (a path, its history, a `Folder`, the fields of the toolbar) and panels (tabs, one active). Reading a folder: `tab_load` gives a task to the workers; `load_done` (through `ui.post`) gives the listing to the tab only if it is the read the tab waits for (`serial`). The worker also sorts and filters the listing with a copy of the tab's settings (`folder_view_copy`, `folder_prepare`); `load_done` swaps the prepared arrays in (`folder_take`) and only puts the selection and the cursor back by name. |
| `src/jobs.odin` | Copy, move, trash, delete: one thread, one job at a time, progress in atomics, a question through `ui.post` and a semaphore. |
| `src/dialogs.odin` | The name-taken question and the delete-for-good confirmation. |
| `src/watcher.odin` | The folders of the tabs, watched on a thread (`fs.Watch`); a change reads the tab again. |
| `src/commands.odin` | The table of every command: id, title, icon, keys, whether its keys work while a text field has the keyboard, the arguments the palette asks. The keyboard (`commands_keys`), the palette and the menus read it. |
| `src/actions.odin` | What the commands do, and the rename in place. |
| `src/palette.odin` | The command palette (the toolkit's `ui.Command_Palette`): the commands source's table, the settings source, the choice, the sheet of the keys. The person's keys and aliases are the toolkit's (`ui.Keymap`, its recorder). |
| `src/palette_sources.odin` | The palette's own sources: `@` the tabs, `/` the folders (listed on the workers, answered in an arena of their own). |
| `src/menu.odin` | The menu of a row or of the folder (right click, Menu key). |
| `src/view.odin` | The window: the top row (the sidebar's head, each panel's tabs as wide as the panel under them, from the last frame's boxes; the window's buttons), then the views' frame (`ui.views_frame`) around the panels; the keys of the commands and of the selection. |
| `src/views.odin` | The views (gui_toolkit's `ui.Views`, `app.views`): the sidebar and the inspector (home: docked at the left and the right of the frame), GoTo, the settings, the name-taken question, batch rename; the memory of where each is shown (`<state>/FromentSoftware/Classeur/views.txt`). |
| `src/view_panel.odin` | A panel: toolbar (back, forward, up, history, lock, bookmark, the crumbs or the typed path, the panel's menu), the columns' header, the virtual list (a box per row, the measures of folders), the footer (the filter, the counts). |
| `src/sidebar.odin` | The sidebar: its filter, its sections (Recents, Bookmarks, Storage, Network, Places). |
| `src/icons.odin` | The entries' icons: drawn folders and pages, Lucide icons coloured by kind. |
| `src/measure.odin` | Folder measures (folders, files, bytes all the way down) on a pool of their own. |
| `src/thumbs.odin` | The grid's thumbnails: the toolkit's `ui.Thumb_Cache` (only the cards built ask, the newest first, two at a time, a card scrolled past not read, the least used dropped), each made by `ui.file_thumbnail_make` on a pool of its own (`app.thumb_pool`): PNG, JPEG, BMP, GIF and WebP decoded with `gt:image` and reduced; any other file, or a picture it cannot decode, the system's thumbnail (on Linux the freedesktop.org cache and thumbnailers, on Windows the shell's); a picture over 2 MB read from the system's cache first and kept there once decoded. The tests turn the system's off (`app.system_thumbs` is off headless) unless they give their own XDG folders. |
| `src/goto.odin`, `src/deep_find.odin` | GoTo and the path field's rows (`goto_rows`): a path's entries, the places, and every entry below the current folder. The tree is walked on a worker into a `Deep_Index`, each text is matched on a worker, the best rows posted (`deep_rows`). |
| `src/inspector.odin` | The inspector: a picture, a PDF's first page or a video's frame (the system's 1024-pixel thumbnail, said under it), a text, a folder's rows, the properties; read on the workers when the cursor stops. |
| `src/places.odin` | The sidebar's places (the person's folders) and volumes, read on a worker. |
| `src/integration.odin` | classeur on the desktop (gui_toolkit's `desktop` and `setup`): the identity, the install's boxes (`SETUP_CHOICES`: on the PATH; the default file manager, which on Windows also takes Win+E), each tied to its part so that it shows what the system has. The settings' menu and session switches are the toolkit's (`prefs_page.install_follow`, which applies them to the installed copy and keeps the install's own parts as it left them). |
| `src/network.odin` | The devices of the network that share files, searched on a worker (`fs.network_devices`: one query of multicast DNS for the file services, and on Windows the network neighbourhood) when the Network section shows or opens, and by Find network devices; closing the app cancels it (`app.devices_cancel`). |
| `src/format.odin` | Sizes, dates (local time zone), types and icons of entries. |
| `src/app.odin` | The App, its window (`app_open`, `app_frame`, `app_close`: the tests drive the same procedures), the theme. |

## Threads

- The interface's thread owns every `App`, `Panel`, `Tab` and `Folder`.
- The workers (`tasks.Pool`s of gui_toolkit's `gt:tasks`: `app.pool` grows while a read of a share hangs, the
  thumbnails' runs the newest first, an urgent task before the rest) run tasks: a task gets what it needs as a copy (a path), makes its result in memory of its own, and
  posts it with `ui.post(&app.main.state, proc, data)`. The procedure runs at the start of the next build, on the
  interface's thread, and frees the task.
- A read that is no longer wanted (the tab went elsewhere) still runs; its result is dropped because its `serial` is
  old.
- The changes to files the interface makes itself (a rename, a new folder or file, a batch rename, the undo and redo of
  these) go to a worker of their own (`app.edit_pool`, one thread: `edit_submit`), so they are done in the order asked.
  The interface keeps what it shows until the answer (the rename's field stays open). The places of the sidebar, a
  share's folder and the share a tab's folder is under (its title, its first crumb) are read on the workers too, and so
  is whether the folder is in an archive (`Tab.in_archive`: what writes is refused at once, what opens as a folder).
- A thumbnailer the system runs for a PDF or a video (`desktop.thumbnail`) runs on a worker, which waits for it (at
  most 30 seconds): the grid's on the thumbnails' pool, the inspector's on the workers.
- A program started (the system's application for a file, Open with, a terminal) is a task of the workers (`launch`):
  a failure comes back to be said. The files written as the window runs (the session, the layouts) are
  each a `store.Writer` (gt:store: its own thread, the latest text wins), the preferences a `config.User_Writer`. Only the read of the
  preferences runs on the interface's thread, before the first frame. The session and the layouts are read by a task at
  the start; the window shows its start's tab until they come (`app.start_read`, src/md/features/session.md).
- The tests wait for the answers with `wait_read` (`app.answers_due`).

## The keyboard

The order in which a build reads the keys, and who has the keyboard, are in
[src/md/features/keyboard.md](../src/md/features/keyboard.md).

## Tests

`src/app_test.odin` opens the real program with no window of the system (`app_open({headless = true})`) and drives it
with gui_toolkit's `testkit/session`: keys and clicks go through the event path, the workers really read a folder made
for the test, and `wait_read` makes frames until every tab has its folder. `test_shots` makes the README's pictures
(`classeurtool shots`).

## The system and the interface

The interface (`src/*.odin`) never says which system it runs on. What differs between Linux and Windows is asked of:

- `src/fs`: the file system (reading folders, statx or FindFirstFileExW, copies, renames that never replace, the trash,
  the volumes, watching, the places of the system, how names compare, what a typed path looks like), one file per
  system (`*_linux.odin`, `*_windows.odin`). The Recycle Bin of Windows is no folder: `fs.list` reads every drive's
  `$I` records into a listing whose entries carry their real paths (`Listing.trashed`; `entry_path` in the program);
- gui_toolkit: the window, the input, the clipboard, drag and drop (`platform`), the icons of files, Open with, the
  terminal, the install (`desktop`, `setup`), one window per person (`instance`);
- a constant of the program's own in `src/system_<os>.odin` (`SETUP_AT_START`).

`classeurtool check` refuses `ODIN_OS` anywhere else in `src/` (`check_systems`).
