# Windows, fast start, and instant close

One process owns every window that it opens, whether started normally, opened by `New window` (`Ctrl+N`), or torn off from a tab. Every window shares one `host.Shared` (one graphics device, one set of shaders, one font atlas, one theme).

## Decisions

### In-process multi-window (`App_Hub`)

- `App_Hub` holds the process's `host.Shared`, its loaded icon and monospace font IDs, and the list of open `^App` windows.
- `App.shared` points to `hub.shared` (or to `App.shared_own` when a test opens one window without a hub).
- Tearing off a tab (`tab_window`) detaches the `^Tab` from its panel and opens a new `^App` on `hub.shared`, moving the `^Tab` directly into the new window's panel. The new window keeps the tab's loaded listing, selection, scroll, history, filter, sort, and zoom without re-reading the disk.
- `New window` (`Ctrl+N`) opens a new `^App` on `hub.shared` at the home folder.
- `app_run` drives every open window in one loop (`host.hosts_wait` and `app_frame`). When the first window closes while another stays open, `host.host_close` hands the renderer to the remaining window (`gui_toolkit`'s `first-window.md`).
- A tab dragged out of one window and dropped on another window of the same process carries `<pid>:<window_id>:<tab_id>:<path>` in `TAB_MIME`. When the source window's drag completes with `.Move`, it parks the detached `^Tab` in `hub.handoff`; the target window's `.Drop` claims that `^Tab` directly instead of reopening the path from disk. If the drop went to another process, the unconsumed handoff tab is destroyed at the end of the round.

### Refused alternatives

- **Spawning a new OS process (`classeur --window <path>`) on tab tear-off or `Ctrl+N`**: each process paid full dynamic linking, Vulkan/D3D device creation, shader compilation, font loading, preference loading, worker startup, and a fresh folder read (~250–350 ms), and discarded the tab's listing, selection, scroll, and history. `--window` stays on the CLI for external launches only.
- **Pre-warming a hidden window per tab**: keeps idle swap chains and UI states per tab, and on Wayland (`can_hide_windows() == false`) an unmapped window cannot hold a configured toplevel or swap chain until shown anyway. Sharing `host.Shared` already opens a second window in a few milliseconds (surface creation plus one compositor configure).

### Faster cold start

- `app_run` calls `render.preload_device()` as soon as the single-instance check confirms that this process will open a window (or when started with `--window`). The graphics driver loads on a background thread while `user_dirs_move`, `host.program_start`, time-zone loading, and Wayland/Win32 window setup run in parallel.

### Instant close

- When a window closes, `app_run` records its placement while the window still exists, then calls `host.host_hide` immediately. On Wayland and Windows the window leaves the screen before any worker stops or any file flushes.
- When the last window closes, `instance.serve_stop` runs before `updates_stop` and `app_close`, so an immediate relaunch does not forward into a closing process.
- `fs.network_devices` takes an atomic `cancel: ^bool` and polls its UDP sockets with a short timeout (20 ms) instead of blocking for 1500 ms uninterruptibly. `app_close` sets `app.network_cancel` so closing right after startup never waits for `QUIT_WAIT_MS` (500 ms).
- `app_close` stops its four task pools with `tasks.stop(..., bound)` (condition-variable wait) instead of spawning four extra stopper threads with 2 ms sleep loops.

## Subtleties

- Only the primary window (`!standalone`) owns the session file, the views file, the palette memory file, and the updater. Secondary windows opened by tab tear-off or `Ctrl+N` run with `standalone = true`.
- `instance.MESSAGE_QUIT` (`--quit`) closes every open window in `hub.windows` so an installer or update can exit the whole process cleanly.
- If a window was hidden with `host.host_hide` before `app_close`, `app_close` skips `placement_keep` so the hidden window does not overwrite the saved placement.
