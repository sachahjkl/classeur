package classeur

// Drag and drop, the system's (gt:platform): rows and cards are dragged out as files, to another program or back into
// classeur; files dropped from anywhere go where the pointer is.
//   - Where a drop goes: each frame the places that take one are noted (`drop_zones`): a folder's row or card, a
//     panel's list (its folder), a tab, a place or a bookmark of the sidebar. The last noted under the pointer wins (a
//     row before the list it is in).
//   - What it does: Ctrl copies, Shift moves, Alt makes no link (refused); with no key, a move on the same volume and a
//     copy across volumes (as the systems' file managers do). Into the folder the files are in, or a folder into
//     itself: refused.
//   - A drag of classeur's own blocks in drag_start: the window answers at once (drop_sync_set) and the drop is a job
//     before drag_start returns. A drag of another program's comes as events (app_input).

import "core:strings"
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
		delete(app.drop_hover)
		app.drop_hover = ""
		return nil
	}
	// (a classeur tab, from this window or another: tab_drag.odin)
	if e, is_tab := tab_drop(app, data, pos, kind); is_tab { app_frames(app); return e }
	dir := drop_target(app, pos)
	effect := drop_effect(app, data.files[:], dir, allowed, mods)
	delete(app.drop_hover)
	app.drop_hover = effect != nil ? strings.clone(dir) : ""
	if kind == .Drop {
		delete(app.drop_hover)
		app.drop_hover = ""
		if e, ok := effect.?; ok {
			job_add(app, e == .Move ? .Move : .Copy, data.files[:], dir)
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
	if !sig.dragging || app.drag_started { return }
	d := sig.drag_delta
	th := platform.drag_threshold(app.main.win)
	if abs(d.x) < th.x && abs(d.y) < th.y { return }
	app.drag_started = true
	for p in app.drag_paths { delete(p) }
	clear(&app.drag_paths)
	for e in folder_targets(&t.folder) { append(&app.drag_paths, fs.join(t.path, e.name)) }
}

// Between frames: the drag asked by the last one runs (it blocks until the drop).
drag_run :: proc(app: ^App) {
	if len(app.drag_paths) == 0 { return }
	data: platform.Drag_Data
	for p in app.drag_paths { append(&data.files, p) }
	defer delete(data.files)
	_, _ = platform.drag_start(app.main.win, data, {.Copy, .Move, .Link})
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
