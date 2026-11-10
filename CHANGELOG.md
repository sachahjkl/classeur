# Changelog

All notable changes to classeur are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [Unreleased]

### Added
- The inspector: its edge dragged (the toolkit's pane: folded to a strip, the arrows, kept between starts); a file's
  properties (where it is, its dates of creation and access, its permissions and owner on Linux, its attributes on
  Windows); a source file in its language's colours (the toolkit's syntax package).
- Archives as folders (File Pilot's): a zip, a tar or a gzipped tar is entered as a folder (Enter; "Open with the
  system's application" still gives it to its program); what is in it is listed, sorted, searched, copied out of it (taken
  out), opened (taken out to a temporary folder first); a write in it is refused (read only). The toolkit's archive
  package reads them.
- The search shows its results as it walks (every 200 ms), the folders read by four threads.
- Sorted by size, the folders go by what they hold as it is measured; a folder measured empty says 0 B. The Size column
  has a bar of each row's share of the largest (File Pilot's).

## [0.13.1] - 2026-11-10

### Fixed
- Where the system has no picture for an icon (no icon theme, a type it does not know), Lucide's folder or file stands
  in: no empty icon. (The 0.13.0 release stopped on this: the CI's machines have no icon theme.)

## [0.13.0] - 2026-11-10

### Added
- Updates: the installed classeur checks its latest release once a day, downloads it, checks its signed manifest and puts
  it in place (the toolkit's Updater); the settings' Updates page checks now, installs, restarts. Releases publish the
  programs alone and their signed manifests, public once both systems' files are there.
- Settings: the rounding of the whole interface (a slider; the tabs' corners and classeur's own drawings too), the
  density, the animations, smooth scrolling, scroll bars that hide.
- Tabs dragged say where they go: the tab follows the pointer, a line between the tabs of a row, the half of the panel a
  new panel takes, the panel that takes it; at the window's edge the drag of the system starts (the pointer still in the
  window), with the tab's picture. A tab's menu sends it to a window of its own (Ctrl+Shift+Alt+N).
- The sidebar's sections in the person's order: a heading dragged (a line says where it lands; Escape cancels), or its
  menu's Move up, Move down, Move to the top, Move to the bottom; kept between starts.
- The columns' filters: a funnel on each column's title (over it, or lit while it filters): the dates of Modified and the
  sizes of Size as the groups have them, with their counts; the types of Type; the letters of Name. Another folder shows
  every row again.
- The palette opens with Ctrl+K too (as in the other programs), and the "…" menu offers it and the settings first.
- A row's icon is its box (File Pilot's): the pointer over it, or the row checked among others, shows it; a click on it
  checks the row, a drag from it drags the row; the header's box is over the icons.

### Changed
- The settings' sliders show their value while they are held (the rounding, the text size), written when let go; the
  settings closed meanwhile, what was written is shown again.
- The site's download button is the reader's system's (Windows or Linux), the other offered under it (the toolkit's).

### Fixed
- A tab dragged back into its own window moves that tab, not another one showing the same folder; a tab dragged out no
  longer goes to a program that takes its path as text; a drag whose tab was closed ends.
- Ctrl+wheel no longer blinks the icons: they are made at a few sizes (drawn smaller), and a size not made yet shows the
  nearest one made.
- After an update on Linux, Restart now and a torn-off tab start the new program (the program's path is read at the
  start).

### Removed
- The Round corners switch: the rounding slider replaces it.

## [0.12.0] - 2026-11-10

### Added
- Windows: classeur.exe has its icon (Explorer, the taskbar, the window), from `res/classeur.rc`.
- Windows: `classeur` typed in cmd or PowerShell gives its output and exit code: `install` writes classeur.com (the
  toolkit's console launcher) beside classeur.exe with the PATH entry; a folder opens a window and gives the prompt back.

## [0.11.0] - 2026-11-10

### Changed
- The Setup is classeur's own screen over the toolkit's controller: a head with the state in its colour, sections as the
  settings page has them (Location, Options, On this system), the buttons in a bar at the foot.
- The menus' search is a field at their top, from edge to edge: a magnifier, what is typed, a caret (the toolkit's).

### Fixed
- On Windows, an install in the default folder asked to be repaired after its restart (the toolkit took the record of
  the default folder for no record).
- The Setup's test wrote its answer in the person's config: a headless run keeps no answer.

## [0.10.0] - 2026-11-10

### Added
- The settings (Ctrl+,): the toolkit's settings page, a page per subject (Appearance, Files, Opening), a search, the
  themes as cards; resizable by its edges and corner.
- The menus' lines show their commands' icons, and are as wide as their longest line (no title cut).
- "Open a terminal in the folder" (Shift+F4, and the menu of a folder).

### Changed
- The palette is resized by its edges and corner and keeps its size; its rows scroll in the toolkit's list.
- The options' list is gone: the settings page replaces it.

### Fixed
- The path suggestions' test waits for the folder's listing (it failed on Windows).

## [0.9.0] - 2026-11-10

### Added
- The path field suggests the folders of the path typed: Up and Down choose, Tab completes, Enter or a click goes.
- The zoom's slider: a row per step with its icon, its name and its percent; a click on a row goes to that step.
- The palette: with nothing typed, the commands run last under Recent, then every command under its group's title; the
  wheel scrolls it, a bar shows where; each row shows its aliases, and its group while searching.

## [0.8.0] - 2026-11-10

### Changed
- The jobs run in the background with their view beside the window, not over it: a panel over the footer that leaves
  the window working, opened by itself once for a job that runs on, sent away by Background or Escape, brought back by
  the footer's button (with the jobs' progress) or Ctrl+Alt+J.

## [0.7.0] - 2026-11-10

### Added
- The columns view filled column by column, scrolled sideways (the wheel too); Up and Down along a column, Left and
  Right across.
- The jobs' window (Ctrl+Alt+J, or the footer's button): every copy, move and trash of the session, what failed, Cancel,
  Retry.

### Fixed
- The errors of the jobs' window and of batch rename in the theme's red, not a magenta.

## [0.6.0] - 2026-11-10

### Added
- Groups folded and unfolded by a click on their title.
- The tree in the names and the columns views too.

## [0.5.0] - 2026-11-10

### Added
- Keys of one's own from the palette: Ctrl+Enter (or a row's +) records the keys of the chosen command, one key or a
  sequence of two (Ctrl+K, then T); Backspace gives it its own keys again. Aliases: the letters typed, Alt+Enter on a
  command, then those letters find it first.
- The tree view (Ctrl+Shift+E): folders opened in place with a chevron, Right and Left.
- Group by date, type or size (Ctrl+Alt+5, 6, 7, or the menus' Group by): a title above each group.

## [0.4.0] - 2026-11-10

### Added
- Panels split below (Ctrl+Shift+J, or a tab dragged to a panel's bottom quarter): columns of panels, each lower panel
  with its tabs at its top.
- The details' columns: shown or hidden from the header's menu (a right click on it), their titles dragged to reorder
  them.
- Tabs torn off: a tab dragged out of the window becomes a window of its own (`classeur --window <folder>`); dragged onto
  another classeur window, it joins its tabs there.

## [0.3.0] - 2026-11-10

### Added
- File Pilot's zoom slider: a click on the footer's percent shows a vertical slider; dragged, the view goes step by step
  and the cards grow or shrink smoothly between the steps.

### Fixed
- Windows: names that start with a dot are hidden files; names joined with the system's separators; a rename tried again
  while the shell reads the file; the batch's folder read after its renames. The tests and the checks run on Windows in CI.

## [0.2.0] - 2026-11-10

### Added
- A key for every action: tabs by number (Alt+1 to Alt+9), the views (Ctrl+1 to Ctrl+4), the sorts (Ctrl+Alt+1 to
  Ctrl+Alt+4), the types (Ctrl+Shift+Y, files or folders alone), copy and move to the other panel (Shift+F5, Shift+F6),
  the names copied (Ctrl+Alt+C), the item's own folder in a search (Alt+O), the tabs closed around the shown one.
- Layouts: the panels and their tabs saved by name (Ctrl+Alt+S) and opened again (Ctrl+Alt+L).
- Tooltips: a tab's path, a row's whole name with its type, size and date, a crumb's path, a column's sort, a place's
  path, a volume's free space.
- The Setup (`classeur --setup`, Ctrl+Shift+F12) and `classeur install`, `uninstall`, `status`: the launcher in the
  applications menu as a file manager, the icons, classeur on the PATH. A copy downloaded on Windows offers it at its start.
- Releases: an archive for Linux and one for Windows on each version's GitHub release.

### Changed
- The interface knows no system: what differs between Linux and Windows is asked of `src/fs` and gui_toolkit
  (`classeurtool check` refuses anything else).

## [0.1.0] - 2026-11-10

### Added
- Folders read on worker threads: a folder of 100 000 files lists and scrolls with no wait. The details view (name, date,
  type, folders, files, size), sorted naturally; File Pilot's zoom (Ctrl+wheel): names alone, names in columns, cards
  ever larger with thumbnails.
- Tabs in panels side by side, the command palette (Ctrl+Shift+P) with every action and its keys, the crumbs, the path
  typed (Ctrl+L), GoTo (Ctrl+G) with the completion of paths, the recent folders, the bookmarks and the places.
- The filter of a folder, fuzzy; the search of every folder below (Ctrl+Shift+F); the types' popup: files or folders
  alone, each extension with its count.
- Copy, cut, paste, move to the other panel, the trash, delete for good, in a queue of jobs with their progress; a name
  taken asks what to do. Undo and redo (Ctrl+Z, Ctrl+Y) of renames, new folders and files, copies, moves and the trash.
- Rename in place (F2), batch rename (F2 on several items): a pattern with numbers, dates and ids, find and replace,
  the case, names from the clipboard.
- Drag and drop: rows and cards out to other programs as files, files dropped from anywhere onto folders, lists, tabs and
  the sidebar; tabs dragged along their row, to another panel or to a new one. The rectangle selection.
- The inspector (Space): a picture, a text, a folder's content beside the list.
- The sidebar: recent folders, bookmarks (Ctrl+D), volumes with how full they are, the person's places.
- The system's icons: the icon theme of the desktop on Linux, the shell's on Windows.
- Folder measures: the folders shown are measured all the way down (their folders, files and bytes).
- The folders shown are watched: a change made by any program shows at once.
- Menus searched by typing, "Open with", a terminal here (F4), the tab's menu, the mouse's side buttons.
- The session: the window, the panels and tabs, the bookmarks and the recent folders come back at the next start. One
  window per person: a second `classeur <folder>` opens a tab in it.
- Options (Ctrl+,): the theme, the font size, hidden files, extensions, folders first, single click, the measures.

[0.1.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.1.0
[0.2.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.2.0
[0.3.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.3.0
[0.4.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.4.0
[0.5.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.5.0
[0.6.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.6.0
[0.7.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.7.0
[0.8.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.8.0
[0.9.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.9.0
[0.10.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.10.0
[0.11.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.11.0
[0.12.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.12.0
[0.13.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.13.0
[0.13.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.13.1
