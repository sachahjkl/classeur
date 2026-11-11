package classeur

// Tabs dragged (File Pilot's): along their row to another place, onto another panel's row to move there, onto the right
// quarter of a panel to open a new panel beside it with the tab, onto its bottom quarter for a new panel below it. The tabs' boxes of the last frame (`tab_rects_last`)
// and the panels' say where the pointer is; the move is made before the build that follows the release.

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:slice"
import "core:strings"
import "gt:draw"
import "gt:render"
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
	grab:         [2]f32,           // where the pointer holds it: pointer minus the tab's corner (the ghost and the picture)
	size:         [2]f32,           // the tab's size (the ghost's)
	capture:      bool,             // a picture of the tab was asked of the renderer (the system's drag shows it)
	panel_now:    int,              // the panel the dragged tab is in (found by its id each frame)
	land_panel:   int,              // where it would land now (tab_drag_land, before the build): a panel's row ...
	land_at:      int,              // ... its place there (-1: none, or nowhere it would move)
	land_split:   Split,            // ... or a new panel beside it
}

// Where a tab let go makes a new panel: none, a column at the right, a panel below.
Split :: enum u8 { None, Right, Below }

// Before a build: where the dragged tab would land at the pointer (the rows show its ghost there). A place that moves
// nothing (its own place, either side of itself) shows none: the dimmed tab is the place.
tab_drag_land :: proc(app: ^App) {
	d := &app.tab_drag
	d.land_at, d.land_split = -1, .None
	if !d.active || d.capture { return }
	to, at, split, ok := tab_drop_place(app, ui.mouse_pos())
	if !ok { return }
	d.land_panel, d.land_split = to, split
	if split != .None { return }
	from := -1
	if to < len(app.panels) { for q, i in app.panels[to].tabs { if q.id == d.tab { from = i } } }
	if from >= 0 && (at == from || at == from + 1) { return }
	d.land_at = at
}

// The place in panel `index`'s row where the dragged tab's ghost goes (-1: none).
tab_ghost_slot :: proc(app: ^App, index: int) -> int {
	d := &app.tab_drag
	if !d.active || d.land_split != .None || d.land_panel != index { return -1 }
	return d.land_at
}

// The dragged tab's ghost in a row: its icon and its title, faint, a line around it.
tab_ghost :: proc(app: ^App, width, em: f32) {
	t := find_tab(app, app.tab_drag.tab)
	if t == nil { return }
	ui.next({width = ui.px(width), height = ui.px(ui.dense(em * (TOP_EM - 0.45))), axis = .X, cross = .Center,
		bg = draw.hex(surfaces(app).list) * {1, 1, 1, 0.6}, border = ui.color("accent"), radius = em * TAB_RADIUS_EM, transparency = 0.25})
	b := ui.build_box({.Draw_Background, .Draw_Border}, "###tab_land")
	if ui.parent(b) {
		ui.spacer(ui.px(em * 0.7))
		path_icon(app, t.path, true, em * 1.6)
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###title", shown_text(tab_title(app, t))))
	}
}

// Before a build: the move of a tab released in the last one. A drag whose tab went (closed while dragged) is over.
tab_drag_apply :: proc(app: ^App) {
	d := &app.tab_drag
	if d.active && find_tab(app, d.tab) == nil {
		d.active = false
		tab_image_free(app)
	}
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
		// (a panel's only tab beside itself: nothing to split)
		alone := i == app.tab_drag.panel_now && len(app.panels[i].tabs) == 1
		if pos.x > pr.max.x - (pr.max.x - pr.min.x) * 0.25 { return i, 0, .Right, !alone }
		if pos.y > pr.max.y - (pr.max.y - pr.min.y) * 0.25 { return i, 0, .Below, !alone }
		// (its own panel's body: it stays where it is)
		if i == app.tab_drag.panel_now { return }
		return i, len(app.panels[i].tabs), .None, true
	}
	return
}

// A tab's signal: a drag past the system's distance starts the tab's drag; its release moves it.
tab_drag_signal :: proc(app: ^App, panel, index: int, sig: ui.Signal) {
	d := &app.tab_drag
	if sig.dragging && !d.active {
		th := platform.drag_threshold(app.main.win)
		if abs(sig.drag_delta.x) >= th.x || abs(sig.drag_delta.y) >= th.y {
			d.active, d.panel, d.index, d.tab, d.panel_now = true, panel, index, app.panels[panel].tabs[index].id, panel
			r := sig.box.rect
			d.grab, d.size = ui.mouse_pos() - sig.drag_delta - r.min, r.max - r.min
			// (its picture, read back from the next frame: what the system's drag shows out of the window)
			tab_image_free(app)
			d.capture = render.capture_request(&app.shared.r, {int(r.min.x), int(r.min.y), int(r.max.x - r.min.x), int(r.max.y - r.min.y)})
		}
	}
	// (the dragged tab is told by its id: the tabs may shift while it is dragged)
	mine := d.active && app.panels[panel].tabs[index].id == d.tab
	if mine { d.panel_now = panel }
	if mine && sig.dragging {
		app_frames(app)
		// at the window's left, right or bottom edge, or out of it: the drag of the system takes it, started while the
		// pointer is still in the window (the systems start a drag from a press of their window's), to another classeur
		// window or a window of its own
		m := ui.mouse_pos()
		size := app.window_px
		edge := ui.font_size() * TAB_OUT_EDGE_EM
		if m.x < edge || m.x >= size.x - edge || m.y >= size.y - edge || m.y < 0 {
			d.active = false
			app.tab_out = d.tab
		}
	}
	if mine && d.active && sig.released {
		d.active = false
		tab_image_free(app)
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

TAB_MIME :: "application/x-classeur-tab"

// What a dragged tab carries: its process, its id and its path ("<pid>:<id>:<path>"): back in its own window, the tab
// itself is moved (two tabs may show one folder); in another, its folder is opened.
tab_mime_data :: proc(pid: int, id: u64, path: string) -> string { return fmt.tprintf("%d:%d:%s", pid, id, path) }

tab_mime_parse :: proc(data: string) -> (pid: int, id: u64, path: string, ok: bool) {
	a := strings.index_byte(data, ':')
	if a < 0 { return }
	b := strings.index_byte(data[a + 1:], ':')
	if b < 0 { return }
	b += a + 1
	p, pok := strconv.parse_int(data[:a])
	i, iok := strconv.parse_u64(data[a + 1:b])
	if !pok || !iok { return }
	return p, i, data[b + 1:], true
}

// How near the window's edge a dragged tab leaves it (em): the system's drag starts there.
TAB_OUT_EDGE_EM :: 1.2

// Each frame of a tab's drag: its picture, once the renderer has read it back (faded: the usual ghost).
tab_drag_poll :: proc(app: ^App) {
	d := &app.tab_drag
	if !d.capture { return }
	pixels, size, status := render.capture_poll(&app.shared.r)
	switch status {
	case .Ready:
		d.capture = false
		tab_image_free(app)
		// (read back after the drag ended: no one to show it)
		if !d.active && app.tab_out == 0 { delete(pixels); return }
		app.tab_image = {pixels, size, {}}
		platform.drag_image_fade(app.tab_image, 0.85)
	case .Failed:
		d.capture = false
	case .Pending:
		app_frames(app)
	case .None:
		d.capture = false
	}
}

tab_image_free :: proc(app: ^App) {
	delete(app.tab_image.rgba)
	app.tab_image = {}
}

// Over the window while a tab is dragged: the tab following the pointer, and where it lands: a line between the tabs of
// a row, the half of a panel that a new panel takes (at the right, below), the panel that takes it whole; out of the
// window, a window of its own (said under the ghost).
tab_drag_overlay :: proc(app: ^App, em: f32) {
	d := &app.tab_drag
	// (while its picture is read back: the frame shows the tab alone, no ghost over it)
	if d.capture { return }
	// (after the tabs' signals: a press that ended out of its tab's box, a capture lost, ends the drag)
	if d.active && ui.active_key() == 0 {
		d.active = false
		tab_image_free(app)
	}
	if !d.active { return }
	t := find_tab(app, d.tab)
	if t == nil { return }
	m := ui.mouse_pos()
	accent := ui.color("accent")
	place :: proc(r: ui.Rect, bg, border: ui.Color, id: string, radius: f32 = 0, axis := ui.Axis.X) -> ^ui.Box {
		ui.next({width = ui.px(max(r.max.x - r.min.x, 1)), height = ui.px(max(r.max.y - r.min.y, 1)), bg = bg, border = border, radius = radius, axis = axis, cross = .Center})
		b := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background, .Draw_Border}, id)
		b.fixed_pos = r.min
		return b
	}
	if to, _, split, ok := tab_drop_place(app, m); ok && to < len(app.panel_rects) {
		pr := app.panel_rects[to]
		switch split {
		case .None:
			row := false
			for tr in app.tab_rects_last {
				if tr.panel == to && m.y >= tr.rect.min.y && m.y < tr.rect.max.y { row = true }
			}
			// (in the row: the ghost there, built with the row; on the panel: the panel lit, the ghost at its row's end)
			if !row {
				place(pr, accent * {1, 1, 1, 0.06}, accent, "###tab_drop_panel")
			}
		case .Right, .Below:
			half := split == .Right ? ui.Rect{{(pr.min.x + pr.max.x) * 0.5, pr.min.y}, pr.max} : ui.Rect{{pr.min.x, (pr.min.y + pr.max.y) * 0.5}, pr.max}
			// (its words in its upper part: the ghost is where the pointer is, lower)
			b := place(half, accent * {1, 1, 1, 0.14}, accent, "###tab_drop_split", axis = .Y)
			if ui.parent(b) {
				ui.spacer(ui.px(em * 3))
				// (on a plate of the list's colour: legible over whatever the half covers)
				ui.next({width = ui.text_size(em * 1.2), height = ui.px(em * 2.2), text_align = .Center, bg = draw.hex(surfaces(app).list), border = accent, radius = em * 0.3})
				ui.build_box({.Draw_Background, .Draw_Border, .Draw_Text}, split == .Right ? "A new panel at the right###t" : "A new panel below###t")
			}
		}
	}
	// the ghost: the tab under the pointer, and what its edge does
	// (a place in a row: its ghost there is the tab, nothing follows the pointer over it)
	if d.land_at >= 0 && d.land_split == .None { return }
	// (in the window, its words under it too)
	hint_w := max(d.size.x, em * 17)
	at := m - d.grab
	at.x = clamp(at.x, 0, max(app.window_px.x - hint_w, 0))
	at.y = clamp(at.y, 0, max(app.window_px.y - d.size.y - em * 2.3, 0))
	// (one line around it, the tabs' own: the accent marks where it lands, not the tab)
	ghost := place({at, at + d.size}, draw.hex(surfaces(app).list) * {1, 1, 1, 0.94}, draw.hex(surfaces(app).edge), "###tab_ghost", tab_radius(em) / max(ui.rounding(ui.current_state()), 0.01))
	if ui.parent(ghost) {
		ui.spacer(ui.px(em * 0.7))
		path_icon(app, t.path, true, em * 1.6)
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###title", shown_text(tab_title(app, t))))
	}
	hint := ui.Rect{{at.x, at.y + d.size.y + em * 0.3}, {at.x + hint_w, at.y + d.size.y + em * 2}}
	if ui.tags("weak") {
		b := place(hint, {}, {}, "###tab_ghost_hint")
		if ui.parent(b) {
			ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.85)})
			ui.label("To a window's edge: a window of its own###t")
		}
	}
}

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
	append(&data.custom, platform.Drag_Entry{TAB_MIME, tab_mime_data(os.get_pid(), id, path)})
	// (no text in it: a program that takes a text with Move would close the tab and open no window)
	defer { delete(data.custom) }
	// (its picture under the pointer, where it was held)
	image: Maybe(platform.Drag_Image)
	if platform.drag_image_valid(app.tab_image) {
		img := app.tab_image
		img.offset = {clamp(int(app.tab_drag.grab.x), 0, img.size.x), clamp(int(app.tab_drag.grab.y), 0, img.size.y)}
		image = img
	}
	defer tab_image_free(app)
	effect, started := platform.drag_start(app.main.win, data, {.Move}, image)
	if !started || app.tab_out_home { return }
	alone := len(app.panels) == 1 && len(app.panels[0].tabs) == 1
	_, moved := effect.?
	if !moved {
		if alone { return }
		if !tab_window(app, path) { return }
	}
	// (the window's only tab taken by another classeur window: this one has nothing left to show)
	if alone {
		if moved && !app.headless { platform.request_close(app.main.win) }
		return
	}
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
	return setup.launch(app.exe, {"--window", path})
}

// A tab of a classeur window dropped here (Drop_* with TAB_MIME): it goes to the panel under the pointer. From this window
// itself: moved there; from another: opened there (the other closes its own).
tab_drop :: proc(app: ^App, data: ^platform.Drag_Data, pos: [2]f32, kind: platform.Event_Kind) -> (effect: Maybe(platform.Drop_Effect), is_tab: bool) {
	pid, id, path := 0, u64(0), ""
	for e in data.custom {
		if e.mime != TAB_MIME { continue }
		if p, i, at, ok := tab_mime_parse(e.data); ok { pid, id, path = p, i, at }
	}
	// (Linux reads the data at the drop only: before it, a tab is told by its type, and taken)
	if kind != .Drop && path == "" && slice.contains(platform.drop_types(app.main.win), TAB_MIME) { return .Move, true }
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
	if pid == os.get_pid() {
		// (our own tab back home: that very tab moved to that panel, or left where it was)
		app.tab_out_home = true
		for p, pi in app.panels {
			for q, ti in p.tabs {
				if q.id == id && pi != panel { tab_move(app, pi, ti, panel, len(app.panels[panel].tabs), .None); return .Move, true }
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

// The tab shown to a window of its own (its tab's menu, Ctrl+Shift+Alt+N): what dragging it out does, without the drag.
act_tab_window :: proc(app: ^App) {
	p := current_panel(app)
	t := current_tab(app)
	if p == nil || t == nil || len(app.panels) == 1 && len(p.tabs) == 1 { return }
	if !tab_window(app, strings.clone(t.path, context.temp_allocator)) { say(app, "No window could be started."); return }
	tab_close(app, p, p.active)
}
