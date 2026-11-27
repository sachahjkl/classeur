# classeur: intent

classeur is a file manager: tabs in panels, a command palette, fast search, an inspector, keyboard first. Its model is
File Pilot. This folder follows <https://srcmd.org>: it records why the code has its shape, the decisions, the refused
alternatives, the subtle points. The map of the code (packages, files, threads, tests) is
[docs/architecture.md](../../docs/architecture.md); building and testing is
[docs/development.md](../../docs/development.md); the preferences are
[docs/configuration.md](../../docs/configuration.md).

## Overview

- One process per person (`gt:instance`), holding one or more windows on a shared `host.Shared` (`App_Hub`: one graphics
  device, one font atlas, one theme; see [features/windows.md](features/windows.md)). The interface is built again at
  every frame from each window's data; the data changes only on the interface's thread.
- `src/fs` is the file system with one interface on every system. The interface (`src/*.odin`) never says which system
  it runs on: `classeurtool check` refuses `ODIN_OS` outside `src/fs` and `src/system_<os>.odin`.
- Workers (`gt:tasks` pools in `App`) do every read and write; a task gets a copy of what it needs and posts its result
  with `ui.post`. Separate pools keep slow work from blocking quick work:
  - `app.pool`: folder reads, places, shares, launches. It grows while a read of a share hangs.
  - `app.edit_pool`: one thread, the interface's own changes to files, in the order asked.
  - `app.thumb_pool`: two threads, the thumbnails the toolkit's cache asks for (newest first, a card scrolled past
    not read), the icons and the types' names.
  - the measures' pool: folders measured all the way down.
- The jobs (copy, move, trash, delete) run one at a time on a thread of their own; a name taken asks the interface and
  the job waits on a semaphore.
- Files written while the window runs (the session, the layouts) are each a `store.Writer`; the preferences are a
  `config.User_Writer`.

## State machines

- A tab's read: asked (with a `serial`), then done; an answer with an old serial is dropped.
- The start's read of the session and the layouts (`app.start_read`): Reading, then Applied or Dropped (the person
  changed the panels first); nothing of them is written while Reading. See [features/session.md](features/session.md).
- A job: counting, copying, asking (name taken), done or cancelled.
- Who has the keyboard (`app.keys_at`): see [features/keyboard.md](features/keyboard.md).
- A paste: asked of the clipboard, then started when the files come (a `Clipboard_Data` event).
- The undo stack: steps of (before, after) paths, undone and redone through free names.

## Subtleties

- The interface's thread never waits: not a `stat`, not a mount table, not a clipboard of files. A share that hangs
  must never freeze the window. The preferences are still read there, before the first frame; the session and the
  layouts are read on a worker ([features/session.md](features/session.md)).
- A frame does no work in proportion to the number of entries: orders, counts and sizes are made when the data changes
  and kept.
- The Recycle Bin of Windows is no folder: `fs.list` reads every drive's `$I` records into a listing whose entries
  carry their real paths (`Listing.trashed`).
- A rename never replaces (`fs.rename`).
- The dates' words, units and order are the toolkit's (`gt:timefmt`), but classeur converts each date to the local time
  itself, with the time zone's region (`app.tz`): timefmt takes one offset, today's, and a file's date from the other
  side of a change of the clock (summer time) would read an hour off. timefmt then writes that wall clock with an
  offset of 0 (`format.odin`).
- The person reads the name `APP_TITLE` ("Classeur"); `APP_NAME` ("classeur") stays the technical one. The settings,
  the state and the caches are in the vendor's folder (`APP_FOLDER`, `FromentSoftware/Classeur`). `app_run` moves the
  folders of the old name there once (`platform.user_dirs_move`). The single instance's name keeps `APP_NAME`: an old and
  a new copy still find each other.
- The tests open the real program headless; they wait for the answers with `wait_read` (`app.answers_due`), never for
  a delay.

## File Index

- [layers.md](layers.md): how the program grew layer by layer, and the decisions of each layer (jobs, the clipboard of
  files, the trash, undo, batch rename, thumbnails), what of the file view is the toolkit's; the known gaps
- [features/keyboard.md](features/keyboard.md): the order in which a build reads the keys, the person's keys and
  aliases (the toolkit's keymap, classeur's ids), who has the keyboard, why F6 stays classeur's
- [features/session.md](features/session.md): the session and the layouts read on a worker at the start, the state
  machine of that read, why a late session does not replace what the person did, no write before the answer
- [features/palette.md](features/palette.md): the command palette's sources (commands, moves, settings, `@` tabs, `/`
  folders), what reads on the workers, what each choice does, the buttons go to reaches, the commands with arguments
- [features/goto.md](features/goto.md): GoTo and the path field: one set of rows, the deep search below the current
  folder (the index read on a worker, the matches on a worker, the serial), why a click on the toolbar opens no dialog
- [features/windows.md](features/windows.md): in-process multi-window (`App_Hub` sharing `host.Shared`), instant tab
  extraction that moves the `^Tab` directly, preloaded graphics device at startup, and instant close (`host.host_hide`,
  cancellable mDNS discovery, direct `tasks.stop`)
- [features/debug-panels.md](features/debug-panels.md): the debug window's panels, one per part of the program that
  keeps state; acts that call the program's own procedures; a simulated failure sets the real failure's state
- [features/context-menu.md](features/context-menu.md): asynchronous system shell context-menu integration via
  `gt:desktop`'s `Context_Menu` (Windows shell extensions, Linux KIO/Nemo/Thunar actions) without delaying menu open
- [data/folder.md](data/folder.md): a folder as a panel shows it: the selection as flags, the worker that prepares the
  order, the serial of a read, edits in order
