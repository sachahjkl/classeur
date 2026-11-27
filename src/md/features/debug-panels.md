# Debug panels

classeur shares its own state and acts with the toolkit's debug window (gui_toolkit's `docs/debug.md`): Ctrl+Alt+Shift+D
in a debug build, and the tools through the devtools (`tk cdp debug`, `debug-set`, `debug-press`). The code is
`src/debug_panels.odin`.

## Purpose

A file manager's bugs live in state that the window does not show: a read that never came back, a watcher that lost a
folder, a cache that holds what it should have dropped, an undo step whose answer is due. The panels show that state
and let a person or a tool make the program do its own work on demand, so a bug is reproduced in a few clicks and a
test drives the same acts.

## Decisions

- **Ctrl+Alt+Shift+D is the toolkit's**: it opens the debug window in a debug build and in the tests. Compact rows,
  which had that key, took Ctrl+Alt+Shift+R (rows): in the tests the toolkit read the key first, and the command
  never ran.

- **One panel per part that keeps state**: Tabs (the folder read, the view), Selection (with the rectangle), Thumbnails,
  Watcher, Undo, File search (GoTo's index), Jobs, Updates, Look. A panel is the part's, not a dump of `App`.
- **Acts call the program's own procedures**: Read again is `tab_load`, Clear is the command's `act_app_thumbs_clear`,
  Undo is `act_undo`, Check now is the updater's `check_now`. A simulated failure sets the state that the real failure
  sets (a refused folder: `listing.error = .Denied`), so the program's own empty state, buttons and Try again run.
  Refused: acts with their own code path, which would test the panel, not the program.
- **Only the interface's state**: a panel runs in the window's build. It reads what the interface's thread owns; the
  jobs' counters are atomics, read as the jobs' view reads them. No panel reads the disk or waits.
- **Live values where a person tunes something**: the tick's time (`app.check_ms`, from `CHECK_ANIM_MS`), the
  system's thumbnails, a tab's zoom, flat, tree and grouping. A grouping chosen reads the folder again, as the menu does.
- **A release has none**: `debug.ENABLED` is on in a debug build and in the tests; a release compiles every call away.

## Subtle points

- "Give the folders again" empties the watcher's copy of its folders; the next frame's `watcher_update` then gives
  every tab's folder, as at the start.
- The panels' tests run twice: on a bare `ui.State` with a zero `App` (every panel lists, values take a set, an act with
  nothing to act on says so), and on a real window for the acts that read folders.
