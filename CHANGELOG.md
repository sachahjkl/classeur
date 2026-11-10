# Changelog

All notable changes to classeur are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [Unreleased]

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
