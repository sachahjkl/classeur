package classeur

// Drag and drop, the system's (gt:platform): rows and cards are dragged out as files, to another program or back into
// classeur; files dropped from anywhere go where the pointer is.
//   - Where a drop goes: each frame the places that take one are noted (`drop_zones`): a folder's row or card, a
//     panel's list (its folder), a tab, a place or a bookmark of the sidebar. The last noted under the pointer wins (a
//     row before the list it is in).
//   - What it does: Ctrl copies, Shift moves, Alt makes no link (refused); with no key, a move on the same volume and a
//     copy across volumes (as the systems' file managers do). Into the folder the files are in, or a folder into
//     itself: refused.
//   - A drag of classeur's own rows stays in the window while the pointer does (file_drag_frame, File Pilot's): the
//     folder under the pointer lit, a ghost of the files beside it, the drop a job at the release. At the window's edge
//     the system's drag takes it (drag_run), to another program, the desktop or another window; it blocks in
//     drag_start: the window answers at once (drop_sync_set) and a drop back on it is a job before drag_start returns.
//     A drag of another program's comes as events (app_input).
//   - Spring-open: the files held still on a folder's row for SPRING_MS open it in its tab, on a tab show that tab
//     (Finder's): the drag goes on there.

import "core:fmt"
import "core:slice"
import "core:strings"
import "gt:draw"
import "gt:platform"
import "gt:ui"
import "fs"

Drop_Zone :: struct {
	rect: ui.Rect,
	path: string,   // owned: the folder a drop there goes into
}

// A place that takes a drop this frame.
drop_zone :: proc(app: ^App, rect: ui.Rect, path: string) {
	append(&app.drop_zones, Drop_Zone{rect, strings.clone(path)})
}

// The folder under `pos`, "" none.
@(private = "file")
drop_target :: proc(app: ^App, pos: [2]f32) -> string {
	#reverse for z in app.drop_zones_last {
		if pos.x >= z.rect.min.x && pos.x < z.rect.max.x && pos.y >= z.rect.min.y && pos.y < z.rect.max.y { return z.path }
	}
	return ""
}

// What a drop of `files` into `dir` would do.
@(private = "file")
// `checked`: drop_takes's answer for these files and `dir`, known already (nil: asked here).
drop_effect :: proc(app: ^App, files: []string, dir: string, allowed: platform.Drop_Effects, mods: platform.Modifiers, checked: Maybe(bool) = nil) -> Maybe(platform.Drop_Effect) {
	if dir == "" || len(files) == 0 { return nil }
	takes, known := checked.?
	if !known { takes = drop_takes(files, dir) }
	if !takes { return nil }
	want: platform.Drop_Effect = same_volume_cached(app, files[0], dir) ? .Move : .Copy
	if .Ctrl in mods { want = .Copy }
	if .Shift in mods { want = .Move }
	if .Alt in mods { return nil }
	if want not_in allowed {
		want = want == .Move ? .Copy : .Move
		if want not_in allowed { return nil }
	}
	return want
}

// Whether `dir` takes a drop of `files`: not a folder into itself or below it, not all of them where they are already.
// A pass over every file: asked once per target of a drag, not at each frame (file_drag_frame).
@(private = "file")
drop_takes :: proc(files: []string, dir: string) -> bool {
	all_here := true
	for f in files {
		if fs.parent(f) != dir { all_here = false }
		// (a folder into itself or below it)
		if dir == f || (strings.has_prefix(dir, f) && len(dir) > len(f) && fs.is_separator(dir[len(f)])) { return false }
	}
	return !all_here
}

// Whether the files' folder and the target are on one volume, asked once per pair (a drag sends an event per move).
@(private = "file")
same_volume_cached :: proc(app: ^App, file, dir: string) -> bool {
	from := fs.parent(file)
	if app.vol_from == from && app.vol_to == dir {
		if app.vol_known { return app.vol_same }
		return vol_guess(app, from, dir)
	}
	delete(app.vol_from)
	delete(app.vol_to)
	app.vol_from, app.vol_to = strings.clone(from), strings.clone(dir)
	app.vol_known = false
	// (asked on a worker: a share of the network may be slow to answer; meanwhile a guess that reads no disk)
	Ask :: struct { app: ^App, from, to: string, same: bool }
	q := new(Ask)
	q^ = {app = app, from = strings.clone(from), to = strings.clone(dir)}
	pool_submit(&app.pool, proc(data: rawptr) {
		q := (^Ask)(data)
		q.same = fs.same_volume(q.from, q.to)
		if !ui.post(&q.app.main.state, proc(data: rawptr, word: u64) {
			q := (^Ask)(data)
			app := q.app
			// (the answer of the pair asked last: an older one is for a place the pointer left)
			if app.vol_from == q.from && app.vol_to == q.to {
				app.vol_same, app.vol_known = q.same, true
				app_frames(app)
			}
			delete(q.from)
			delete(q.to)
			free(q)
		}, q, 0) {
			delete(q.from)
			delete(q.to)
			free(q)
		}
	}, q)
	return vol_guess(app, from, dir)
}

// Whether two folders are on one volume, guessed from the volumes and shares known (the longest one each is under):
// the answer of a worker replaces it.
@(private = "file")
vol_guess :: proc(app: ^App, from, dir: string) -> bool {
	root_of :: proc(app: ^App, path: string) -> string {
		best := ""
		for v in app.volumes { if under_or_at(path, v.path) && len(v.path) > len(best) { best = v.path } }
		for s in app.shares { if under_or_at(path, s.path) && len(s.path) > len(best) { best = s.path } }
		return best
	}
	return root_of(app, from) == root_of(app, dir)
}

@(private = "file")
under_or_at :: proc(path, root: string) -> bool {
	if path == root || fs.is_root(root) && strings.has_prefix(path, root) { return true }
	return strings.has_prefix(path, root) && len(path) > len(root) && fs.is_separator(path[len(root)])
}

// The answer to a Drop_* at `pos`: the effect, and for a Drop the job.
drop_answer :: proc(app: ^App, kind: platform.Event_Kind, pos: [2]f32, mods: platform.Modifiers, allowed: platform.Drop_Effects) -> Maybe(platform.Drop_Effect) {
	data := platform.drop_data(app.main.win)
	if kind == .Drop_Leave || data == nil {
		tab_coming_end(app)
		delete(app.drop_hover)
		app.drop_hover = ""
		return nil
	}
	// (a classeur tab, from this window or another: tab_drag.odin)
	if e, is_tab := tab_drop(app, data, pos, kind); is_tab { app_frames(app); return e }
	dir := drop_target(app, pos)
	// (our own drag: its files are known here; Linux gives a drag's data at its drop only, the enter and the moves came
	// with none, and the drop was refused everywhere: on a folder, a place of the sidebar, a tab)
	files := data.files[:]
	if len(files) == 0 && len(app.dragging) > 0 { files = app.dragging }
	effect := drop_effect(app, files, dir, allowed, mods)
	// (Linux reads a drag's data at its drop only: before it, files that the drag offers are judged by its types)
	if kind != .Drop && len(data.files) == 0 && dir != "" && slice.contains(platform.drop_types(app.main.win), "text/uri-list") {
		effect = platform.drop_effect_for(allowed, mods, .Copy)
	}
	delete(app.drop_hover)
	app.drop_hover = effect != nil ? strings.clone(dir) : ""
	if kind == .Drop {
		delete(app.drop_hover)
		app.drop_hover = ""
		if e, ok := effect.?; ok {
			job_add(app, e == .Move ? .Move : .Copy, files, dir)
		}
	}
	app_frames(app)
	return effect
}

// The window answers its own drags at once (they come back while drag_start blocks).
dnd_start :: proc(app: ^App) {
	if !app.headless { platform.drop_target_enable(app.main.win, true) }
	platform.drop_sync_set(app.main.win, proc(user: rawptr, w: ^platform.Window, ev: platform.Event) -> Maybe(platform.Drop_Effect) {
		return drop_answer((^App)(user), ev.kind, ev.pos, ev.mods, ev.drop_allowed)
	}, app)
}

// A press on a selected row that moved past the system's distance: the selection is dragged (after this frame).
drag_maybe :: proc(app: ^App, t: ^Tab, sig: ui.Signal) {
	if sig.pressed { app.drag_started = false }   // (a new press: it may drag)
	if !sig.dragging || app.drag_started || app.band.active || app.gesture_cancelled { return }   // (a band of Ctrl selects; it drags no file)
	d := sig.drag_delta
	th := platform.drag_threshold(app.main.win)
	if abs(d.x) < th.x && abs(d.y) < th.y { return }
	app.drag_started = true
	for p in app.drag_paths { delete(p) }
	clear(&app.drag_paths)
	targets := folder_targets(&t.folder)
	for e in targets { append(&app.drag_paths, fs.join(t.path, e.name)) }
	// (the first one's kind, for the ghost's icon: known from the listing, no disk read at each frame)
	app.drag_first_folder = len(targets) > 0 && targets[0].kind == .Directory
	app.drag_check_valid = false   // (other files: checked again against their target)
	delete(app.spring_target)
	app.spring_target = ""
	app.file_drag = len(app.drag_paths) > 0
	app_frames(app)
}

// Each build while the files are dragged in the window: the folder under the pointer lit, the ghost; the release
// makes the job, Escape gives it up, the window's edge hands it to the system's drag.
file_drag_frame :: proc(app: ^App, em: f32) {
	if !app.file_drag { return }
	m := ui.mouse_pos()
	dir := drop_target(app, m)
	// (the modifiers held now, by their own keys: a compositor may leave the modifiers' state stale during a drag)
	mods: platform.Modifiers
	if ui.key_held(.Ctrl) { mods += {.Ctrl} }
	if ui.key_held(.Shift) { mods += {.Shift} }
	if ui.key_held(.Alt) { mods += {.Alt} }
	// (the dragged files checked against a target once, when it changes: a frame goes through none of them)
	if !app.drag_check_valid || app.drag_checked != dir {
		delete(app.drag_checked)
		app.drag_checked = strings.clone(dir)
		app.drag_check_ok = dir != "" && drop_takes(app.drag_paths[:], dir)
		app.drag_check_valid = true
	}
	effect := drop_effect(app, app.drag_paths[:], dir, {.Copy, .Move}, mods, app.drag_check_ok)
	delete(app.drop_hover)
	app.drop_hover = effect != nil ? strings.clone(dir) : ""
	spring(app, m, dir)
	// (let go: the press's box has no longer the pointer's)
	if ui.active_key() == 0 {
		if e, ok := effect.?; ok { job_add(app, e == .Move ? .Move : .Copy, app.drag_paths[:], dir) }
		file_drag_end(app)
		return
	}
	// at the window's left, right or bottom edge, or above it: the system's drag, started while the pointer is still
	// in the window (as a tab's)
	size := app.window_px
	edge := em * TAB_OUT_EDGE_EM
	if m.x < edge || m.x >= size.x - edge || m.y >= size.y - edge || m.y < 0 {
		app.file_drag, app.drag_out = false, true
		delete(app.drop_hover)
		app.drop_hover = ""
		return
	}
	app_frames(app)
	file_ghost(app, m, effect, dir, em)
}

SPRING_MS :: 700

// One timer for the target under the pointer (a tab, else a folder's row in a panel's list), set again when the
// target changes; due, the folder opens in that panel's tab or the tab is shown, once.
@(private = "file")
spring :: proc(app: ^App, m: [2]f32, dir: string) {
	inside :: proc(m: [2]f32, r: ui.Rect) -> bool { return m.x >= r.min.x && m.x < r.max.x && m.y >= r.min.y && m.y < r.max.y }
	target := ""
	tab_at: Tab_Rect
	for tr in app.tab_rects_last {
		if tr.panel < len(app.panels) && tr.index < len(app.panels[tr.panel].tabs) && inside(m, tr.rect) {
			tab_at, target = tr, fmt.tprintf("tab %d %d", tr.panel, tr.index)
		}
	}
	into: ^Tab
	if target == "" && dir != "" {
		for r, i in app.panel_rects {
			if i >= len(app.panels) || !inside(m, r) { continue }
			// (a row of its list: a folder under the one shown; a crumb is above it, the list itself is it)
			if t := panel_tab(app.panels[i]); t != nil && dir != t.path && under_or_at(dir, t.path) { into, target = t, dir }
		}
	}
	key := ui.key_from_string(0, "classeur_spring")
	if target != app.spring_target {
		delete(app.spring_target)
		app.spring_target, app.spring_done = strings.clone(target), false
		if target != "" { ui.timer_set(key, SPRING_MS) }
		return
	}
	if target == "" || app.spring_done || !ui.timer_due(key) { return }
	app.spring_done = true
	if into != nil {
		tab_go(app, into, dir)
	} else {
		app.panels[tab_at.panel].active = tab_at.index
	}
	app_frames(app)
}

// The files dragged, beside the pointer: the first one's icon, its name or how many they are, what a release does.
@(private = "file")
file_ghost :: proc(app: ^App, m: [2]f32, effect: Maybe(platform.Drop_Effect), dir: string, em: f32) {
	first := app.drag_paths[0]
	name := len(app.drag_paths) == 1 ? fs.base(first) : fmt.tprintf("%d items", len(app.drag_paths))
	what := ""
	if e, ok := effect.?; ok { what = fmt.tprintf("%s to %s", e == .Move ? "Move" : "Copy", fs.base(dir)) }
	ui.next({width = ui.children_sum(), height = ui.px(em * 2.2), axis = .X, cross = .Center,
		bg = draw.hex(surfaces(app).raised), border = draw.hex(surfaces(app).edge), radius = em * 0.3 * corner_k()})
	b := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background, .Draw_Border}, "###file_ghost")
	b.fixed_pos = m + {em, em * 1.1}
	if ui.parent(b) {
		ui.spacer(ui.px(em * 0.5))
		path_icon(app, first, app.drag_first_folder, em * 1.6)
		ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###name", name))
		if what != "" {
			ui.next({width = ui.text_size(em * 0.2), height = ui.pct(1)})
			if ui.tags("weak") { ui.label(fmt.tprintf("%s###what", what)) }
		}
		ui.spacer(ui.px(em * 0.4))
	}
}

file_drag_end :: proc(app: ^App) {
	app.file_drag = false
	delete(app.spring_target)
	app.spring_target = ""
	for p in app.drag_paths { delete(p) }
	clear(&app.drag_paths)
	app.drag_check_valid = false
	delete(app.drop_hover)
	app.drop_hover = ""
	app_frames(app)
}

// Between frames: the drag asked by the last one runs (it blocks until the drop).
drag_run :: proc(app: ^App) {
	if !app.drag_out { return }
	app.drag_out = false
	if len(app.drag_paths) == 0 { return }
	data: platform.Drag_Data
	for p in app.drag_paths { append(&data.files, p) }
	defer delete(data.files)
	// (while it runs: its files, which a drop on this window takes when the system gives it no data before the drop)
	app.dragging = app.drag_paths[:]
	_, _ = platform.drag_start(app.main.win, data, {.Copy, .Move, .Link})
	app.dragging = nil
	for p in app.drag_paths { delete(p) }
	clear(&app.drag_paths)
	delete(app.drop_hover)
	app.drop_hover = ""
	app_frames(app)
}

// Each frame: the zones noted by the last one are the ones a drop is tested against; the press that dragged ends.
dnd_frame :: proc(app: ^App) {
	for z in app.drop_zones_last { delete(z.path) }
	app.drop_zones_last, app.drop_zones = app.drop_zones, app.drop_zones_last
	clear(&app.drop_zones)
}

dnd_free :: proc(app: ^App) {
	for z in app.drop_zones { delete(z.path) }
	for z in app.drop_zones_last { delete(z.path) }
	delete(app.drop_zones)
	delete(app.drop_zones_last)
	for p in app.drag_paths { delete(p) }
	delete(app.drag_paths)
	delete(app.drop_hover)
	delete(app.spring_target)
	delete(app.drag_checked)
}

// The tests' way to ask drop_effect.
drop_effect_for_test :: proc(app: ^App, files: []string, dir: string) -> Maybe(platform.Drop_Effect) {
	return drop_effect(app, files, dir, {.Copy, .Move}, {})
}
