# Changelog

All notable changes to classeur are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [0.51.0] - 2026-11-27 20:22

### Changed
- **Compact rows is Ctrl+Shift+Alt+R**: its key was Ctrl+Shift+Alt+D, which opens the debug window in a debug build.
- **Updated gui_toolkit to v0.367.0**: photos in the grid are turned the way they were taken, SVG files show their picture, and drop-down lists are as wide as their rows.

## [0.50.1] - 2026-11-27 05:56

### Changed
- **A row's tick is drawn so it can be seen**: its box fills at once and its tick is drawn in about a quarter of a second; an unchecked row gets its icon back at once.

## [0.50.0] - 2026-11-26 21:35

### Added
- **The boxes of the rows check with a movement**: a row's box fills, then its tick is drawn, and it empties the same way; a rectangle drawn over the rows checks them one after the other. With Animations off in the settings, it is at once.

## [0.49.0] - 2026-11-26 20:32

### Added
- **Install for everyone on the computer**: the install dialog and the settings' Installation page offer Only me or Everyone on this computer (Program Files on Windows, /opt on Linux, one administrator prompt). An install for everyone is updated by an administrator. On NixOS the Nix package is the install for everyone.

## [0.48.1] - 2026-11-26 16:07

### Fixed
- **The program is about 860 KB smaller**: a release build again carries only the icons Classeur uses, not the whole icon font.

## [0.48.0] - 2026-11-26 10:33

### Fixed
- **Folders opened by other programs open in Classeur on Windows**: with Open folders and Win+E with Classeur on, a folder or a drive that a program opens by its verb (most Open folder buttons) no longer opens in File Explorer. An existing install shows this part as to repair: run Install again in the settings.

### Security
- **An elevated Classeur opens nothing with your programs**: run as administrator (Windows) or as root (Linux), it opens no file, URL, terminal or Open with application and does not update or install itself. A message says why, and on Windows the title ends with (Administrator).

## [0.47.0] - 2026-11-25 22:18

### Added
- **A rectangle selection starts from a row**: in Details and List, a drag from after a file's name, or from between the columns, draws the rectangle, so a full folder has room to start it; a drag from the name or the icon drags the files. The list keeps half a row of empty space at its end.

### Fixed
- **The rectangle selection shows in a scrolled list**: in Details, List and Grid it was drawn too high by what the list had scrolled, often out of view. In Columns, a rectangle no longer makes the view jump back to the file under the cursor.

## [0.46.1] - 2026-11-24 13:09

### Fixed
- **Open with speaks French again**: when no application opens a file, the submenu says Aucune application instead of No application.

## [0.46.0] - 2026-11-24 11:01

### Changed
- **Updated gui_toolkit to v0.352.0**: the folder watcher, the start of child programs and the restart after an update now use the toolkit, as the other programs do.
- **Open with shows the applications with their icons**: the submenu of a file lists each application with its icon, the default first.

## [0.45.1] - 2026-11-22 06:36

### Fixed
- **GoTo result ordering with recent paths**: recent folders matching only scattered letters along a long path no longer outrank direct filename matches from gt:filesearch.

## [0.45.0] - 2026-11-22 06:10

### Added
- **Typo-tolerant file search with frecency in GoTo, path field, and command palette**: GoTo (Ctrl+G), the path field (Ctrl+L), and the command palette / source now search files and folders below the current directory through gt:filesearch (fff-search) with typo tolerance, live watching, and shared frecency ranking.

### Changed
- **System context menu icons**: system shell actions now render through ui.Shell_Menu with native Windows and Linux theme icons.
- **Updated gui_toolkit to v0.341.1**: Wayland secondary windows wake the loop immediately on input, selected rows keep high-contrast secondary text and search highlights across themes, and preference controls support the mouse wheel.

## [0.44.0] - 2026-11-21 17:11

### Added
- **System shell context menu actions**: right-clicking items or a folder loads third-party system actions asynchronously (Windows shell extensions such as 7-Zip, Git, VS Code, Send to; Linux KIO service menus, Nemo actions, and Thunar custom actions) without slowing menu open.

### Changed
- **Instant tab extraction, new windows, and closing**: tearing off a tab or opening a new window shares the running process and graphics device and moves the tab directly without reloading the folder; closing hides the window immediately and cancels network discovery; startup preloads the graphics device.

### Fixed
- **Opening files on Linux**: double-clicking a file or pressing Enter now opens it with the desktop default application instead of failing silently through the OpenURI portal.

## [0.43.0] - 2026-11-21 10:03

### Added
- **How much of an update is downloaded**: the Updates settings page says the size received and the whole, with a bar.
- **The update button becomes its download bar**: after Install, the button turns into a bar that fills as the update downloads, then into Restart, in one smooth change.

## [0.42.0] - 2026-11-20 11:47

### Added
- **Lower latency on Linux**: during an animation or a drag, each frame starts as late as it can and still reaches the next refresh, so it shows the newest input.

### Changed
- **Every menu filters what is typed**: a field at the top of a menu keeps the items that match, in every menu.

### Fixed
- **`nix run github:sachahjkl/classeur` works.** A flake fetched from GitHub is a tarball without the gui_toolkit submodule, and the build stopped at once; the package now takes the toolkit from an input pinned to the submodule's commit.

## [0.41.2] - 2026-11-20 06:56

### Fixed
- **The full frame rate on a second screen**: on Wayland a window on a 144 Hz screen beside a 60 Hz one moves at 144 frames a second, not 60.

## [0.41.1] - 2026-11-19 22:15

### Fixed
- **Smooth animations on Wayland**: a menu, a dialog or a switch moves at each refresh of the screen, with no need to move the pointer.

## [0.41.0] - 2026-11-19 18:26

### Fixed
- **A folded group's title no longer selects a hidden file**: the keys, Select all, Invert selection and a rectangle skip the title of a folded group, so no action reaches the files it hides.

## [0.40.0] - 2026-11-19 17:29

### Changed
- **GIF pictures show in the grid and the inspector, and the rectangle scrolls the list**: a GIF's card shows its first frame and the inspector shows it, also without the system's thumbnails. A rectangle selection dragged to the edge of the list, the grid or the columns scrolls them to reach the items beyond.

## [0.39.1] - 2026-11-19 15:32

### Fixed
- **The title bar with the sidebar closed**: the sidebar's button keeps its place before the tabs, and the logo no longer runs over the first tab.

## [0.39.0] - 2026-11-18 21:10

### Changed
- **Old Head theme**: sliders have a raised rectangular knob on a sunken track, and switches are drawn as check boxes.

### Fixed
- **No crash when a window closes while a font loads**: closing waits for the font family being read.

## [0.38.0] - 2026-11-18 16:03

### Changed
- **Old Head theme**: its title bar is a navy band with square bevelled buttons, and its scroll bars have bevelled arrows and thumb.

## [0.37.0] - 2026-11-18 13:36

### Added
- **Old Head theme**: square corners, two-tone bevels, a dotted focus and white on navy selections, in the theme list.

## [0.36.1] - 2026-11-18 08:41

### Fixed
- **Settings saved on Windows while another program reads them**: an antivirus or the indexer holding the settings file no longer makes a change get lost.

## [0.36.0] - 2026-11-17 20:55

### Changed
- **The engraving on the back of the licence card blends into the foil**: it is struck in the card's own silver now, and still waits for the right angle.

## [0.35.0] - 2026-11-17 18:13

### Added
- **Something engraved on the back of the licence card**: turn the card over and look at it from the right angle.

## [0.34.0] - 2026-11-17 12:44

### Changed
- **Gaps and margins follow one scale**: the insets of the list's rows and group titles, the gaps between the grid's cards and the padding of the footer's item text use the toolkit's spacing steps, on whole pixels.

### Fixed
- **The window opens at once, even when the settings' folder is on a share that does not answer**: the last session's tabs, bookmarks and layouts come back a moment later. If you open or close a tab, or press a key, before they come, your tabs stay as they are.

## [0.33.0] - 2026-11-17 11:20

### Changed
- **Dates and sizes read as in the other programs of Froment Software**: the words, the units and the order of a date are the language's, and a date keeps the offset of its own day across summer time.
  - Relative dates read "today 21:40", "yesterday 21:40", the weekday for the last week, then "Nov 5, 21:40", with the year only when it is not this one.
  - Day month year dates read in the language's order: "Nov 9 2026 21:40" in English, "9 nov. 2026 21:40" in French.
  - A size rounds to its unit: "10 KB", not "10.0 KB", and "1.0 MB", not "1024 KB"; its number and its unit stay on one line.

## [0.32.2] - 2026-11-16 22:50

### Fixed
- **A click past the last crumb opens the path field, even on a long path.** A folder with a long name covered the empty part of the path bar, and the click did nothing.

## [0.32.1] - 2026-11-16 21:39

### Changed
- **GoTo and the path field search below the current folder, at any depth**: a few letters find any file or folder under it, and a relative path typed whole (packages/web/public/brand/logo.svg) goes straight to its file. A click on the path opens the path field with its list under it, no longer a dialog over the panel.

### Fixed
- **The command palette appears at once, with its rows.** Ctrl+K showed it after a few empty frames, faded it in before its rows came, and jumped when a frame was late; now it comes in the frame its rows are ready, and fades in over 70 ms.

## [0.32.0] - 2026-11-16 17:56

### Added
- **Your licence as a card.** The Licence page of the settings shows a registered licence as a card: an engraved iridescent foil, your name raised in silver, a seal in relief; it tilts towards the pointer and turns over to show its back.

### Changed
- **The palette goes to a command's button and asks a layout's name**: Shift+Enter on a command shows the button that runs it (the sidebar's, New tab, Back, Forward, Up, Lock, Bookmark, the path, the footer's Types, Search subfolders and Jobs, the inspector's close), focused and lit. Save layout asks its name in the palette, and Open layout lists the saved layouts there; their keys still open the prompt and the menu. A setting changed in the palette shows on the settings page in the same frame.

## [0.31.0] - 2026-11-16 13:56

### Changed
- **Even spacing.** The gaps of classeur's windows follow the toolkit's one scale, so neighbouring parts line up.

## [0.30.0] - 2026-11-16 12:12

### Fixed
- **Closing your session no longer reads as a crash.** The next start no longer shows a crash report after a logout or a shutdown. Also from the toolkit: a setting found in the palette is changed right there (Shift+Enter opens its page), and the pricing page keeps the site's bar as it is.

## [0.29.0] - 2026-11-15 21:09

### Added
- **By Froment Software in the install**: the install's dialog and the settings' Installation page show the vendor's mark
and name, a link to its site.

### Changed
- **Your keys and aliases work as in the other Froment Software programs**: Ctrl+Enter on a command of the palette still
sets a key of your own, Alt+Enter still makes the letters typed its alias. A sequence's first key shows at the bottom of
the window until its second. The recorder says when a key types text in a field, and refuses the palette's keys. The
settings show "Your keys" and "Your aliases" (advanced): edit or reset them there. Your keys are now written in English
whatever the language: a key set before in French with Shift ("Maj") must be set again.
- **Classeur, capitalised, and its settings in the vendor's folder**: the window, the menus, the dialogs and the site say
"Classeur". The settings, the session, the layouts, the logs and the palette's memory move once, at the first start, from
the `classeur` folders to `FromentSoftware/Classeur` (`~/.config/FromentSoftware/Classeur` on Linux,
`%APPDATA%\FromentSoftware\Classeur` on Windows). The command `classeur` and its file names do not change.

## [0.28.0] - 2026-11-15 17:40

### Added
- **classeur --quit.** An installer (atelier, a script) asks the running classeur to end before it replaces it: `classeur --quit` closes it as its Quit does and waits for it; `classeur --status` says `quit: yes`.

## [0.27.0] - 2026-11-15 16:49

### Added
- **A license to buy.** The pricing page sells a license of classeur: a payment once through Paddle, the license by mail and on the thank-you page at once, its key or its file to give the program.
- **Properties in an item's menu.** A right click on a file or a folder ends with Properties (Alt+Shift+Enter), as in every file manager: it opens the inspector on the item, with its size, its dates and what the system says of it.

### Fixed
- **Zoom in with Ctrl++ on a French keyboard.** On an AZERTY keyboard + is Shift+=: Ctrl++ now zooms in, as Ctrl+= and the keypad's Ctrl++ do.
- **French that reads like a file manager's.** The French words of classeur were written again in the vocabulary of the French file managers: "Copier le nom", "Copier le chemin d'accès", "Ouvrir l'emplacement", "Vue en liste", "Replier ici", clear messages ("Cette action est irréversible."), one word for one thing ("utilisé", "Conserver").

## [0.26.0] - 2026-11-15 14:20

### Added
- **What's new in the settings.** The settings have a What's new page: each version on a timeline with its day and time, its changes under pills of their kind. After an update, classeur says what changed and opens it on request.

## [0.25.0] - 2026-11-15 12:55

### Added
- **Frame rate in Settings.** Settings › Rendering › Frame rate caps how many pictures a second classeur draws when something moves: the screen's rate, 30 to 240, or no limit.
- **WebP on Windows.** The Windows version ships its own libwebp beside the program, so WebP pictures show there; the setup installs it with classeur.

## [0.24.0] - 2026-11-15 10:42

### Added
- **classeur as the default file manager**: the install (and the settings' Installation page) has a box that makes classeur open the folders other programs open. On Windows, folders, drives and Win+E open in classeur in place of File Explorer; on Linux, classeur becomes the default application of folders. The box shows what the system does, and unticked, it gives the former file manager back. The box of the PATH also shows what the install has now.

## [0.23.0] - 2026-11-15 08:23

### Changed
- **Too many tabs scroll with arrows.** When a panel's tabs do not fit, an arrow shows on each side that hides tabs, as in every program on the toolkit; a click brings the next tab fully into view, and the wheel still scrolls them.
- **The line under each row can be turned off.** Appearance › Rows of tables has the toolkit's two settings, the same in every program: alternating rows (off) and rules (on). A choice of alternating rows made before goes back to off once.

## [0.22.2] - 2026-11-15 07:05

### Fixed
- **The palette puts the whole word first**: a search for a name ranks the item whose word ends there above a longer one that only starts with it. A panel moved to a window of its own closes again with its close button on Wayland.
- **Undo after the Recycle Bin always undoes that step (Windows)**: a move to the Recycle Bin now always records where the item went. Before, it was lost now and then, and Ctrl+Z then undid an older step instead.

## [0.22.1] - 2026-11-15 01:04

### Fixed
- **Two copies open at once no longer hide each other's crash**: when two copies of Classeur ran at the same time, a crash or a forced end of one could go unreported, and its report could be hidden by the clean end of the other. Each copy now keeps its own trace, and the next start shows what it did not see.

## [0.22.0] - 2026-11-14 23:45

### Changed
- **One command palette, with tabs and folders in it**: the palette is the one of the other programs of the family, with the same look and keys. `>` lists the commands and the moves of the panes and dialogs, `:` the settings (a switch flips and the palette stays open), `@` the tabs of every panel (Enter shows one), and `/` the folders: type a path and its folders come as you type, with the recent folders, the bookmarks and the places; Tab completes the path, Enter goes there, Ctrl+Enter opens it in a new tab. The foot of the palette names the prefixes and what Enter, Ctrl+Enter and Alt+Enter do. A command that cannot act now is listed greyed, last, instead of hidden. "Tab 1" to "Last tab" are no longer in the palette: `@` lists the tabs themselves (Alt+1 to Alt+9 still pick them). The palette's memory of what you chose starts afresh.

## [0.21.0] - 2026-11-14 19:21

### Added
- **Select several items with Ctrl and Shift, as in every file manager**: a second Shift+click nearer the first item makes the range smaller; Ctrl+Shift+click adds a range to what is selected; Ctrl and the arrows move the cursor alone, and Ctrl+Space then adds or removes the item under it; Escape on several items keeps the one under the cursor. The rectangle and the keys share these rules. A Shift range no longer keeps the items that Ctrl selected before it (Ctrl+Shift keeps them).
- **Panes and dialogs go where you want them**: the sidebar, the inspector and every dialog (GoTo, batch rename, the settings, the command palette, the sheet of the keys, a question) can float inside the window, open in a window of their own, or dock to the left, the right or the bottom of the window: a right click on a dialog's header, the icons that show over the top of a pane, a drag of a dialog's header, or the palette, which lists these moves for each one open. classeur remembers where each one was, its size and whether the sidebar and the inspector were open, and shows them there at the next start. The inspector now sits at the right of the window, beside every panel.

### Fixed
- **The inspector's text can be selected and copied.** A drag selects across lines in a file's preview (text or code), its name, what it is, its properties' values and a picture's size; Ctrl+C copies the text selected, not the files, until a press elsewhere. The footer's line about the cursor's item, the jobs' paths and errors, the names before and after a batch rename and the files of the name-taken question select the same way.
- **The palette, the keys and quit work over the settings.** While the settings, the sheet of the keys or another dialog was open, Ctrl+K, Ctrl+Shift+P, F1, Ctrl+, and Ctrl+Q did nothing. They now work there too, and the palette lists the settings from inside them. The recorder of a command's keys still records any combination.
- **The update is shown once**: the button of the title bar alone says that a new version is on offer, downloading or ready to restart; the status line no longer repeats it. A failed update is said there.
- **The font settings apply at once.** The interface and monospace fonts took effect only at the next start, and the reading font never; a family chosen in the settings now shows at once, in every window, and Default brings classeur's own back.

## [0.20.2] - 2026-11-14 01:55

### Fixed
- **classeur starts on Windows**: 0.20.0 and 0.20.1 had no Windows download, because Windows refused to start the program (its manifest was broken). This version has it, and it starts.

## [0.20.1] - 2026-11-14 00:52

### Fixed
- **classeur starts on Windows again**: 0.20.0 had no Windows download, because Windows refused to start it. Dialogs also open at their final size, without a jump.

## [0.20.0] - 2026-11-13 23:50

### Added
- **A Diagnostics page in the settings, with a Copy button.** It shows the versions, the system, the graphics adapter (and whether a software rasterizer draws), the window's size and scale, the last frames' times and how much partial redraw drew. If classeur is slow, copy it and send it.

### Changed
- **Windows: classeur.exe says what it is.** Properties > Details and Task Manager show its name, version and publisher. Its windows group under the Start menu's shortcut in the taskbar. The archive has `classeur.com` beside `classeur.exe` for use from a terminal. The window is sharp on each monitor, and paths longer than 260 characters and UTF-8 text work.
- **The licence has its own page in the settings, worded as in the other programs.** It says whether classeur is registered. It offers Buy a licence, a field to paste a key, Choose a licence file… and Remove the licence.
- **A crash of the last session shows in a bar at the top of the window**, in place of a dialog. The bar says what happened and offers Open the report, Copy and Report on GitHub (a new issue with the report in it). Its cross dismisses it.
- **The install is in the settings: an Installation page.** It says where the installed copy is, its version, and whether this copy is the installed one. It shows the menu entry, Settings > Apps, the start with the session and the PATH, with Install, Repair, Upgrade and Uninstall. The palette finds the page ("install").
The command line is `--install`, `--uninstall`, `--status` and `--setup`, as in the other programs. `--status` says what is installed and whether classeur runs. `--install` installs the copy in its own folder. `classeur install`, `uninstall`, `status` and the Setup command (Ctrl+Shift+F12) are gone.
- **A change of language shows at once**: the window, the settings and the sidebar's places (Documents, Downloads, Pictures…) take the new language without a restart.
- **classeur has the same settings and look as the other programs of Froment Software.** Only its theme, Graphite, is its own. It is no longer always dark and flat: it starts light or dark as the system is, with the machined finish, 14 px text (was 13.5) and the usual rounded corners (they were squarer). A setting that you changed keeps your value; Reset in the settings gives the new defaults. The settings open on General, as in the other programs.

### Fixed
- **`classeur --pref name=value` sets a preference for the run**, as in the other programs. It no longer opens a folder of that name.
- **Dialogs and buttons never cut their text.** If a dialog's buttons do not fit on one line, they go on a second line. The bookmarks hint and the batch rename's help wrap, and the batch rename's case choices widen for longer words. Cancel buttons are neutral, no longer red.
- **French done right.** Keys have the names that a French keyboard prints ("Ctrl+Maj+N"), and numbers use the French decimal mark and spacing. The filter fields say "Filtrer…". The batch rename explains each of its fields ({name}, {ext}, {n}, {date}, {time}, {id}) in the language in use. A delete for good asks « Supprimer définitivement « nom » ? ». The palette's foot is shorter, and the window's title writes the name "classeur".

## [0.19.2] - 2026-11-13 18:55

### Changed
- **One licence at one price, and a new pricing page**: the classeur licence is one edition at 29 €, paid once, taxes included. The pricing page shows classeur's icon and name, one card with the price, what the licence gives as a list, one button, then "Before you buy". The licence is named "classeur licence" on the site, at checkout and in the licence file.

## [0.19.1] - 2026-11-13 18:04

### Fixed
- **The Windows download is there again**: 0.19.0 had no Windows archive (its build stopped on a check that read the files with Windows line endings). This version has it.

## [0.19.0] - 2026-11-13 17:02

### Added
- **A crash is reported at the next start**: if classeur's last session ended without closing, the next start says so and offers its report, written on this computer. You can open the report or copy its path. Nothing is sent anywhere. classeur also keeps a log of its messages in its state folder.
- **In the application menu, and with the session**: the copy that the Setup or `classeur install` integrated shows two settings in General. One puts classeur in the application menu (the Start menu on Windows). The other starts classeur with the session.
- **Choose where classeur tells what it did**: Settings > General > Messages sends the messages of a path or names copied, a layout saved, items renamed, an undo, and a copy, move or delete that ended to the system's notifications (System, the default), to classeur's window only (Window), or nowhere (Off). A failure is always told.
- **A licence that supports classeur**: Settings > General > Licence says who classeur is registered to, takes a key pasted or a licence file, and removes it. classeur does the same with or without a licence. The shop opens later: until then its page says "Coming soon".
- **Themes of your own**: under the themes in the settings, a link opens `themes.txt` beside the settings, made from a commented template. A theme written there shows among the others as soon as the file is saved.
- **classeur in French**: the menus, commands, palette, dialogs, messages, sidebar, inspector, jobs, settings and dates read in French, and so do the names that the Setup gives to the application menu and the icons. Settings > General > Language chooses System, English or Français. System follows the language of the system. A change takes effect at the next start.

### Changed
- **The sidebar's filter looks like the palette's search**: a band in a field's colour across the top of the sidebar, as in the palette and the menus.
- **Every tooltip waits the same delay**: the tooltips of the bar's buttons, the rows, the sidebar's devices and the status bar's figures appear after half a second, as the settings' tooltips do. Settings > Delays and menus changes this delay.
- **Dialogs in the middle, with a header**: the copy conflict, the name of a layout, the keys of a command, the batch rename, the confirmations and the crash report open in the middle of the window. They show their title in a strip across their top, with a close button in its corner, and their buttons at the bottom right.
- **The palette remembers what you choose**: its Recent group holds the commands you choose often and lately. A command chosen often stays near the top for weeks, and while you type it comes before an equal match. The list of commands run last from earlier versions is not read. The palette opens once at its default size, then keeps the size you give it.
- **New settings, in groups**: besides the look, the settings now cover the text and its fonts, the scrolling, the keyboard's repeats, the delays of tooltips and menus, the rendering and the updates. Each setting is in its group, and the technical ones are folded under an Advanced part. Light or dark replaces "Follow the system" (dark by default, as before), and the finish is a choice. The settings export to JSON, TOML or INI and import back. The names in the settings file changed: a look set before (theme, text size, rounding, density, animations, scrolling, title bar, alternating rows, dimmed panels) goes back to its default once.

### Fixed
- **The check mark and the zoom's percent stay readable in every theme**: on a light accent they are drawn dark, instead of white.

## [0.18.0] - 2026-11-13 00:38

### Added
- **A long copy says when it ends, even behind other windows**: a copy, move or delete that lasted long enough to show in the jobs' view, ended while classeur is not the window in front, is told by a notification of the system.

### Changed
- **Every context menu has a search field**: typing in an open menu keeps the items with those letters.
- **The buttons of an empty folder have their icons**: New folder, Paste, Go up, Try again and the others, under an empty folder or a filter that hides every row, show an icon, the first one highlighted.

## [0.17.2] - 2026-11-12 14:03

### Fixed
- **Space in an empty filter no longer shows a space**: the inspector opens and the filter stays empty, with no space shown for a moment.

## [0.17.1] - 2026-11-12 13:31

### Fixed
- **A picture in the inspector takes the pane's whole height**: its preview fills the room under the properties, fitted in it, with its zoom buttons at the pane's foot instead of over the picture's edge.

## [0.17.0] - 2026-11-12 12:26

### Added
- **The sidebar finds the network's file servers**: its Network section is always there and lists, after the shares mounted, the devices that announce a file service on the local network (SMB, SFTP, WebDAV, NFS, AFP, FTP), and on Windows the computers of the network neighbourhood. A click opens the device's first service in the tab, its menu lists each one, and Find network devices (Ctrl+Shift+F5) searches again.
- **The Recycle Bin opens in a tab on Windows**: trash:/// and the sidebar's Recycle Bin list the items of every drive by their original names, with the folder each was deleted from, its size and when it was deleted. Put back returns the selection where it was (a name taken there is asked about), Empty the trash deletes every item after the question, and Delete in the trash deletes for good after the question.
- **Thumbnails of more kinds of files**: the grid shows the thumbnail of a PDF, a video or a document when the system has a thumbnailer for it, and the thumbnails are kept in the system's cache on the disk, shared with the other file managers; a large picture's thumbnail comes from that cache the next time.
- **The inspector shows PDF files and videos**: a PDF shows its first page and a video one of its frames, from the thumbnails the system makes, with a line under the picture that says which.
- **The program's own commands in the palette**: Quit (Ctrl+Q), Restart classeur, New window (Ctrl+N), Minimize, Maximize and Full screen (F11) of the window, Check for updates, Install the update and Restart to update when there is one, About classeur, the website, Report a problem, Release notes, Open settings folder, Copy the version, Next and Previous theme, Compact rows, Animations, Larger, Smaller and Default text size, Reload all folders, Reset the layout and Clear thumbnails. Each has its keys, and the palette finds them by the words a person types ("exit" finds Quit).

### Changed
- **Space opens the inspector from an empty filter too**: in the filter with nothing typed, Space shows or hides the inspector, as it does in the list, and types no space (no name starts with one); once letters are typed it is a space.
- **Put back asks when the name is taken**: an item of the trash whose place holds another file now asks to replace it, skip it or keep both, as a copy does, instead of failing. Delete on an item of the trash deletes it for good after the question, with its record, instead of moving it to the trash again.

### Fixed
- **Relative dates turn at midnight**: with relative dates on, "Today" becomes "Yesterday" just after midnight, even when the window is idle.
- **Escape cancels a bookmark's drag**: the bookmarks keep their order, and letting go of the button afterwards opens nothing, as with the other drags.

## [0.16.3] - 2026-11-12 10:46

### Fixed
- **A paste in a text field no longer freezes the window**: Ctrl+V in the filter, the address, the rename, the batch rename's fields and Go to asks the clipboard without waiting, and the text appears as soon as the program that copied it answers. A slow or hung program no longer stops the window.

## [0.16.2] - 2026-11-12 09:55

### Fixed
- **A tab torn off no longer holds the window**: its new window starts in the background, and the tab leaves once that window has started; if it cannot start, this is said and the tab stays. The Setup's check at the start no longer delays the first frame.
- **Large folders stay fluid with a large selection**: the inspector's summary of several items, the types' popup and the grid no longer go through every entry at each frame, and dragging many files no longer checks each of them at each frame. The inspector's preview of a folder lists its first 200 entries and counts the others.
- **A paste no longer freezes the window**: Paste, Paste into folder and the batch rename's "Names from the clipboard" ask for the clipboard and go on; the copy, the move or the names start when the other program answers. A program that holds the clipboard and does not answer is given up after 2 seconds, and the window never stops meanwhile.
- **The window no longer waits for a slow desktop or disk** when it opens a file with its application or with Open with, opens a terminal, or saves the settings, the layouts and the Setup's answer: these run in the background, and a program that cannot start is still reported.

## [0.16.1] - 2026-11-12 07:57

### Fixed
- **Large folders no longer hold the window**: a folder of tens of thousands of items is sorted and filtered on a worker as it is read, so the window does not stop when it comes or when a change in it makes it read again. A filter typed in it answers faster, the footer and the list do no work per item at each frame, and a paste of many items selects them at once.
- **A hung share no longer holds the other folders**: when every reader waits on a share that does not answer for a second, classeur starts another, so local folders, the address's suggestions and the rest still open.
- **The thumbnails on screen come first**: after a fast scroll through a grid, the cards on screen get their pictures at once instead of after every card passed; a picture changed on disk gets a new thumbnail; the names of the types no longer wait for the pictures, and a grid of many small cards no longer loses its pictures and icons at each frame.
- **Measures go on in the other panels**: going to another folder in one panel no longer stops the folder measures of the other panels. Measuring a very large tree takes far less memory, and the measures kept are limited to the 20 000 most recent.
- **Closing does not wait for a search**: closing the window stops a running flat search and the folder measures at once. A read of a share that does not answer no longer holds the window open: classeur waits half a second at most.
- **A folder changed while it is read is read again**: a file made or removed while a folder is being read now shows once the read ends; before, the change was missed until the next one.
- **A search of a large tree stays smooth**: while the flat search reads, each batch of results goes among the rows already shown, without filtering and sorting all of them again. A search of a tree of many thousands of files no longer slows down as it goes.
- **A slow disk or share no longer holds the window**: a rename, a new folder or file, a batch rename, an undo or redo of them, opening a share's address and reading the sidebar's places are done in the background. While a rename is being done, its field stays open; a name refused is said and kept in the field, as before. The sidebar keeps its list until the new one is read. The name of a tab on a share and the share's address in the path are read with the folder, no longer at every frame.

## [0.16.0] - 2026-11-12 02:58

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

## [0.15.2] - 2026-11-11 23:03

### Added
- **The details header's menu resets a column**: a right click on a column's title offers to give it back its own width and to leave its sort, the rows can go back to no sort, and Default columns shows every column again at its width and place (gui_toolkit 0.195.0).

## [0.15.1] - 2026-11-11 22:42

### Changed
- **The palette forgives a slip**: a word typed with a letter missing, one too many, one for another or two swapped still finds its command or setting ("new foldr" finds New folder), after every exact match. The palette's field has the darker background of a field, and its edge runs all along it (gui_toolkit 0.194.0).

## [0.15.0] - 2026-11-11 21:13

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

## [0.14.5] - 2026-11-11 11:25

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

## [0.14.4] - 2026-11-11 02:27

### Changed
- A column's title clicked a third time goes back to the order there was (the names going up): its first way, the other
  way, then the names'. The sort commands (Ctrl+Alt+1 to 4) go the same way round.

## [0.14.3] - 2026-11-11 01:32

### Fixed
- The rectangle selection in the Grid and Columns views (it was the Details and List views' only): from the empty part,
  between the cards too, it selects the items it touches. Ctrl and a drag from a card deselects as in the list.
- A right click on the empty part of the Grid view opens the folder's menu (the Columns view's goes through the same
  place now).
- A test goes through the pointer's gestures in every view: the rectangle, the empty part's menu, Ctrl and a drag, a
  file dragged onto a folder.

## [0.14.2] - 2026-11-11 01:14

### Fixed
- Files dragged in the window are classeur's own drag (File Pilot's): the folder under the pointer (a row, a tab, a place
  or a bookmark of the sidebar) is lit, a ghost beside the pointer says what a release does, and the release makes the
  job. The system's drag, which takes the files at the window's edge (to another program, the desktop), blocked the
  window: nothing was lit, and on some compositors the drop never came.
- A dragged tab's ghost, the place it lands and the half a new panel takes show at once: they waited for the tab's picture
  (read back from the renderer for the system's drag), which comes late on some systems, never on some.
- A tab dragged from another classeur window shows its ghost where it lands in this one's row, and lands there.
- 0.14.1 was not published (its Windows build failed a test that assumed the tabs' widths).

## [0.14.1] - 2026-11-11 00:35

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

## [0.14.0] - 2026-11-10 23:17

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

## [0.13.1] - 2026-11-10 21:57

### Fixed
- Where the system has no picture for an icon (no icon theme, a type it does not know), Lucide's folder or file stands
  in: no empty icon. (The 0.13.0 release stopped on this: the CI's machines have no icon theme.)

## [0.13.0] - 2026-11-10 21:50

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

## [0.12.0] - 2026-11-10 11:55

### Added
- Windows: classeur.exe has its icon (Explorer, the taskbar, the window), from `res/classeur.rc`.
- Windows: `classeur` typed in cmd or PowerShell gives its output and exit code: `install` writes classeur.com (the
  toolkit's console launcher) beside classeur.exe with the PATH entry; a folder opens a window and gives the prompt back.

## [0.11.0] - 2026-11-10 11:44

### Changed
- The Setup is classeur's own screen over the toolkit's controller: a head with the state in its colour, sections as the
  settings page has them (Location, Options, On this system), the buttons in a bar at the foot.
- The menus' search is a field at their top, from edge to edge: a magnifier, what is typed, a caret (the toolkit's).

### Fixed
- On Windows, an install in the default folder asked to be repaired after its restart (the toolkit took the record of
  the default folder for no record).
- The Setup's test wrote its answer in the person's config: a headless run keeps no answer.

## [0.10.0] - 2026-11-10 11:26

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

## [0.9.0] - 2026-11-10 11:13

### Added
- The path field suggests the folders of the path typed: Up and Down choose, Tab completes, Enter or a click goes.
- The zoom's slider: a row per step with its icon, its name and its percent; a click on a row goes to that step.
- The palette: with nothing typed, the commands run last under Recent, then every command under its group's title; the
  wheel scrolls it, a bar shows where; each row shows its aliases, and its group while searching.

## [0.8.0] - 2026-11-10 09:57

### Changed
- The jobs run in the background with their view beside the window, not over it: a panel over the footer that leaves
  the window working, opened by itself once for a job that runs on, sent away by Background or Escape, brought back by
  the footer's button (with the jobs' progress) or Ctrl+Alt+J.

## [0.7.0] - 2026-11-10 09:53

### Added
- The columns view filled column by column, scrolled sideways (the wheel too); Up and Down along a column, Left and
  Right across.
- The jobs' window (Ctrl+Alt+J, or the footer's button): every copy, move and trash of the session, what failed, Cancel,
  Retry.

### Fixed
- The errors of the jobs' window and of batch rename in the theme's red, not a magenta.

## [0.6.0] - 2026-11-10 08:18

### Added
- Groups folded and unfolded by a click on their title.
- The tree in the names and the columns views too.

## [0.5.0] - 2026-11-10 08:09

### Added
- Keys of one's own from the palette: Ctrl+Enter (or a row's +) records the keys of the chosen command, one key or a
  sequence of two (Ctrl+K, then T); Backspace gives it its own keys again. Aliases: the letters typed, Alt+Enter on a
  command, then those letters find it first.
- The tree view (Ctrl+Shift+E): folders opened in place with a chevron, Right and Left.
- Group by date, type or size (Ctrl+Alt+5, 6, 7, or the menus' Group by): a title above each group.

## [0.4.0] - 2026-11-10 07:52

### Added
- Panels split below (Ctrl+Shift+J, or a tab dragged to a panel's bottom quarter): columns of panels, each lower panel
  with its tabs at its top.
- The details' columns: shown or hidden from the header's menu (a right click on it), their titles dragged to reorder
  them.
- Tabs torn off: a tab dragged out of the window becomes a window of its own (`classeur --window <folder>`); dragged onto
  another classeur window, it joins its tabs there.

## [0.3.0] - 2026-11-10 07:35

### Added
- File Pilot's zoom slider: a click on the footer's percent shows a vertical slider; dragged, the view goes step by step
  and the cards grow or shrink smoothly between the steps.

### Fixed
- Windows: names that start with a dot are hidden files; names joined with the system's separators; a rename tried again
  while the shell reads the file; the batch's folder read after its renames. The tests and the checks run on Windows in CI.

## [0.2.0] - 2026-11-10 07:08

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

[0.51.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.51.0
[0.50.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.50.1
[0.50.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.50.0
[0.49.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.49.0
[0.48.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.48.1
[0.48.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.48.0
[0.47.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.47.0
[0.46.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.46.1
[0.46.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.46.0
[0.45.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.45.1
[0.45.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.45.0
[0.44.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.44.0
[0.43.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.43.0
[0.42.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.42.0
[0.41.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.41.2
[0.41.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.41.1
[0.41.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.41.0
[0.40.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.40.0
[0.39.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.39.1
[0.39.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.39.0
[0.38.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.38.0
[0.37.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.37.0
[0.36.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.36.1
[0.36.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.36.0
[0.35.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.35.0
[0.34.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.34.0
[0.33.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.33.0
[0.32.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.32.2
[0.32.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.32.1
[0.32.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.32.0
[0.31.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.31.0
[0.30.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.30.0
[0.29.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.29.0
[0.28.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.28.0
[0.27.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.27.0
[0.26.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.26.0
[0.25.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.25.0
[0.24.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.24.0
[0.23.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.23.0
[0.22.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.22.2
[0.22.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.22.1
[0.22.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.22.0
[0.21.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.21.0
[0.20.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.20.2
[0.20.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.20.1
[0.20.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.20.0
[0.19.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.19.2
[0.19.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.19.1
[0.19.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.19.0
[0.18.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.18.0
[0.17.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.17.2
[0.17.1]: https://github.com/sachahjkl/classeur/releases/tag/v0.17.1
[0.17.0]: https://github.com/sachahjkl/classeur/releases/tag/v0.17.0
[0.16.3]: https://github.com/sachahjkl/classeur/releases/tag/v0.16.3
[0.16.2]: https://github.com/sachahjkl/classeur/releases/tag/v0.16.2
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
