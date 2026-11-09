package classeur

// Undo (Ctrl+Z): a stack of what was done to files, each step with what puts it back. A step holds pairs (before,
// after) of paths:
//   - a rename: the name back (a rename);
//   - a new folder: the folder removed, when it is still empty;
//   - a copy: the copies to the trash (never deleted for good: an undo loses nothing);
//   - a move: each item moved back to where it was (a job: a move across volumes copies);
//   - the trash: each item put back from the trash (Linux; the Recycle Bin of Windows gives no path back).
// Deleting for good cannot be undone. What an undo does is not undone in turn; it can be done again (redo, Ctrl+Y,
// Ctrl+Shift+Z) until something else is done to files.

import "core:os"
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

act_undo :: proc(app: ^App) {
	if len(app.undo) == 0 {
		say(app, "Nothing to undo.")
		return
	}
	step := pop(&app.undo)
	n := len(step.pairs)
	done := true
	defer if done { append(&app.redo, step) } else { undo_step_free(&step) }
	switch step.kind {
	case .Rename:
		before, after := step.pairs[0][0], step.pairs[0][1]
		if fs.exists(before) {
			say(app, "%s is there again: the rename cannot be undone.", fs.base(before))
			done = false
			return
		}
		if err := os.rename(after, before); err != nil {
			say(app, "The rename cannot be undone: %v.", err)
			done = false
			return
		}
		undo_reveal(app, before)
	case .New_Folder, .New_File:
		path := step.pairs[0][1]
		info, _ := fs.stat(path)
		if (step.kind == .New_File && info.size > 0) || fs.remove(path) != .None {
			say(app, "%s is not empty now: it stays.", fs.base(path))
			done = false
			return
		}
		undo_reveal(app, path)
	case .Copy:
		copies := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { copies[i] = p[1] }
		job_add(app, .Trash, copies, undoing = true)
	case .Move:
		sources := make([]string, n, context.temp_allocator)
		targets := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { sources[i], targets[i] = p[1], p[0] }
		job_add(app, .Move, sources, targets = targets, undoing = true)
	case .Trash:
		in_trash := make([]string, n, context.temp_allocator)
		for p, i in step.pairs { in_trash[i] = p[1] }
		job_add(app, .Restore, in_trash, undoing = true)
	}
	say(app, "Undone: the %s%s.", UNDO_SAID[step.kind], n > 1 ? " of several items" : "")
}

act_redo :: proc(app: ^App) {
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
		if fs.exists(afters[0]) || os.rename(befores[0], afters[0]) != nil {
			say(app, "The rename cannot be done again.")
			return
		}
		undo_push(app, .Rename, step.pairs, redoing = true)
		undo_reveal(app, afters[0])
	case .New_Folder, .New_File:
		e: fs.Error
		if step.kind == .New_Folder {
			e = fs.make_folder(afters[0])
		} else if os.write_entire_file(afters[0], []u8{}) != nil {
			e = .Denied
		}
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
