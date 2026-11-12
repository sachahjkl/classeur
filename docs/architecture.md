# Architecture

classeur is one process and one window. The interface is built again at every frame from the program's data (gui_toolkit
is immediate-mode); the data changes only on the interface's thread.

## Packages and files

| Where | What |
|---|---|
| `src/fs/` | The file system, the same interface on every system. `list` reads a folder into a `Listing` (one array of `Entry`, the names in one arena). Linux: `getdents64` into 64 KB, then one `statx` per entry relative to the folder's descriptor. Windows: `FindFirstFileExW` with the basic level and large fetches (no call per file). `stat`, `space`, `volumes`, the operations (`copy_file`, `copy_link`, `rename` that never replaces, `make_folder`, `remove`, `trash`, `free_name`), `Watch`, the paths (`clean`, `join`, `parent`, `base`, `crumbs`) and the natural sort (`name_compare`: digits by value, case and Latin accents ignored; `sort_order`: a stable merge sort of indices). |
| `src/folder.odin` | A folder as a panel shows it: the listing, its order, the rows shown (filter, hidden files), the selection (a flag per entry, so that it survives a sort or a filter), the cursor and the anchor of Shift ranges. No interface. |
| `src/tab.odin` | Tabs (a path, its history, a `Folder`, the fields of the toolbar) and panels (tabs, one active). Reading a folder: `tab_load` gives a task to the workers; `load_done` (through `ui.post`) gives the listing to the tab only if it is the read the tab waits for (`serial`). |
| `src/pool.odin` | The workers: three threads, a queue of tasks. |
| `src/jobs.odin` | Copy, move, trash, delete: one thread, one job at a time, progress in atomics, a question through `ui.post` and a semaphore. |
| `src/dialogs.odin` | The name-taken question and the delete-for-good confirmation. |
| `src/watcher.odin` | The folders of the tabs, watched on a thread (`fs.Watch`); a change reads the tab again. |
| `src/commands.odin` | The table of every command: id, title, icon, keys, whether its keys work while a text field has the keyboard. The keyboard (`commands_keys`), the palette and the menus read it. |
| `src/actions.odin` | What the commands do, and the rename in place. |
| `src/palette.odin` | The command palette: fuzzy search over the titles, the keys shown. |
| `src/menu.odin` | The menu of a row or of the folder (right click, Menu key). |
| `src/view.odin` | The window: the top row (the sidebar's head, each panel's tabs as wide as the panel under them, from the last frame's boxes; the window's buttons), the body; the keys of the commands and of the selection. |
| `src/view_panel.odin` | A panel: toolbar (back, forward, up, history, lock, bookmark, the crumbs or the typed path, the panel's menu), the columns' header, the virtual list (a box per row, the measures of folders), the footer (the filter, the counts). |
| `src/sidebar.odin` | The sidebar: its filter, its sections (Recents, Bookmarks, Storage, Places). |
| `src/icons.odin` | The entries' icons: drawn folders and pages, Lucide icons coloured by kind. |
| `src/measure.odin` | Folder measures (folders, files, bytes all the way down) on a pool of their own. |
| `src/places.odin` | The sidebar's places (the person's folders) and volumes. |
| `src/format.odin` | Sizes, dates (local time zone), types and icons of entries. |
| `src/app.odin` | The App, its window (`app_open`, `app_frame`, `app_close`: the tests drive the same procedures), the theme. |

## Threads

- The interface's thread owns every `App`, `Panel`, `Tab` and `Folder`.
- The workers (`Pool`) run tasks: a task gets what it needs as a copy (a path), makes its result in memory of its own, and
  posts it with `ui.post(&app.main.state, proc, data)`. The procedure runs at the start of the next build, on the
  interface's thread, and frees the task.
- A read that is no longer wanted (the tab went elsewhere) still runs; its result is dropped because its `serial` is
  old.

## The keyboard

1. `view_build` reads the keys of the commands first (`commands_keys`). While a text field has the keyboard (the fields
   built in the last frame are noted in `app.text_keys_before`), only the commands marked `in_text` run.
2. Then the keys of the selection (`list_keys` in `view.odin`: Shift ranges, Ctrl+Space, Escape, Menu).
3. Then the virtual list of the focused panel takes the moves (Up, Down, Page Up, Page Down, Home, End). It takes no
   letter (`no_typeahead`): the letters typed go to the panel's filter (`type_to_field`). A move of the list selects the
   cursor's row alone (`folder_pick`). The list has the keyboard from the start (`app_open`).
4. A press in a panel gives it the keyboard; unless the press is on a text field, the list gets the focus back at the
   next build (`Tab.focus_due`).
5. F6 and Ctrl+Shift+F6 move the keyboard round its stops (`app.keys_at`): the sidebar, each panel's list, the inspector.
   While the sidebar or the inspector has it, the list's keys do not run and only the `in_text` commands do; Escape gives
   it back to the list.

## Tests

`src/app_test.odin` opens the real program with no window of the system (`app_open({headless = true})`) and drives it
with gui_toolkit's `testkit/session`: keys and clicks go through the event path, the workers really read a folder made
for the test, and `wait_read` makes frames until every tab has its folder. `test_shots` makes the README's pictures
(`classeurtool shots`).

## The system and the interface

The interface (`src/*.odin`) never says which system it runs on. What differs between Linux and Windows is asked of:

- `src/fs`: the file system (reading folders, statx or FindFirstFileExW, copies, renames that never replace, the trash,
  the volumes, watching, the places of the system, how names compare, what a typed path looks like), one file per
  system (`*_linux.odin`, `*_windows.odin`);
- gui_toolkit: the window, the input, the clipboard, drag and drop (`platform`), the icons of files, Open with, the
  terminal, the install (`desktop`, `setup`), one window per person (`instance`);
- a constant of the program's own in `src/system_<os>.odin` (`SETUP_AT_START`).

`classeurtool check` refuses `ODIN_OS` anywhere else in `src/` (`check_systems`).
