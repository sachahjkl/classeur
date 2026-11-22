# The command palette

classeur's palette is the toolkit's (`ui.Command_Palette`; its intent is gui_toolkit's `src/md/features/palette.md`):
the same look, keys and prefixes as in the other programs. classeur gives it its data as **sources**
(`src/palette.odin`, `src/palette_sources.odin`); the palette asks them, ranks their items on a chore and returns the
choice as a source and an id.

## The sources

| Prefix | Source | Items | Choosing |
|---|---|---|---|
| `>`, plain | the commands (`ui.palette_commands`) | `COMMANDS` by group, the keys in effect, the aliases as tags (the toolkit's keymap) | runs it; a command with arguments asks them in its form first; Ctrl+Enter records a key of one's own, Alt+Enter makes the letters typed its alias (both the toolkit's) |
| `>`, plain | the views' moves (the toolkit's) | float, dock, re-attach, close each open view | the toolkit runs it |
| `:`, plain | the settings (`prefs_page.palette_settings_add`) | each setting the pages show | a switch flips, the palette stays; another opens its control under its row (the run mode) |

Shift+Enter, in every source, goes to where the item lives (the toolkit's go to): the settings page on a setting, or the
button that runs a command.

## Go to a command's button

A button whose click runs a command of `COMMANDS` states it at its build (`icon_action`'s `command`, else
`ui.act_command`): Shift+Enter on the command shows that button, focused and lit. Named today:

- the top bar: Sidebar (`sidebar`), and the focused panel's New tab (`tab_new`);
- the focused panel's toolbar: Back, Forward, Up, Lock, Bookmark (`back`, `forward`, `up`, `lock`, `bookmark`), and the
  empty part of the path, which opens GoTo (`goto_popup`);
- the focused panel's footer: Types shown (`types`, which opens its menu), Search subfolders (`flat`), Jobs (`jobs`);
- the inspector's close button (`inspector`).

## Commands with arguments

A command that asks one value before it acts states it (`Command.arguments`, a `config.Def` each); the palette asks it in
its form, and the choice runs `Command.run_with` with the value. Its keys still run `Command.run`, which asks in a dialog
of its own.

| Command | Its argument | Its dialog, kept for its keys |
|---|---|---|
| Save layout (`layout_save`) | the name, free text; empty: "Layout n", the next | the prompt (`LAYOUT_NAME_VIEW`) |
| Open layout (`layout_open`) | the layout, among the saved ones (`Palette_Commands_Options.choices`: `layout_choices`) | the menu (`LAYOUTS_MENU`), which also deletes a layout |
| `@`, plain | the tabs | every tab, under its panel's name; the shown one marked | its panel gets the keyboard and shows it |
| `/`, plain | the folders | the folders of the path typed, and the recent folders, bookmarks and places the letters find | goes there in the tab; Ctrl+Enter in a new tab; Tab completes the path |
| `/` | files (`ui.Palette_Files`) | typo-tolerant files and folders under the current folder, ranked by frecency (`gt:filesearch`, shared with `deep_find.odin`) | goes there (files select in their folder); Ctrl+Enter in a new tab; records frecency |

## Decisions

- **The tabs source replaces "Tab 1" to "Last tab" in the palette.** They showed once "tab" was typed: a rule of
  classeur's own. They stay commands (Alt+1 to Alt+9), out of the palette's table.
- **A command that cannot act now is listed, greyed and last** (the toolkit's rule), not hidden as before. The table
  of the commands source is made once, at the start: the labels are translated where they show, and the keys and
  aliases in effect are the toolkit's to follow. What can act is a bit per gated command, read at each build (three
  commands), and a change of it bumps the source's version: the palette compares versions, never `disabled`.
- **The folders are read on the workers.** A question for a path lists its folder on `app.pool`; the job also gets a
  copy of the recent folders, the bookmarks and the places (lists of a few dozen) and finds them by the letters there.
  The answer is built in the job's own arena and given whole (`ui.palette_answer`) by the job itself: an end is safe
  from any thread. The interface's thread never lists a folder nor matches a name.
- **One listing per folder while typing.** The folders source is asked at each letter. The last folder listed is kept
  (`Folders_Cache`: its path, its modification time, its folders' names, under a mutex): a job that finds the same path
  and the same time takes the names from there, after one `stat`. A folder changed since (an entry made or removed
  changes its time) is listed again.
- **What `/` means.** The prefix is the path's first separator on Linux and macOS: `/home/x` lists `/home`'s folders
  whose names have `x`. `~` is the home folder. On Windows a drive or a share after `/` (`/C:\Users`) is a path. Words
  after `/` find the recent folders, the bookmarks and the places.
- **Ctrl+K and Ctrl+Shift+P are the toolkit's** (`ui.palette_keys`), and so is its command (`ui.palette_command`): the
  sheet lists it, classeur's table has no line for it, the "…" menu builds its line from it. The keys wait while the
  recorder is open, as the window's commands do: it records any chord.
- **The settings source is added once.** Its page options are read when it needs them (`options_page`, a procedure):
  the updater and the themes shown as they are then.
- **Personal keys and aliases are the toolkit's** (`ui.Keymap`, gui_toolkit's
  [src/md/features/keymap.md](../../../ext/gui_toolkit/src/md/features/keymap.md)): its recorder, Alt+Enter, an alias
  typed whole put first. Classeur had them alone and the toolkit took them; [keyboard.md](keyboard.md) says what
  classeur keeps.

- **The choice is taken at the top of the build** (`palette_choose`, before anything is built). The views, the settings
  page among them, are built first in `views_frame`: a value the run mode writes later in the build would show in the
  palette one frame before the page. The palette's keys stay after the views' (`palette_keys_read`).
- **Only the focused panel's buttons state their commands.** The commands act on the panel with the keyboard; the same
  button of another panel acts on its own panel, and a name kept for the last panel built would send go to there.
- **The dialogs that stay.** GoTo (`goto_popup`) shows where each letter typed leads, a preview the palette's `/` source
  already gives. Rename and New folder name the item in its row, in place (Tab goes to the next row). Batch rename asks
  several values with the preview of each new name. The name taken (replace, skip, keep both) and the confirmation of a
  deletion are a job's questions, not a command's values.

## Refused

- **An argument's default that changes** ("Layout 3", the next free name): a `config.Def`'s default is the table's,
  made once. The form's empty name means the next free one.

- **Decoding a chosen index by ranges** (commands, then settings, then moves): it broke when the table was made again
  between the choice and its reading. A choice is a source and an id.
- **GoTo's suggestions as the folders source** (`goto_rows`): it matches on the interface's thread, at each key.

## Subtle points

- The usage memory's keys are `<source>:<id>` (`command:tab_new`): the file of before (`palette_choices`) is not read;
  the memory starts again in `palette_choices.txt`.
- The tabs' ids last one run: the tabs source does not remember its choices.
- The tabs source follows the panels with a small signature made while the palette is open (`poll`): the ids, the
  paths, which tab is shown, which panel has the keyboard. A few dozen tabs: no pass over a folder's entries.
