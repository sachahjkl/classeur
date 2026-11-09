package classeur

// The jobs: copy, move, trash and delete, one at a time, on a thread of their own (two copies at once on one disk are
// slower than one after the other). A job is made on the interface's thread with what it must do (its sources, its
// destination); the thread reports its progress in atomics the status bar reads, and posts to the interface when it
// needs an answer (a name already taken) and when it ends. The interface owns the list of jobs; a job is freed by the
// interface when it has ended and is no longer shown.

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "gt:fsx"
import "gt:ui"
import "fs"

Job_Kind :: enum u8 { Copy, Move, Trash, Delete }

Job_State :: enum u8 { Waiting, Counting, Running, Asking, Done, Failed, Cancelled }

// What a name already taken at the destination becomes.
Conflict :: enum u8 { Ask, Replace, Skip, Keep_Both }

JOB_VERB := [Job_Kind]string{.Copy = "Copying", .Move = "Moving", .Trash = "Moving to the trash", .Delete = "Deleting"}
JOB_DONE := [Job_Kind]string{.Copy = "copied", .Move = "moved", .Trash = "moved to the trash", .Delete = "deleted"}

// How long an ended job stays in the status bar.
JOB_SHOWN_MS :: 4000

Job :: struct {
	id:      u64,
	kind:    Job_Kind,
	sources: []string,     // owned, absolute
	dest:    string,       // owned: the folder (Copy, Move)
	policy:  Conflict,     // for every conflict; Ask: the person says, then maybe for all

	// written by the jobs' thread, read by the interface
	state:       Job_State,   // atomic
	bytes_total: i64,         // atomic
	bytes_done:  i64,         // atomic
	files_total: int,         // atomic
	files_done:  int,         // atomic
	cancel:      bool,        // atomic: set by the interface
	mutex:       sync.Mutex,  // guards `current` and `errors`
	current:     string,      // owned: the name being done
	errors:      [dynamic]string,   // owned: what failed, one line each

	// a name taken: the jobs' thread waits on `answered` until the interface sets `answer`
	ask_name:   string,       // owned (by the jobs' thread while it waits)
	answer:     Conflict,
	answer_all: bool,
	answered:   sync.Sema,

	ended_ms:   f64,          // the interface's clock when job_ended ran (0: not yet: the job is not freed before)
	app:        ^App,
}

Jobs :: struct {
	mutex:   sync.Mutex,
	cond:    sync.Cond,
	queue:   [dynamic]^Job,   // waiting for the thread
	list:    [dynamic]^Job,   // the interface's: every job not yet forgotten
	thread:  ^thread.Thread,
	quit:    bool,
	next_id: u64,
}

jobs_start :: proc(app: ^App) {
	app.jobs.thread = thread.create_and_start_with_data(app, jobs_work)
}

// Ends the thread after the job it runs (cancelled); the jobs waiting are dropped.
jobs_stop :: proc(app: ^App) {
	j := &app.jobs
	sync.mutex_lock(&j.mutex)
	j.quit = true
	for job in j.list { sync.atomic_store(&job.cancel, true) }
	sync.mutex_unlock(&j.mutex)
	sync.cond_broadcast(&j.cond)
	// (a job waiting for an answer is answered: skip)
	for job in j.list {
		if sync.atomic_load(&job.state) == .Asking {
			job.answer = .Skip
			sync.sema_post(&job.answered)
		}
	}
	if j.thread != nil {
		thread.join(j.thread)
		thread.destroy(j.thread)
	}
	for job in j.list { job_free(job) }
	delete(j.list)
	delete(j.queue)
	j^ = {}
}

// A new job, queued. `sources` are cloned.
job_add :: proc(app: ^App, kind: Job_Kind, sources: []string, dest := "", policy := Conflict.Ask) -> ^Job {
	j := &app.jobs
	job := new(Job)
	j.next_id += 1
	job.id, job.kind, job.policy, job.app = j.next_id, kind, policy, app
	job.sources = make([]string, len(sources))
	for s, i in sources { job.sources[i] = strings.clone(s) }
	job.dest = strings.clone(dest)
	append(&j.list, job)
	sync.mutex_lock(&j.mutex)
	append(&j.queue, job)
	sync.mutex_unlock(&j.mutex)
	sync.cond_signal(&j.cond)
	return job
}

job_free :: proc(job: ^Job) {
	for s in job.sources { delete(s) }
	delete(job.sources)
	delete(job.dest)
	delete(job.current)
	for e in job.errors { delete(e) }
	delete(job.errors)
	delete(job.ask_name)
	free(job)
}

job_cancel :: proc(job: ^Job) {
	sync.atomic_store(&job.cancel, true)
	if sync.atomic_load(&job.state) == .Asking {
		job.answer = .Skip
		sync.sema_post(&job.answered)
	}
}

// The job whose question the interface shows: the first that asks.
job_asking :: proc(app: ^App) -> ^Job {
	for job in app.jobs.list { if sync.atomic_load(&job.state) == .Asking { return job } }
	return nil
}

// The interface's answer to a name taken.
job_answer :: proc(job: ^Job, answer: Conflict, all: bool) {
	job.answer, job.answer_all = answer, all
	sync.sema_post(&job.answered)
}

job_current :: proc(job: ^Job, allocator := context.temp_allocator) -> string {
	sync.mutex_lock(&job.mutex)
	defer sync.mutex_unlock(&job.mutex)
	return strings.clone(job.current, allocator)
}

// Forgets the jobs that ended some time ago (each frame).
jobs_tidy :: proc(app: ^App) {
	now := ui.now_ms()
	j := &app.jobs
	for i := 0; i < len(j.list); {
		job := j.list[i]
		if job.ended_ms > 0 && now - job.ended_ms > JOB_SHOWN_MS {
			ordered_remove(&j.list, i)
			job_free(job)
			continue
		}
		i += 1
	}
}

////////////////////////////////
// The jobs' thread

@(private = "file")
jobs_work :: proc(data: rawptr) {
	app := (^App)(data)
	j := &app.jobs
	for {
		sync.mutex_lock(&j.mutex)
		for len(j.queue) == 0 && !j.quit { sync.cond_wait(&j.cond, &j.mutex) }
		if j.quit {
			sync.mutex_unlock(&j.mutex)
			return
		}
		job := j.queue[0]
		ordered_remove(&j.queue, 0)
		sync.mutex_unlock(&j.mutex)
		job_run(job)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
job_run :: proc(job: ^Job) {
	switch job.kind {
	case .Copy, .Move:
		sync.atomic_store(&job.state, Job_State.Counting)
		for s in job.sources { count_tree(job, s) }
		sync.atomic_store(&job.state, Job_State.Running)
		for s in job.sources {
			if cancelled(job) { break }
			target := fs.join(job.dest, fs.base(s), context.temp_allocator)
			if job.kind == .Copy { copy_one(job, s, target) } else { move_one(job, s, target) }
		}
	case .Trash, .Delete:
		sync.atomic_store(&job.files_total, len(job.sources))
		sync.atomic_store(&job.state, Job_State.Running)
		for s in job.sources {
			if cancelled(job) { break }
			set_current(job, fs.base(s))
			if job.kind == .Trash {
				if e := fs.trash(s); e != .None { job_error(job, s, e) }
			} else {
				if !fsx.remove_tree(s) { job_error(job, s, .Other) }
			}
			sync.atomic_add(&job.files_done, 1)
		}
	}
	end: Job_State = .Done
	if cancelled(job) { end = .Cancelled } else if len(job.errors) > 0 { end = .Failed }
	sync.atomic_store(&job.state, end)
	_ = ui.post(&job.app.main.state, job_ended, job)   // (false: the program ends, nobody reads it)
}

@(private = "file")
cancelled :: proc(job: ^Job) -> bool { return sync.atomic_load(&job.cancel) }

@(private = "file")
set_current :: proc(job: ^Job, name: string) {
	sync.mutex_lock(&job.mutex)
	delete(job.current)
	job.current = strings.clone(name)
	sync.mutex_unlock(&job.mutex)
}

@(private = "file")
job_error :: proc(job: ^Job, path: string, e: fs.Error) {
	if e == .Cancelled { return }
	verb := job.kind == .Copy ? "copied" : job.kind == .Move ? "moved" : job.kind == .Trash ? "moved to the trash" : "deleted"
	sync.mutex_lock(&job.mutex)
	append(&job.errors, fmt.aprintf("%s cannot be %s: %s.", fs.base(path), verb, fs.ERROR_REASON[e]))
	sync.mutex_unlock(&job.mutex)
}

// The files and bytes under `path` (what the progress counts to).
@(private = "file")
count_tree :: proc(job: ^Job, path: string) {
	if cancelled(job) { return }
	info, ok := fs.stat(path)
	if !ok { return }
	if info.kind != .Directory || .Link in info.flags {
		sync.atomic_add(&job.files_total, 1)
		if info.size > 0 { sync.atomic_add(&job.bytes_total, info.size) }
		return
	}
	l: fs.Listing
	defer fs.listing_destroy(&l)
	if fs.list(&l, path) != .None { return }
	for e in l.entries { count_tree(job, fs.join(path, e.name, context.temp_allocator)) }
}

@(private = "file")
on_bytes :: proc(user: rawptr, n: i64) { sync.atomic_add(&(^Job)(user).bytes_done, n) }
@(private = "file")
on_cancelled :: proc(user: rawptr) -> bool { return cancelled((^Job)(user)) }

// What to do with `target`, taken: the job's policy, else the person's answer (asked through the interface).
@(private = "file")
resolve :: proc(job: ^Job, target: string) -> Conflict {
	if job.policy != .Ask { return job.policy }
	delete(job.ask_name)
	job.ask_name = strings.clone(target)
	sync.atomic_store(&job.state, Job_State.Asking)
	ui.post(&job.app.main.state, job_asks, job)
	sync.sema_wait(&job.answered)
	sync.atomic_store(&job.state, Job_State.Running)
	if job.answer_all { job.policy = job.answer }
	return job.answer
}

// Copies `from` (a file, a link, a folder and what it holds) to `target`. A folder copied onto a folder merges into it.
@(private = "file")
copy_one :: proc(job: ^Job, from, target: string) -> (ok: bool) {
	if cancelled(job) { return false }
	info, found := fs.stat(from)
	if !found && !fs.exists(from) { job_error(job, from, .Not_Found); return false }
	to := target
	is_folder := info.kind == .Directory && .Link not_in info.flags
	if is_folder && (to == from || strings.has_prefix(to, strings.concatenate({from, fs.SEPARATOR_STRING}, context.temp_allocator))) {
		append_line(job, fmt.aprintf("%s cannot be copied into itself.", fs.base(from)))
		return false
	}
	set_current(job, fs.base(from))
	if fs.exists(to) {
		there, _ := fs.stat(to)
		merge := is_folder && there.kind == .Directory
		if !merge || to == from {
			choice := to == from ? Conflict.Keep_Both : resolve(job, to)
			switch choice {
			case .Skip, .Ask:
				return false
			case .Keep_Both:
				to = fs.join(fs.parent(to), fs.free_name(fs.parent(to), fs.base(to), context.temp_allocator), context.temp_allocator)
			case .Replace:
				if !fsx.remove_tree(to) { job_error(job, to, .Denied); return false }
			}
		}
	}
	if is_folder {
		if !fs.exists(to) {
			if e := fs.make_folder(to); e != .None { job_error(job, from, e); return false }
		}
		l: fs.Listing
		defer fs.listing_destroy(&l)
		if e := fs.list(&l, from); e != .None { job_error(job, from, e); return false }
		ok = true
		for e in l.entries {
			if !copy_one(job, fs.join(from, e.name, context.temp_allocator), fs.join(to, e.name, context.temp_allocator)) { ok = false }
		}
		return ok
	}
	e: fs.Error
	if .Link in info.flags || !found {
		e = fs.copy_link(from, to)
	} else {
		p := fs.Progress{user = job, on_bytes = on_bytes, cancelled = on_cancelled}
		e = fs.copy_file(from, to, &p)
	}
	sync.atomic_add(&job.files_done, 1)
	if e != .None { job_error(job, from, e); return false }
	return true
}

// Moves `from` to `target`: a rename on its volume, else a copy then the source deleted (only when all of it was
// copied).
@(private = "file")
move_one :: proc(job: ^Job, from, target: string) {
	if fs.parent(from) == fs.parent(target) && fs.base(from) == fs.base(target) { return }   // (already there)
	info, _ := fs.stat(from)
	set_current(job, fs.base(from))
	to := target
	e := fs.rename(from, to)
	if e == .Exists {
		there, _ := fs.stat(to)
		if info.kind == .Directory && there.kind == .Directory && .Link not_in info.flags {
			e = .Cross_Volume   // (a folder onto a folder: merged, as a copy is)
		} else {
			switch resolve(job, to) {
			case .Skip, .Ask:
				return
			case .Keep_Both:
				to = fs.join(fs.parent(to), fs.free_name(fs.parent(to), fs.base(to), context.temp_allocator), context.temp_allocator)
				e = fs.rename(from, to)
			case .Replace:
				if !fsx.remove_tree(to) { job_error(job, to, .Denied); return }
				e = fs.rename(from, to)
			}
		}
	}
	switch e {
	case .None:
		// (renamed in one step: its bytes count as done)
		if info.size > 0 { sync.atomic_add(&job.bytes_done, info.size) }
		sync.atomic_add(&job.files_done, 1)
	case .Cross_Volume:
		if copy_one(job, from, to) && !cancelled(job) {
			if !fsx.remove_tree(from) { job_error(job, from, .Denied) }
		}
	case .Not_Found, .Denied, .Not_A_Folder, .Exists, .No_Space, .Cancelled, .Other:
		job_error(job, from, e)
	}
}

@(private = "file")
append_line :: proc(job: ^Job, line: string) {
	sync.mutex_lock(&job.mutex)
	append(&job.errors, line)
	sync.mutex_unlock(&job.mutex)
}

////////////////////////////////
// On the interface's thread

// A job asks: a frame shows its question.
@(private = "file")
job_asks :: proc(data: rawptr, word: u64) {
	job := (^Job)(data)
	app_frames(job.app)
}

// A job ended: the folders it changed are read again, the status bar says what it did.
@(private = "file")
job_ended :: proc(data: rawptr, word: u64) {
	job := (^Job)(data)
	app := job.app
	touched := make([dynamic]string, context.temp_allocator)
	if job.dest != "" { append(&touched, job.dest) }
	for s in job.sources { append(&touched, fs.parent(s)) }
	for p in app.panels {
		for t in p.tabs {
			for d in touched { if t.path == d { tab_load(app, t); break } }
		}
	}
	st := sync.atomic_load(&job.state)
	n := len(job.sources)
	switch st {
	case .Done:
		say(app, "%d item%s %s.", n, n == 1 ? "" : "s", JOB_DONE[job.kind])
	case .Failed:
		say(app, "%s", job.errors[0])
	case .Cancelled:
		say(app, "%s: cancelled.", JOB_VERB[job.kind])
	case .Waiting, .Counting, .Running, .Asking:
	}
	job.ended_ms = ui.now_ms()
	app_frames(app)
	ui.wake_within(&app.main.state, JOB_SHOWN_MS + 1)   // (then jobs_tidy forgets it)
}
