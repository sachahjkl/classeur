package classeur

// The jobs: copy, move, trash and delete, one at a time, on a thread of their own (two copies at once on one disk are
// slower than one after the other). A job is made on the interface's thread with what it must do (its sources, its
// destination); the thread reports its progress in atomics the status bar reads, and posts to the interface when it
// needs an answer (a name already taken) and when it ends. The interface owns the list of jobs; a job is freed by the
// interface when it has ended and is no longer shown.

import "core:fmt"
import "core:math"
import "core:strings"
import "core:sync"
import "core:thread"
import "gt:fsx"
import "gt:i18n"
import "gt:ui"
import "fs"

Job_Kind :: enum u8 { Copy, Move, Trash, Delete, Restore }

Job_State :: enum u8 { Waiting, Counting, Running, Asking, Done, Failed, Cancelled }

// What a name already taken at the destination becomes.
Conflict :: enum u8 { Ask, Replace, Skip, Keep_Both }

// What a job does, a label (i18n.later: tr where it is shown).
JOB_VERB := [Job_Kind]string{.Copy = i18n.later("Copying"), .Move = i18n.later("Moving"), .Trash = i18n.later("Moving to the trash"), .Delete = i18n.later("Deleting"), .Restore = i18n.later("Putting back")}


Job :: struct {
	id:      u64,
	kind:    Job_Kind,
	sources: []string,     // owned, absolute
	dest:    string,       // owned: the folder (Copy, Move)
	targets: []string,     // owned: when set, each source's own target path (Copy, Move), not dest/<its name>
	policy:  Conflict,     // for every conflict; Ask: the person says, then maybe for all
	undoing: bool,         // an undo's job: what it does is not undone in turn
	redoing: bool,         // a redo's job: its step goes back on the undo stack, what can be done again stays
	redo_step: Undo_Step,  // an undo's job: the step undone, to the redo stack when the job ends well (else freed)

	// written by the jobs' thread, read by the interface
	state:       Job_State,   // atomic
	bytes_total: i64,         // atomic
	bytes_done:  i64,         // atomic
	files_total: int,         // atomic
	files_done:  int,         // atomic
	cancel:      bool,        // atomic: set by the interface
	mutex:       sync.Mutex,  // guards `current`, `errors` and the two files asked about
	current:     string,      // owned: the name being done
	errors:      [dynamic]string,   // owned: what failed, one line each
	done:        [dynamic][2]string,   // owned: each source done and where it is now (undo.odin reads them)

	// a name taken: the jobs' thread waits on `answered` until the interface sets `answer`
	ask_name:   string,       // owned (by the jobs' thread while it waits)
	ask_there:  fs.Info,      // under `mutex`: the file at ask_name and the one that comes, for the question to compare
	ask_coming: fs.Info,
	answer:     Conflict,
	answer_all: bool,
	answered:   sync.Sema,

	ended_ms:   f64,          // the interface's clock when job_ended ran (0: not yet: the job is not freed before)
	started_ms: f64,          // the interface's clock when the jobs' view first saw it (jobs_view.odin)

	// the interface's: the speed, from bytes_done read every JOB_RATE_STEP_MS (job_rate_update)
	rate:         f64,        // bytes per second, smoothed (0: not known)
	rate_ms:      f64,        // when it last stepped (0: not sampling: the job does not run)
	rate_bytes:   i64,        // bytes_done then
	rate_from_ms: f64,        // the first sample: no speed is shown in the first second
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
job_add :: proc(app: ^App, kind: Job_Kind, sources: []string, dest := "", policy := Conflict.Ask, targets: []string = nil, undoing := false) -> ^Job {
	j := &app.jobs
	job := new(Job)
	j.next_id += 1
	job.id, job.kind, job.policy, job.app = j.next_id, kind, policy, app
	job.sources = make([]string, len(sources))
	for s, i in sources { job.sources[i] = strings.clone(s) }
	job.dest = strings.clone(dest)
	job.undoing = undoing
	if targets != nil {
		job.targets = make([]string, len(targets))
		for s, i in targets { job.targets[i] = strings.clone(s) }
	}
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
	for s in job.targets { delete(s) }
	delete(job.targets)
	for d in job.done { delete(d[0]); delete(d[1]) }
	delete(job.done)
	undo_step_free(&job.redo_step)
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

// How often the speed steps, how slowly it follows (seconds: a burst of small files moves it a little), and how long it
// is kept to itself at the start (the first reads are cached or slow).
JOB_RATE_STEP_MS :: 400
JOB_RATE_TAU :: 3.0
JOB_RATE_AFTER_MS :: 1000

// The speed after `seconds` that did `bytes`: an average that forgets at the same pace whatever the steps.
rate_step :: proc(prev: f64, bytes: i64, seconds: f64) -> f64 {
	if seconds <= 0 { return prev }
	now := f64(max(bytes, 0)) / seconds
	if prev <= 0 { return now }
	k := 1 - math.exp(-seconds / JOB_RATE_TAU)
	return prev + (now - prev) * k
}

// "42 MB/s".
rate_text :: proc(bytes_per_second: f64, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%s/s", size_text(i64(bytes_per_second)), allocator = allocator)
}

// "12 s left", "2 min left", "1 h 5 min left" (rounded up: a minute left is not "0 min").
eta_text :: proc(seconds: f64, allocator := context.temp_allocator) -> string {
	s := int(math.ceil(max(seconds, 0)))
	if s < 60 { return fmt.aprintf(i18n.tr("%d s left"), s, allocator = allocator) }
	if s < 3600 { return fmt.aprintf(i18n.tr("%d min left"), (s + 59) / 60, allocator = allocator) }
	h, m := s / 3600, (s % 3600 + 59) / 60
	if m == 60 { h, m = h + 1, 0 }
	if m == 0 { return fmt.aprintf(i18n.tr("%d h left"), h, allocator = allocator) }
	return fmt.aprintf(i18n.tr("%d h %d min left"), h, m, allocator = allocator)
}

// Each frame, on the interface's thread: the speed steps from the bytes done (atomics: no lock, no disk). While the job
// waits (an answer, its turn) the sampling stops, so the time it waits does not read as slowness.
job_rate_update :: proc(app: ^App, job: ^Job, now: f64) {
	if sync.atomic_load(&job.state) != .Running {
		job.rate_ms = 0
		return
	}
	done := sync.atomic_load(&job.bytes_done)
	if job.rate_ms == 0 {
		job.rate_ms, job.rate_bytes = now, done
		if job.rate_from_ms == 0 { job.rate_from_ms = now }
	} else if now - job.rate_ms >= JOB_RATE_STEP_MS {
		job.rate = rate_step(job.rate, done - job.rate_bytes, (now - job.rate_ms) / 1000)
		job.rate_ms, job.rate_bytes = now, done
	}
	ui.wake_within(&app.main.state, int(JOB_RATE_STEP_MS - (now - job.rate_ms)) + 1)
}

// " · 42 MB/s · 2 min left" for a job that runs, "" while its speed is not known (the first second, nothing moved);
// the time left only with a total to go by.
job_rate_fields :: proc(job: ^Job, now: f64) -> string {
	if job.rate <= 0 || job.rate_from_ms == 0 || now - job.rate_from_ms < JOB_RATE_AFTER_MS { return "" }
	text := fmt.tprintf(" · %s", rate_text(job.rate))
	total, done := sync.atomic_load(&job.bytes_total), sync.atomic_load(&job.bytes_done)
	if total > 0 && job.rate >= 1 { text = fmt.tprintf("%s · %s", text, eta_text(f64(max(total - done, 0)) / job.rate)) }
	return text
}

// The footer's line for a job that runs: "Copying 3 of 40 · name · 42 MB/s · 2 min left".
job_status_text :: proc(job: ^Job, now: f64) -> string {
	st := sync.atomic_load(&job.state)
	if st == .Counting { return fmt.tprintf(i18n.tr("%s: counting…"), i18n.tr(JOB_VERB[job.kind])) }
	files, files_done := sync.atomic_load(&job.files_total), sync.atomic_load(&job.files_done)
	return fmt.tprintf(i18n.tr("%s %d of %d · %s%s"), i18n.tr(JOB_VERB[job.kind]), min(files_done + 1, files), files, ui.text_shown(job_current(job)), job_rate_fields(job, now))
}

job_current :: proc(job: ^Job, allocator := context.temp_allocator) -> string {
	sync.mutex_lock(&job.mutex)
	defer sync.mutex_unlock(&job.mutex)
	return strings.clone(job.current, allocator)
}

// The ended jobs kept for the jobs' window (jobs_view.odin): the oldest go past this many.
JOBS_KEPT :: 50

// Forgets the oldest ended jobs past JOBS_KEPT (each frame). (The status bar shows a job only while it runs.)
jobs_tidy :: proc(app: ^App) {
	j := &app.jobs
	ended := 0
	for job in j.list { if job.ended_ms > 0 { ended += 1 } }
	for i := 0; i < len(j.list) && ended > JOBS_KEPT; {
		job := j.list[i]
		if job.ended_ms > 0 {
			ordered_remove(&j.list, i)
			job_free(job)
			ended -= 1
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
		for s, i in job.sources {
			if cancelled(job) { break }
			target := job.targets != nil ? job.targets[i] : fs.join(job.dest, fs.base(s), context.temp_allocator)
			// (a folder merged into one that was there: no step, its undo would take what was there before)
			merged := fs.exists(target) && is_folder(s) && is_folder(target) && target != s
			at: string
			ok: bool
			if job.kind == .Copy { at, ok = copy_one(job, s, target) } else { at, ok = move_one(job, s, target) }
			if ok && !(merged && at == target) { job_did(job, s, at) }
		}
	case .Restore:
		sync.atomic_store(&job.files_total, len(job.sources))
		sync.atomic_store(&job.state, Job_State.Running)
		for s in job.sources {
			if cancelled(job) { break }
			set_current(job, fs.base(s))
			restore_one(job, s)
			sync.atomic_add(&job.files_done, 1)
		}
	case .Trash, .Delete:
		sync.atomic_store(&job.files_total, len(job.sources))
		sync.atomic_store(&job.state, Job_State.Running)
		for s in job.sources {
			if cancelled(job) { break }
			set_current(job, fs.base(s))
			if job.kind == .Trash {
				in_trash, e := fs.trash(s, context.temp_allocator)
				if e != .None { job_error(job, s, e) } else if in_trash != "" { job_did(job, s, in_trash) }
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
is_folder :: proc(path: string) -> bool {
	info, ok := fs.stat(path)
	return ok && info.kind == .Directory && .Link not_in info.flags
}

// A source done: where it is now.
@(private = "file")
job_did :: proc(job: ^Job, source, now: string) {
	sync.mutex_lock(&job.mutex)
	append(&job.done, [2]string{strings.clone(source), strings.clone(now)})
	sync.mutex_unlock(&job.mutex)
}

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
	said := ""
	switch job.kind {
	case .Copy:    said = i18n.tr("%s cannot be copied: %s.")
	case .Move:    said = i18n.tr("%s cannot be moved: %s.")
	case .Trash:   said = i18n.tr("%s cannot be moved to the trash: %s.")
	case .Delete:  said = i18n.tr("%s cannot be deleted: %s.")
	case .Restore: said = i18n.tr("%s cannot be put back: %s.")
	}
	sync.mutex_lock(&job.mutex)
	append(&job.errors, fmt.aprintf(said, fs.base(path), i18n.tr(fs.ERROR_REASON[e])))
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

// What to do with `target`, taken: the job's policy, else the person's answer (asked through the interface). `there`
// and `coming`: the two files as read here (the interface reads no disk).
@(private = "file")
resolve :: proc(job: ^Job, target: string, there, coming: fs.Info) -> Conflict {
	if job.policy != .Ask { return job.policy }
	delete(job.ask_name)
	job.ask_name = strings.clone(target)
	sync.mutex_lock(&job.mutex)
	job.ask_there, job.ask_coming = there, coming
	sync.mutex_unlock(&job.mutex)
	sync.atomic_store(&job.state, Job_State.Asking)
	// (cancelled meanwhile, or nobody to ask: skipped; jobs_stop sets `cancel` before it looks for a job that asks)
	if cancelled(job) || !ui.post(&job.app.main.state, job_asks, job) {
		sync.atomic_store(&job.state, Job_State.Running)
		return .Skip
	}
	sync.sema_wait(&job.answered)
	sync.atomic_store(&job.state, Job_State.Running)
	if job.answer_all { job.policy = job.answer }
	return job.answer
}

// Copies `from` (a file, a link, a folder and what it holds) to `target`. A folder copied onto a folder merges into it.
// `at`: where the copy is (target, or the free name kept beside it).
@(private = "file")
copy_one :: proc(job: ^Job, from, target: string) -> (at: string, ok: bool) {
	if cancelled(job) { return }
	info, found := fs.stat(from)
	if !found && !fs.exists(from) { job_error(job, from, .Not_Found); return }
	to := target
	is_folder := info.kind == .Directory && .Link not_in info.flags
	if is_folder && (to == from || strings.has_prefix(to, strings.concatenate({from, fs.SEPARATOR_STRING}, context.temp_allocator))) {
		append_line(job, fmt.aprintf(i18n.tr("%s cannot be copied into itself."), fs.base(from)))
		return
	}
	set_current(job, fs.base(from))
	if fs.exists(to) {
		there, _ := fs.stat(to)
		merge := is_folder && there.kind == .Directory
		if !merge || to == from {
			choice := to == from ? Conflict.Keep_Both : resolve(job, to, there, info)
			switch choice {
			case .Skip, .Ask:
				return
			case .Keep_Both:
				to = fs.join(fs.parent(to), fs.free_name(fs.parent(to), fs.base(to), context.temp_allocator), context.temp_allocator)
			case .Replace:
				if !fsx.remove_tree(to) { job_error(job, to, .Denied); return }
			}
		}
	}
	if is_folder {
		if !fs.exists(to) {
			if e := fs.make_folder(to); e != .None { job_error(job, from, e); return }
		}
		l: fs.Listing
		defer fs.listing_destroy(&l)
		if e := fs.list(&l, from); e != .None { job_error(job, from, e); return }
		ok = true
		for e in l.entries {
			if _, cok := copy_one(job, fs.join(from, e.name, context.temp_allocator), fs.join(to, e.name, context.temp_allocator)); !cok { ok = false }
		}
		return to, ok
	}
	e: fs.Error
	if .Link in info.flags || !found {
		e = fs.copy_link(from, to)
	} else {
		p := fs.Progress{user = job, on_bytes = on_bytes, cancelled = on_cancelled}
		e = fs.copy_file(from, to, &p)
	}
	sync.atomic_add(&job.files_done, 1)
	if e != .None { job_error(job, from, e); return }
	return to, true
}

// Moves `from` to `target`: a rename on its volume, else a copy then the source deleted (only when all of it was
// copied).
@(private = "file")
move_one :: proc(job: ^Job, from, target: string) -> (at: string, ok: bool) {
	if fs.parent(from) == fs.parent(target) && fs.base(from) == fs.base(target) { return }   // (already there: nothing to undo)
	info, _ := fs.stat(from)
	set_current(job, fs.base(from))
	to := target
	e := fs.rename(from, to)
	if e == .Exists {
		there, _ := fs.stat(to)
		if info.kind == .Directory && there.kind == .Directory && .Link not_in info.flags {
			e = .Cross_Volume   // (a folder onto a folder: merged, as a copy is)
		} else {
			switch resolve(job, to, there, info) {
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
		return to, true
	case .Cross_Volume:
		if copied, cok := copy_one(job, from, to); cok && !cancelled(job) {
			if !fsx.remove_tree(from) { job_error(job, from, .Denied); return }
			return copied, true
		}
	case .Not_Found, .Denied, .Not_A_Folder, .Exists, .No_Space, .Cancelled, .Read_Only, .Other:
		job_error(job, from, e)
	}
	return
}

// Puts an item of the trash back where it was. A name taken there now is asked about, as a copy's is: replaced, skipped
// or kept beside it under a free name.
@(private = "file")
restore_one :: proc(job: ^Job, s: string) {
	original, e := fs.untrash(s, context.temp_allocator)
	if e == .Exists {
		if to, ok := fs.trash_origin(s); ok {
			there, _ := fs.stat(to)
			coming, _ := fs.stat(s)
			switch resolve(job, to, there, coming) {
			case .Skip, .Ask:
				return
			case .Keep_Both:
				dir := fs.parent(to)
				original, e = fs.untrash(s, context.temp_allocator, fs.join(dir, fs.free_name(dir, fs.base(to), context.temp_allocator), context.temp_allocator))
			case .Replace:
				if !fsx.remove_tree(to) { job_error(job, to, .Denied); return }
				original, e = fs.untrash(s, context.temp_allocator)
			}
		}
	}
	if e != .None { job_error(job, s, e) } else { job_did(job, s, original) }
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
	for s in job.targets { append(&touched, fs.parent(s)) }
	for d in job.done { append(&touched, fs.parent(d[1])) }   // (a restore: where the items came back)
	// (the trash's tab: on Windows its items are not in its folder, which is no folder of the disk)
	if job.kind == .Trash || job.kind == .Restore || job.kind == .Delete { append(&touched, fs.trash_files_dir()) }
	if !job.undoing { undo_push_job(app, job) }
	if job.redo_step.pairs != nil && sync.atomic_load(&job.state) == .Done {
		append(&app.redo, job.redo_step)
		job.redo_step = {}
	}
	for p in app.panels {
		for t in p.tabs {
			// (a copy or a move into the tab's folder: what it made there is selected once the folder is read again)
			if (job.kind == .Copy || job.kind == .Move) && job.dest != "" && t.path == job.dest {
				tab_select_forget(t)
				for d in job.done { if fs.parent(d[1]) == t.path { append(&t.select_names, strings.clone(fs.base(d[1]))) } }
			}
			for d in touched { if t.path == d { tab_load(app, t); break } }
		}
	}
	st := sync.atomic_load(&job.state)
	n := len(job.sources)
	said := ""
	switch st {
	case .Done:      said = fmt.tprintf(job_done_text(job.kind, n), n)
	case .Failed:    said = job.errors[0]
	case .Cancelled: said = fmt.tprintf(i18n.tr("%s: cancelled."), i18n.tr(JOB_VERB[job.kind]))
	case .Waiting, .Counting, .Running, .Asking:
	}
	if said != "" { announce(app, st == .Done ? .Good : st == .Failed ? .Bad : .Info, "%s", said) }
	job.ended_ms = ui.now_ms()
	app_frames(app)
}

// What a job that ended well says: "%d items copied." (a whole sentence for each kind, its form for the count).
@(private = "file")
job_done_text :: proc(kind: Job_Kind, n: int) -> string {
	switch kind {
	case .Copy:    return i18n.tr(n, "%d item copied.", "%d items copied.")
	case .Move:    return i18n.tr(n, "%d item moved.", "%d items moved.")
	case .Trash:   return i18n.tr(n, "%d item moved to the trash.", "%d items moved to the trash.")
	case .Delete:  return i18n.tr(n, "%d item deleted.", "%d items deleted.")
	case .Restore: return i18n.tr(n, "%d item put back.", "%d items put back.")
	}
	return ""
}
