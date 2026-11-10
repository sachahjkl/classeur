package classeur

// Undo (Ctrl+Z): a stack of what was done to files, each step with what puts it back. A step holds pairs (before,
// after) of paths:
//   - a rename: the name back (a rename);
//   - a new folder: the folder removed, when it is still empty;
//   - a copy: the copies to the trash (never deleted for good: an undo loses nothing);
//   - a move: each item moved back to where it was (a job: a move across volumes copies);
//   - the trash: each item put back from the trash (Linux's, or the Recycle Bin of Windows, its $I records read).
// Deleting for good cannot be undone. What an undo does is not undone in turn; it can be done again (redo, Ctrl+Y,
// Ctrl+Shift+Z) until something else is done to files.

import "core:fmt"
import "core:slice"
import "core:strings"
import "fs"

Undo_Kind :: enum u8 { Rename, New_Folder, New_File, Copy, Move, Trash }

Undo_Step :: struct {
	kind:  Undo_Kind,
	pairs: [][2]string,   // owned: (before, after)
}

UNDO_KEPT :: 100

@(private = "file")
UNDO_SAID := [Undo_Kind]string{.Rename = "rename", .New_Folder = "new folder", .New_File = "new file", .Copy = "copy", .Move = "move", .Trash = "move to the trash"}

// A step done by the person: what could be done again is forgotten.
undo_push :: proc(app: ^App, kind: Undo_Kind, pairs: [][2]string, redoing := false) {
	if len(pairs) == 0 { return }
	if !redoing { redo_clear(app) }
	step := Undo_Step{kind = kind, pairs = make([][2]string, len(pairs))}
	for p, i in pairs { step.pairs[i] = {strings.clone(p[0]), strings.clone(p[1])} }
	append(&app.undo, step)
	if len(app.undo) > UNDO_KEPT {
		undo_step_free(&app.undo[0])
		ordered_remove(&app.undo, 0)
	}
}

// What a job did, as a step (called when it ends).
undo_push_job :: proc(app: ^App, job: ^Job) {
	kind: Undo_Kind
	switch job.kind {
	case .Copy:  kind = .Copy
	case .Move:  kind = .Move
	case .Trash: kind = .Trash
	case .Delete, .Restore: return
	}
	undo_push(app, kind, job.done[:], job.redoing)
}

// Whether a job keeps `step` to hand it to the redo stack when it ends.
@(private = "file")
job_owns :: proc(app: ^App, step: Undo_Step) -> bool {
	for job in app.jobs.list { if job.redo_step.pairs != nil && raw_data(job.redo_step.pairs) == raw_data(step.pairs) { return true } }
	return false
}

redo_clear :: proc(app: ^App) {
	for &s in app.redo { undo_step_free(&s) }
	clear(&app.redo)
}

undo_step_free :: proc(s: ^Undo_Step) {
	for p in s.pairs { delete(p[0]); delete(p[1]) }
	delete(s.pairs)
	s^ = {}
}

undo_free :: proc(app: ^App) {
	for &s in app.undo { undo_step_free(&s) }
	delete(app.undo)
	redo_clear(app)
	delete(app.redo)
}

// A job copies, moves or trashes: its step comes when it ends, so an undo now would undo the step before it.
@(private = "file")
job_running :: proc(app: ^App) -> bool {
	for job in app.jobs.list { if job.ended_ms == 0 { return true } }
	return false
}

act_undo :: proc(app: ^App) {
	if job_running(app) {
		say(app, "A copy or a move is running: undo once it has ended.")
		return
	}
	if len(app.undo) == 0 {
		say(app, "Nothing to undo.")
		return
	}
	step := pop(&app.undo)
	n := len(step.pairs)
	done := true
	defer if done { append(&app.redo, step) } else if !job_owns(app, step) { undo_step_free(&step) }
	switch step.kind {
	case .Rename:
		// (a batch: every name back, the last renamed first)
		for p in step.pairs {
			if fs.exists(p[0]) && !slice.contains(afters_of(step.pairs), p[0]) {
				say(app, "%s is there again: the rename cannot be undone.", fs.base(p[0]))
				done = false
				return
			}
		}
		if !renames_swap(step.pairs, back = true) {
			say(app, "The rename cannot be undone.")
			done = false
			return
		}
		undo_reveal(app, step.pairs[0][0])
	case .New_Folder, .New_File:
		path := step.pairs[0][1]
		info, _ := fs.stat(path)
		if (step.kind == .New_File && info.size > 0) || fs.remove(path) != .None {
			say(app, "%s is not empty now: it stays.", fs.base(path))
			done = false
			return
		}
		undo_reveal(app, path)
	// (a job's undo: the step can be done again once its job has ended well: job_ended hands it to the redo stack)
	case .Copy:
		copies := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { copies[i] = p[1] }
		job := job_add(app, .Trash, copies, undoing = true)
		job.redo_step, done = step, false
	case .Move:
		sources := make([]string, n, context.temp_allocator)
		targets := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { sources[i], targets[i] = p[1], p[0] }
		job := job_add(app, .Move, sources, targets = targets, undoing = true)
		job.redo_step, done = step, false
	case .Trash:
		in_trash := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { in_trash[i] = p[1] }
		job := job_add(app, .Restore, in_trash, undoing = true)
		job.redo_step, done = step, false
	}
	say(app, "Undone: the %s%s.", UNDO_SAID[step.kind], n > 1 ? " of several items" : "")
}

act_redo :: proc(app: ^App) {
	if job_running(app) {
		say(app, "A copy or a move is running: redo once it has ended.")
		return
	}
	if len(app.redo) == 0 {
		say(app, "Nothing to do again.")
		return
	}
	step := pop(&app.redo)
	defer undo_step_free(&step)
	n := len(step.pairs)
	befores := make([]string, n, context.temp_allocator)
	afters := make([]string, n, context.temp_allocator)
	for p, i in step.pairs { befores[i], afters[i] = p[0], p[1] }
	switch step.kind {
	case .Rename:
		if !renames_swap(step.pairs, back = false) {
			say(app, "The rename cannot be done again.")
			return
		}
		undo_push(app, .Rename, step.pairs, redoing = true)
		undo_reveal(app, afters[0])
	case .New_Folder, .New_File:
		e := step.kind == .New_Folder ? fs.make_folder(afters[0]) : fs.make_file(afters[0])
		if e != .None {
			say(app, "%s cannot be made again.", fs.base(afters[0]))
			return
		}
		undo_push(app, step.kind, step.pairs, redoing = true)
		undo_reveal(app, afters[0])
	case .Copy:
		job := job_add(app, .Copy, befores, targets = afters)
		job.redoing = true
	case .Move:
		job := job_add(app, .Move, befores, targets = afters)
		job.redoing = true
	case .Trash:
		job := job_add(app, .Trash, befores)
		job.redoing = true
	}
	say(app, "Done again: the %s%s.", UNDO_SAID[step.kind], n > 1 ? " of several items" : "")
}

@(private = "file")
afters_of :: proc(pairs: [][2]string) -> []string {
	out := make([]string, len(pairs), context.temp_allocator)
	for p, i in pairs { out[i] = p[1] }
	return out
}

// Renames each pair (before to after, or back), in two steps through free names: names of a batch can swap. Never
// over a name (fs.rename); when one fails, every pair goes back to where it was: all or nothing.
renames_swap :: proc(pairs: [][2]string, back: bool) -> bool {
	from_of :: proc(p: [2]string, back: bool) -> string { return back ? p[1] : p[0] }
	to_of :: proc(p: [2]string, back: bool) -> string { return back ? p[0] : p[1] }
	temps := make([]string, len(pairs), context.temp_allocator)
	for p, i in pairs {
		temps[i] = fmt.tprintf("%s.classeur-undo-%d", from_of(p, back), i)
		if fs.rename(from_of(p, back), temps[i]) != .None {
			for j in 0 ..< i { _ = fs.rename(temps[j], from_of(pairs[j], back)) }
			return false
		}
	}
	for p, i in pairs {
		if fs.rename(temps[i], to_of(p, back)) == .None { continue }
		// (one cannot go: the ones done go back, then every one to its old name)
		for j in 0 ..< i { _ = fs.rename(to_of(pairs[j], back), temps[j]) }
		for j in 0 ..< len(pairs) { _ = fs.rename(temps[j], from_of(pairs[j], back)) }
		return false
	}
	return true
}

// The tabs that show the folder of `path` read it again, the cursor on its name.
@(private = "file")
undo_reveal :: proc(app: ^App, path: string) {
	dir := fs.parent(path)
	for p in app.panels {
		for t in p.tabs {
			if t.path != dir { continue }
			delete(t.reveal_name)
			t.reveal_name = strings.clone(fs.base(path))
			tab_load(app, t)
		}
	}
}
