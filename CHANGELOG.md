# Changelog

All notable changes to classeur are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [0.16.1] - 2026-11-12

### Fixed
- **Large folders no longer hold the window**: a folder of tens of thousands of items is sorted and filtered on a worker as it is read, so the window does not stop when it comes or when a change in it makes it read again. A filter typed in it answers faster, the footer and the list do no work per item at each frame, and a paste of many items selects them at once.
- **A hung share no longer holds the other folders**: when every reader waits on a share that does not answer for a second, classeur starts another, so local folders, the address's suggestions and the rest still open.
- **The thumbnails on screen come first**: after a fast scroll through a grid, the cards on screen get their pictures at once instead of after every card passed; a picture changed on disk gets a new thumbnail; the names of the types no longer wait for the pictures, and a grid of many small cards no longer loses its pictures and icons at each frame.
- **Measures go on in the other panels**: going to another folder in one panel no longer stops the folder measures of the other panels. Measuring a very large tree takes far less memory, and the measures kept are limited to the 20 000 most recent.
- **Closing does not wait for a search**: closing the window stops a running flat search and the folder measures at once. A read of a share that does not answer no longer holds the window open: classeur waits half a second at most.
- **A folder changed while it is read is read again**: a file made or removed while a folder is being read now shows once the read ends; before, the change was missed until the next one.
- **A search of a large tree stays smooth**: while the flat search reads, each batch of results goes among the rows already shown, without filtering and sorting all of them again. A search of a tree of many thousands of files no longer slows down as it goes.
- **A slow disk or share no longer holds the window**: a rename, a new folder or file, a batch rename, an undo or redo of them, opening a share's address and reading the sidebar's places are done in the background. While a rename is being done, its field stays open; a name refused is said and kept in the field, as before. The sidebar keeps its list until the new one is read. The name of a tab on a share and the share's address in the path are read with the folder, no longer at every frame.

## [0.16.0] - 2026-11-12

### Added
- **The name-taken question compares the two files**: it shows the size and the date of the file there and of the one copied or moved, and marks the newer one.
- **A copy says its speed and the time left**: the footer's line of a job that runs and its row in the jobs' view read "Copying 3 of 40 · name · 42 MB/s · 2 min left". The speed is smoothed over the last seconds and shows after the first second; the time left shows when the total is known.
- **The sidebar and the inspector by the keyboard**: F6 goes from the sidebar to each panel's list, then to the inspector, and back to the sidebar; Ctrl+Shift+F6 goes the other way. In the sidebar, Up and Down move a cursor over its places, Enter opens the place, Ctrl+Enter opens it in a new tab. In the inspector, Page Up, Page Down, Home, End, Up and Down scroll the text or the folder shown. Escape gives the keyboard back to the list, whose cursor stays where it was.
- **The inspector's folder rows open**: a double click on an item of the folder shown goes to it if it is a folder, or opens it with its application if it is a file, as in the list.
- **The inspector says when a text is cut**: a text longer than 64 KB ends with "The first 64 KB are shown."
- **The inspector says a picture's pixels**: its head shows the picture's own width and height (1920 × 1080), not those of the copy it shows.
- **The inspector sums up a selection**: with several items selected, it says how many there are, how many folders and files, and their size (the folders' when they are measured), then lists them.
- **Keyboard shortcuts on F1**: a sheet lists every command with its keys, your own keys included, under the palette's groups. It is in the panel's "…" menu too; Escape closes it.
- **Dates in your format**: the setting Date format (Files) shows the dates as before (2026-11-09 21:40), relative ("Today 21:40", "Yesterday 21:40", the weekday in the last week, then "9 Nov 2026"), or day, month and year ("9 Nov 2026 21:40").
- **Drops on the path, and folders that spring open**: files dragged onto a part of the path go into that folder, marked as a row is. Held still on a folder's row for 0.7 s while dragged, the folder opens in its tab; on a tab, that tab is shown, and the drag goes on there.
- **Put back and Empty the trash**: in the trash (trash:///), Put back (Ctrl+Alt+R) returns the items selected to where they were, and Empty the trash (Ctrl+Shift+Delete) deletes every item for good after a question; both are in the menus of the trash. On Windows the Recycle Bin is no folder: its items come back by an undo.
- **The sidebar's rows have a menu, and the bookmarks move**: a right click on a place, a bookmark, a recent or a volume opens it here, in a new tab or in the other panel, copies its path or opens a terminal there; a bookmark is removed from it, the recents cleared (Ctrl+Shift+Alt+H). A bookmark dragged up or down lands where the line shows. A middle click on a volume opens it in a new tab, as on the other rows. A recent shows its folder's name, then where it is in the weak colour.
- **What is cut looks cut, what is pasted is selected**: after a cut, its rows, lines and cards are dimmed until they are pasted or something else is copied or cut. After a copy or a move into the folder of a tab, the items it made there are selected and the cursor is on the first.
- **The row's menu holds what can be done with an item**: a folder's row pastes into that folder (Ctrl+Shift+V) and bookmarks it (Ctrl+Shift+B); every row copies its names, copies or moves it to the other panel, goes to its folder in a search and opens the Inspector. Rename stays on with several items selected and says "Rename 3 items…": it opens the batch rename, as F2 does.

### Changed
- **The dialogs share one look**: batch rename, the naming of a layout and the key recorder have a title, a weak note and buttons laid out as the question before Delete for good; the button that Enter presses says "(Enter)", and the case of batch rename is a segmented control.
- **An empty view says what to do**: an empty folder, a filter or the columns' funnels that leave no row, a folder of hidden files only, a folder that cannot be read: the middle of the view says so, with an icon, and offers its way out (New folder, Paste, Clear the filter, Show every row, Show hidden files, Go up, Try again). It was one grey line at the top.
- **The panel that has the keyboard stands out**: with two panels, its shown tab has a line of the accent two pixels thick as its top edge, and the other panel's column titles are dimmed with its rows.
- **The inspector's picture sits under the properties**: it is at the top of its room, fitted to the pane's width, not centred under a large empty gap.
- **Commands have short names and their own icons**: the menus, the tooltips and the palette say "Inspector", "Jobs", "Delete permanently", "Move tab to window" instead of a sentence with a colon, and the palette still finds a command by the words its old name had ("beside the list" finds the inspector). Each command has an icon of its own: Zoom out no longer shows a cross, the hidden files and the inspector no longer share the eye, each sort and each group has its sign. Tab 1 to Last tab leave the palette's lines until "tab" is typed.
- **Types named by the system**: the Type column, the footer, the tooltips and the inspector say what the system calls a file's type ("Plain text document", "PNG image"); a folder is a "Folder". A type the system does not know still reads "TXT File".
- **A card shows more of a long name**: the name goes on two lines, centred, where the card has room for them; still too long, it is cut in its middle so that its end and its extension stay visible ("a very long na…ame.txt").
- **The footer reads plainly**: the counts of folders and files show the number alone ("7"), and "3/7" in the accent's colour only while a filter leaves rows out; the zoom shows the view's icon before its percent. The empty part of the footer says the cursor's item: its name, type and size.
- **A rename that fails keeps what you typed, and Tab renames the next item**: when the name is taken or not allowed, or the system refuses, the field stays open with the name selected and in the colour of an error, and the reason shows; Tab and Shift+Tab keep the name and rename the next or the previous item, as in Explorer. A change of case alone ("File.txt" to "file.txt") renames on Windows too.
- **Back and Forward come back to where you were**: the cursor is on the item it was on when you left the folder, and the list is scrolled as it was; before, the cursor went to the first row and the list to its top.

### Fixed
- **A long text scrolls in the inspector**: its box was one row tall whatever the text, so the text ran past it and neither the wheel nor the keys could scroll it.
- **The small controls follow the rounding**: the toolbar's buttons, the crumbs, the address and rename fields, a tab's close button and the zoom's slider are rounded as the rows' selection, and square when the rounding setting is 0; the ring a drop shows takes the corners of what it is around.
- **The inspector of an empty folder**: it was blank, with no close button; it now shows the folder in its head, its close button, and "This folder is empty." (or "Nothing selected.").
- **Typing filters after a click too**: once the list had the keyboard (a click in it), the letters typed jumped to a name instead of going to the filter; they go to the filter now, as before any click.
- **The arrows work as soon as classeur opens**: the list has the keyboard from the start; Up, Down, End and the others did nothing until a first click in it.
- **Every tab stays in reach when a panel has many**: a row with more tabs than it holds scrolls with the wheel, the tab shown is brought into view, the new tab's button stays at the row's end, and a chevron before it lists every tab of the panel to show one.
- **The Size column draws no stray dots**: a file under 2 % of the largest row's size has no bar under its size, and each bar ends under the right edge of its size. The Folders and Files cells of a file are empty; a folder shows "--" only until it is measured, then its counts.
- **A menu's search edits as a field and the menu holds still**: in the right-click menu and the layouts' menu, what is typed takes Ctrl+A, Backspace on a selection, Ctrl+Backspace for a word, the arrows and a paste; while it filters, the menu keeps its corner and its width (gui_toolkit at 59f97b3).
- **The questions are clear and fit their dialog**: Delete for good is the toolkit's question, as inspecteur asks it: its title, a note, each item it deletes by name, Cancel (Enter: nothing is deleted) and Delete; the note no longer runs under the buttons. The question of a name already taken has the same look, its four choices fit on one line, and Enter keeps both files.

## [0.15.2] - 2026-11-11

### Added
- **The details header's menu resets a column**: a right click on a column's title offers to give it back its own width and to leave its sort, the rows can go back to no sort, and Default columns shows every column again at its width and place (gui_toolkit 0.195.0).

## [0.15.1] - 2026-11-11

### Changed
- **The palette forgives a slip**: a word typed with a letter missing, one too many, one for another or two swapped still finds its command or setting ("new foldr" finds New folder), after every exact match. The palette's field has the darker background of a field, and its edge runs all along it (gui_toolkit 0.194.0).

## [0.15.0] - 2026-11-11

### Added
- **The system's title bar, by choice**: a setting puts the window under the system's title bar (Windows, X11, a Wayland compositor that draws them), the tabs under it; off, they are in the title bar as before.
- **The inspector's picture zooms**: the wheel zooms about the pointer, a drag moves it, a double click shows its pixels and fits it again, a bar at its corner says the zoom. Code is coloured with the theme's colours for code, and a script with no extension gets its language from what it holds (its #! line).
- **Shares of the network, the trash and file URIs**: smb://, sftp://, ftp://, dav(s)://, nfs:// and afp:// open from the address bar, GoTo, the command line or another program; on Linux a share gvfs has not mounted yet is mounted first (its password asked by the session), on Windows an SMB share is its \\\\host\\share path. trash:/// opens the trash, file:// URIs their path. The shares mounted are listed in the sidebar's new Network section; a share's folder is named by it in its tab and its address.
- **A click of the wheel scrolls**: on the empty part of a list, the sidebar or the inspector, the view follows the pointer until the next click, as in a browser; on a folder it still opens a tab.

### Changed
- **Square rows**: a selected row of a list, a table or a menu fills its whole width with square corners, and a table's tinted cell is square too. The Console theme is named Kernel (gui_toolkit 0.191.1).
- **Selected rows are one block**: rows selected one under another share one fill and one border around them, with no line between them nor under the selection. A rectangle drawn over a folded group takes none of its hidden files, and costs what it touches in a large folder.
- **Fields empty with a cross, what a search found lit in the theme's colours**: the sidebar's filter, GoTo and the panel's filter have a cross that empties them; GoTo, the address's suggestions and the search of every folder below light the letters found as the palette does. The batch rename's case is three words to choose from.
- **The details' columns are resized, moved and scrolled**: the line at a column's right edge resizes it (its width kept), its title dragged moves it, a panel narrower than its columns scrolls sideways instead of dropping some; Folders and Files are two columns, each shown or hidden from the header's menu. A date sorts the newest first.
- **The palette is the toolkit's, with the settings in it**: every setting is found there too (by its words, "corners" for the rounding) and opens alone in the settings; what was typed is lit in the lines; Ctrl+Enter records a command's keys in a small dialog of its own. The settings show classeur's version at their foot, and an update to install shows as a button in the title bar.

### Fixed
- **Every key has its name**: the keypad's + and - and the Menu key showed "?", and a key of one's own made of them was lost at the next start. The menus and the tooltips show the keys one set, not the default ones.
- **The session on disk is always the last one**: two writes at once could leave an older one, and dragging the sidebar wrote it at every frame.
- **Escape ends a gesture**: files or a tab dragged, a rectangle drawn, a section of the sidebar dragged; the rectangle gives back the selection there was, a drag moves nothing. It cleared the selection instead.
- **The keys of an open dialog stay in it**: Escape or a shortcut pressed in the palette, GoTo or the settings no longer reaches the window behind them.

## [0.14.5] - 2026-11-11

### Fixed
- The session (the panels, the tabs, the bookmarks, the recent folders) is written as soon as it changes, not only when
  the window closes: a program killed, a crash or the end of the system's session lost the tabs.
- Folders given at the start (another program opening one) open beside the session's tabs, which come back too (they
  alone were shown); a folder that has a tab already shows it.
- A dragged tab's ghost has a tab's shape, one line of the accent on its top and sides, and fits in the row: the tabs'
  widths count it and the window's buttons (it ran past the row's end, cut).

### Added
- Each tab's sort is part of the session.
- `classeurtool test <names>`: those tests of the program alone; the tests' log says each one as it starts.

## [0.14.4] - 2026-11-11

### Changed
- A column's title clicked a third time goes back to the order there was (the names going up): its first way, the other
  way, then the names'. The sort commands (Ctrl+Alt+1 to 4) go the same way round.

## [0.14.3] - 2026-11-11

### Fixed
- The rectangle selection in the Grid and Columns views (it was the Details and List views' only): from the empty part,
  between the cards too, it selects the items it touches. Ctrl and a drag from a card deselects as in the list.
- A right click on the empty part of the Grid view opens the folder's menu (the Columns view's goes through the same
  place now).
- A test goes through the pointer's gestures in every view: the rectangle, the empty part's menu, Ctrl and a drag, a
  file dragged onto a folder.

## [0.14.2] - 2026-11-11

### Fixed
- Files dragged in the window are classeur's own drag (File Pilot's): the folder under the pointer (a row, a tab, a place
  or a bookmark of the sidebar) is lit, a ghost beside the pointer says what a release does, and the release makes the
  job. The system's drag, which takes the files at the window's edge (to another program, the desktop), blocked the
  window: nothing was lit, and on some compositors the drop never came.
- A dragged tab's ghost, the place it lands and the half a new panel takes show at once: they waited for the tab's picture
  (read back from the renderer for the system's drag), which comes late on some systems, never on some.
- A tab dragged from another classeur window shows its ghost where it lands in this one's row, and lands there.
- 0.14.1 was not published (its Windows build failed a test that assumed the tabs' widths).

## [0.14.1] - 2026-11-11

### Added
- A tab dragged shows its ghost where it lands in a row, the tabs after it moved along (nothing then follows the pointer
  over it); off the rows, the panel or the half a new panel takes is lit as before.
- Letters typed while the list has the keyboard go to the panel's filter (File Pilot's); Space still opens the inspector.
- Ctrl and a drag from a row (Explorer's): from a selected row, the rows it passes leave the selection; from another, they
  join it.
- A right click on the empty part of a list opens the folder's menu (New folder, New file, Paste...).

### Fixed
- Files dragged out of a list into a folder of classeur (a row, a tab, a place or a bookmark of the sidebar) on Linux:
  the drop was refused everywhere, the drag's data coming at its drop only; classeur now knows its own drag's files.
- A tab dragged onto another classeur window docks there on Linux: the window took no drop of a tab, whose data Linux
  reads at the drop only (the toolkit's drop_types tells it before); files dragged from another program too.
- The dragged tab's picture and ghost had several blue borders: its picture is read before the ghost shows, the ghost has
  one line, the tab left behind is dimmed.
- The text size's slider applies when let go (shown live, the page moved under the pointer); the rounding and the
  dimming of the panels still show while held.
- The sidebar's filter as tall as the panels' toolbars: their lines meet.
- A line under the title bar, the whole width, the shown tab's lines going on from it.

### Changed
- The alternating rows a faint shade (a few levels off the list, mixed in sRGB): the tint of the text, blended in linear
  light, made a band that stood out on a dark list.
- The themes are the toolkit's, as in its other programs (inspecteur's Graphite): classeur's own Graphite is gone; the
  surfaces, the selection, the cursor and the volumes' bars take the theme's colours.

## [0.14.0] - 2026-11-10

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

### Fixed
- A malicious archive (an entry named "../..") lists nothing that a copy could follow out of its folder (the toolkit's
  archive leaves such entries out); a file opened out of an archive goes to a folder of the person's alone, named after
  the archive and the file, removed at the end; what writes is refused at once in an archive.
- The search's batches are merged into the order, not sorted again whole; a short search shows at once; a new search
  starts at its top.
- A folder's measured size goes to the listing shown, at its date; the bars follow it; the sort by size at most every
  250 ms; the selection's size counts files only.
- The inspector works a source file's colours out once, not each frame.
- Windows: a move to the Recycle Bin is undone (Ctrl+Z): the item is found by its $I record and put back where it was.
- Wayland: a second start brings the window up with its launcher's activation token (the toolkit's
  raise_window_token), which the compositor honours where it may refuse the window's own.

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
- The sidebar's sections in the person's order: a heading dragged (a line says where it lands; Escape cancels), its
  menu's Move up, Move down, Move to the top, Move to the bottom, or the keys of the section last touched
  (Ctrl+Alt+Shift+Up and Down); kept between starts.
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

[0.16.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.16.1
[0.16.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.16.0
[0.15.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.15.2
[0.15.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.15.1
[0.15.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.15.0
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
[0.14.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.0
[0.14.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.1
[0.14.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.2
[0.14.3]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.3
[0.14.4]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.4
[0.14.5]: https://github.com/sachahjkl/classeur/releases/tag/v0.14.5
