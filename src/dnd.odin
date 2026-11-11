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
drop_effect :: proc(app: ^App, files: []string, dir: string, allowed: platform.Drop_Effects, mods: platform.Modifiers) -> Maybe(platform.Drop_Effect) {
	if dir == "" || len(files) == 0 { return nil }
	all_here := true
	for f in files {
		if fs.parent(f) != dir { all_here = false }
		// (a folder into itself or below it)
		if dir == f || strings.has_prefix(dir, strings.concatenate({f, fs.SEPARATOR_STRING}, context.temp_allocator)) { return nil }
	}
	if all_here { return nil }
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

// Whether the files' folder and the target are on one volume, asked once per pair (a drag sends an event per move).
@(private = "file")
same_volume_cached :: proc(app: ^App, file, dir: string) -> bool {
	from := fs.parent(file)
	if app.vol_from == from && app.vol_to == dir { return app.vol_same }
	delete(app.vol_from)
	delete(app.vol_to)
	app.vol_from, app.vol_to = strings.clone(from), strings.clone(dir)
	app.vol_same = fs.same_volume(from, dir)
	return app.vol_same
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
	for e in folder_targets(&t.folder) { append(&app.drag_paths, fs.join(t.path, e.name)) }
	app.file_drag = len(app.drag_paths) > 0
	app_frames(app)
}

// Each build while the files are dragged in the window: the folder under the pointer lit, the ghost; the release
// makes the job, Escape gives it up, the window's edge hands it to the system's drag.
file_drag_frame :: proc(app: ^App, em: f32) {
	if !app.file_drag { return }
	m := ui.mouse_pos()
	dir := drop_target(app, m)
	effect := drop_effect(app, app.drag_paths[:], dir, {.Copy, .Move}, ui.current_state().mods)
	delete(app.drop_hover)
	app.drop_hover = effect != nil ? strings.clone(dir) : ""
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

// The files dragged, beside the pointer: the first one's icon, its name or how many they are, what a release does.
@(private = "file")
file_ghost :: proc(app: ^App, m: [2]f32, effect: Maybe(platform.Drop_Effect), dir: string, em: f32) {
	first := app.drag_paths[0]
	name := len(app.drag_paths) == 1 ? fs.base(first) : fmt.tprintf("%d items", len(app.drag_paths))
	what := ""
	if e, ok := effect.?; ok { what = fmt.tprintf("%s to %s", e == .Move ? "Move" : "Copy", fs.base(dir)) }
	info, _ := fs.stat(first)
	ui.next({width = ui.children_sum(), height = ui.px(em * 2.2), axis = .X, cross = .Center,
		bg = draw.hex(surfaces(app).raised), border = draw.hex(surfaces(app).edge), radius = em * 0.3 * corner_k()})
	b := ui.build_box({.Floating_X, .Floating_Y, .Draw_Background, .Draw_Border}, "###file_ghost")
	b.fixed_pos = m + {em, em * 1.1}
	if ui.parent(b) {
		ui.spacer(ui.px(em * 0.5))
		path_icon(app, first, info.kind == .Directory, em * 1.6)
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
	for p in app.drag_paths { delete(p) }
	clear(&app.drag_paths)
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
}

// The tests' way to ask drop_effect.
drop_effect_for_test :: proc(app: ^App, files: []string, dir: string) -> Maybe(platform.Drop_Effect) {
	return drop_effect(app, files, dir, {.Copy, .Move}, {})
}
