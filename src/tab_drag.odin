package classeur

// Tabs dragged (File Pilot's): along their row to another place, onto another panel's row to move there, onto the right
// quarter of a panel to open a new panel beside it with the tab, onto its bottom quarter for a new panel below it. The tabs' boxes of the last frame (`tab_rects_last`)
// and the panels' say where the pointer is; the move is made before the build that follows the release.

import "core:strings"
import "gt:draw"
import "gt:process"
import setup "gt:setup"
import "gt:platform"
import "gt:ui"

Tab_Rect :: struct {
	panel, index: int,
	rect:         ui.Rect,
}

Tab_Drag :: struct {
	active:       bool,
	panel, index: int,
	tab:          u64,              // the tab's id (the tabs may shift while it is dragged: it is found again)
	pending:      bool,             // released: the move is made before the next build (the panels are built now)
	to, at:       int,
	split:        Split,
}

// Where a tab let go makes a new panel: none, a column at the right, a panel below.
Split :: enum u8 { None, Right, Below }

// Before a build: the move of a tab released in the last one.
tab_drag_apply :: proc(app: ^App) {
	d := &app.tab_drag
	if !d.pending { return }
	d.pending = false
	for p, pi in app.panels {
		for t, ti in p.tabs {
			if t.id == d.tab { tab_move(app, pi, ti, d.to, d.at, d.split); return }
		}
	}
}

// Where a tab let go at `pos` goes: a panel and the place in its row, or a new panel after `panel` (`split`).
@(private = "file")
tab_drop_place :: proc(app: ^App, pos: [2]f32) -> (panel, at: int, split: Split, ok: bool) {
	// a row of tabs: before the tab whose middle is right of the pointer
	for tr in app.tab_rects_last {
		r := tr.rect
		if pos.y < r.min.y || pos.y >= r.max.y { continue }
		if tr.panel >= len(app.panels) || tr.panel >= len(app.panel_rects) { continue }
		pr := app.panel_rects[tr.panel]
		if pos.x < pr.min.x || pos.x >= pr.max.x { continue }
		at = 0
		for o in app.tab_rects_last {
			if o.panel == tr.panel && pos.x > (o.rect.min.x + o.rect.max.x) * 0.5 { at = o.index + 1 }
		}
		return tr.panel, at, .None, true
	}
	for pr, i in app.panel_rects {
		if i >= len(app.panels) { break }
		if pos.x < pr.min.x || pos.x >= pr.max.x || pos.y < pr.min.y || pos.y >= pr.max.y { continue }
		if pos.x > pr.max.x - (pr.max.x - pr.min.x) * 0.25 { return i, 0, .Right, true }
		if pos.y > pr.max.y - (pr.max.y - pr.min.y) * 0.25 { return i, 0, .Below, true }
		return i, len(app.panels[i].tabs), .None, true
	}
	return
}

// A tab's signal: a drag past the system's distance starts the tab's drag; its release moves it.
tab_drag_signal :: proc(app: ^App, panel, index: int, sig: ui.Signal) {
	d := &app.tab_drag
	if sig.dragging && !d.active {
		th := platform.drag_threshold(app.main.win)
		if abs(sig.drag_delta.x) >= th.x || abs(sig.drag_delta.y) >= th.y { d.active, d.panel, d.index, d.tab = true, panel, index, app.panels[panel].tabs[index].id }
	}
	if d.active && d.panel == panel && d.index == index && sig.dragging {
		app_frames(app)
		// out of the window: the drag of the system takes it (another classeur window, or a window of its own)
		m := ui.mouse_pos()
		size := app.window_px
		if m.x < 0 || m.y < 0 || m.x >= size.x || m.y >= size.y {
			d.active = false
			app.tab_out = d.tab
		}
	}
	if d.active && d.panel == panel && d.index == index && sig.released {
		d.active = false
		to, at, split, ok := tab_drop_place(app, ui.mouse_pos())
		if ok { d.pending, d.to, d.at, d.split = true, to, at, split; app_frames(app) }
	}
}

// Moves the tab `index` of panel `from` to panel `to` at `at`, or into a new panel beside `to`'s column or below `to`.
tab_move :: proc(app: ^App, from, index, to, at: int, split: Split) {
	if from < 0 || from >= len(app.panels) || to < 0 || to >= len(app.panels) { return }
	src := app.panels[from]
	if index < 0 || index >= len(src.tabs) { return }
	t := src.tabs[index]
	if split == .None && from == to {
		dest := at > index ? at - 1 : at
		ordered_remove(&src.tabs, index)
		dest = clamp(dest, 0, len(src.tabs))
		inject_at(&src.tabs, dest, t)
		src.active = dest
		app.focus = from
		return
	}
	if split != .None && len(src.tabs) == 1 && from == to { return }   // (the panel's one tab beside itself: nothing)
	ordered_remove(&src.tabs, index)
	target: ^Panel
	if split != .None {
		target = new(Panel)
		target.below = split == .Below
		inject_at(&app.panels, split == .Below ? to + 1 : column_end(app, to), target)
	} else {
		target = app.panels[to]
	}
	dest := split != .None ? 0 : clamp(at, 0, len(target.tabs))
	inject_at(&target.tabs, dest, t)
	target.active = dest
	// (the tab shown stays shown: one left of it went)
	if src.active > index { src.active -= 1 }
	if src.active >= len(src.tabs) { src.active = len(src.tabs) - 1 }
	// a panel left with no tab goes
	if len(src.tabs) == 0 {
		for q, i in app.panels {
			if q == src {
				// (the panel under it, the top of its column now)
				if !src.below && i + 1 < len(app.panels) && app.panels[i + 1].below { app.panels[i + 1].below = false }
				ordered_remove(&app.panels, i)
				free_panel_shell(src)
				break
			}
		}
	}
	for q, i in app.panels { if q == target { app.focus = i } }
	app_frames(app)
}

@(private = "file")
free_panel_shell :: proc(p: ^Panel) {
	delete(p.tabs)
	free(p)
}

// The tab being dragged, outlined in the accent.
tab_drag_mark :: proc(b: ^ui.Box) {
	prev, prev_user := b.custom, b.custom_user
	Mark :: struct { prev: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context), user: rawptr }
	m := ui.frame_new(Mark)
	m^ = {prev, prev_user}
	b.custom = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		m := (^Mark)(user)
		if m.prev != nil { m.prev(b, m.user, dc) }
		draw.rect(dc, b.rect, ui.color("accent"), border = max(1, ui.scale()))
	}
	b.custom_user = m
}

TAB_MIME :: "application/x-classeur-tab"

// Between frames: a tab dragged out of the window (tab_out) as a drag of the system, carrying its path. Dropped on another
// classeur window, it moves there; dropped back here, it stays (drop_answer took it); dropped anywhere else, it becomes
// a window of its own (classeur --window <path>), unless it is the window's only tab.
tab_out_run :: proc(app: ^App) {
	id := app.tab_out
	if id == 0 { return }
	app.tab_out, app.tab_out_home = 0, false
	t := find_tab(app, id)
	if t == nil { return }
	path := strings.clone(t.path, context.temp_allocator)
	data: platform.Drag_Data
	append(&data.custom, platform.Drag_Entry{TAB_MIME, path})
	data.text = path
	defer { delete(data.custom) }
	effect, started := platform.drag_start(app.main.win, data, {.Move})
	if !started || app.tab_out_home { return }
	alone := len(app.panels) == 1 && len(app.panels[0].tabs) == 1
	if _, moved := effect.?; !moved {
		if alone { return }
		if !tab_window(app, path) { return }
	}
	if alone { return }
	for p in app.panels {
		for q, i in p.tabs { if q.id == id { tab_close(app, p, i); app_frames(app); return } }
	}
}

// A window of its own on `path` (this program again, standalone).
tab_window :: proc(app: ^App, path: string) -> bool {
	if app.headless {
		append(&app.opened, strings.concatenate({"window:", path}))
		return true
	}
	return setup.launch(process.executable_path(), {"--window", path})
}

// A tab of a classeur window dropped here (Drop_* with TAB_MIME): it goes to the panel under the pointer. From this window
// itself: moved there; from another: opened there (the other closes its own).
tab_drop :: proc(app: ^App, data: ^platform.Drag_Data, pos: [2]f32, kind: platform.Event_Kind) -> (effect: Maybe(platform.Drop_Effect), is_tab: bool) {
	path := ""
	for e in data.custom { if e.mime == TAB_MIME { path = e.data } }
	if path == "" { return nil, false }
	if kind != .Drop { return .Move, true }
	panel := app.focus
	for pr, i in app.panel_rects {
		if i < len(app.panels) && pos.x >= pr.min.x && pos.x < pr.max.x && pos.y >= pr.min.y && pos.y < pr.max.y { panel = i }
	}
	for tr in app.tab_rects_last {
		if pos.x >= tr.rect.min.x && pos.x < tr.rect.max.x && pos.y >= tr.rect.min.y && pos.y < tr.rect.max.y { panel = tr.panel }
	}
	panel = clamp(panel, 0, len(app.panels) - 1)
	if app.tab_out != 0 || platform.drag_sending(app.main.win) {
		// (our own tab back home: moved to that panel, or left where it was)
		app.tab_out_home = true
		for p, pi in app.panels {
			for q, ti in p.tabs {
				if q.path == path && pi != panel { tab_move(app, pi, ti, panel, len(app.panels[panel].tabs), .None); return .Move, true }
			}
		}
		return .Move, true
	}
	p := app.panels[panel]
	tab_open(app, p, path, p.active + 1)
	app.focus = panel
	platform.raise_window(app.main.win)
	return .Move, true
}
