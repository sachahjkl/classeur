# System shell context menu

Right-clicking entries or a folder background opens `classeur`'s menu immediately with its own commands, while third-party
system actions (Windows shell extensions such as 7-Zip, Git, VS Code, or Send to; Linux KIO service menus, Nemo actions,
and Thunar custom actions) load asynchronously via `ui.Shell_Menu` (`gt:ui` over `gt:desktop`'s `Context_Menu`).

## Decisions

- **Toolkit widget (`ui.Shell_Menu`)**: `Entry_Menu.shell` uses `ui.Shell_Menu` directly instead of keeping a custom
  callback/post/rendering wrapper in `classeur`. `ui.Shell_Menu` manages the refcounted `ui.post` gate, lazy GPU
  icon textures (Windows `MIIM_BITMAP` icons and Linux icon-theme icons), recursive submenus, and safe teardown.
- **No wait on menu open**: `entry_menu_open` calls `ui.shell_menu_query` and opens `ui.menu` immediately. Stale
  serials are dropped when a newer menu opens first.
- **Placement below `classeur`'s own items**: system entries appear in a separated section near the bottom of the menu
  (above `Properties` on an entry, at the end on a folder background) only once items arrive. `classeur`'s own commands
  never shift while the system query runs, and systems with no matching extensions show no empty placeholder.
- **No duplicate built-in verbs**: `SHELL_EXCLUDE_VERBS` filters out standard Windows shell verbs that `classeur` already
  offers (`open`, `openas`, `opennew`, `explore`, `cut`, `copy`, `paste`, `link`, `delete`, `rename`, `properties`).
- **Prompt release**: when `ENTRY_MENU` closes, `ui.shell_menu_clear` releases any held native `IContextMenu`, `HMENU`,
  and icon textures. Because `gt:desktop` processes a queued `invoke` before `clear`, clicking an item right as the
  menu closes still runs its action.
- **"Open with" is the toolkit's (`ui.Open_With`)**: `entry_menu_open` asks it for the file under the cursor, and a
  chore reads the applications and their icons. The submenu shows them, the default first. classeur keeps the start
  itself: `ui.open_with_chosen` gives the application, and `launch` starts it on a worker. That path reports a failure
  in a toast and, in a headless test, records the start in `app.opened` instead of running it. `open_with_run` is not
  used because it has neither of these.
- **Headless isolation**: when `app.headless` is true, `entry_menu_open` skips querying the host desktop so tests never
  read the person's `uca.xml` or Windows registry; tests inject items directly through `ui.shell_menu_apply`.
