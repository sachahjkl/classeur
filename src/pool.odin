package classeur

// The workers: a few threads that run what must not hold the interface (reading a folder, measuring one, searching).
// A task runs on a worker and hands its result to the interface's thread with ui.post; the interface owns everything
// it reads. Tasks run in the order they came, or the newest first (newest_first: the pictures of the grid, where the
// cards last built are the ones on screen); an urgent task runs before them all.
//
// A pool may grow: a read of a share that hangs holds its worker for good, and three of them would hold every later
// read of a local folder. So when tasks wait, no worker is free and none has taken or ended a task for POOL_STUCK, a
// watcher starts one more worker (up to `grow` more); a worker so added ends when it has had nothing to do for
// POOL_EXTRA_IDLE. A pool for the shares alone would need to know which paths are on a share before reading them (the
// mount table, a system call), and a local disk can hang too (one asleep, a FUSE mount); the growth covers them all.

import "core:sync"
import "core:thread"
import "core:time"

POOL_THREADS    :: 3                 // the workers that read folders (the measures have their own: MEASURE_THREADS)
POOL_GROW       :: 8                 // the workers the reads may add while theirs are held
POOL_STUCK      :: time.Second       // no worker free nor moving for this long: one more is started
POOL_EXTRA_IDLE :: 5 * time.Second   // an added worker with nothing to do for this long ends

Task :: struct {
	run:  proc(data: rawptr),
	data: rawptr,
}

Pool :: struct {
	mutex:        sync.Mutex,
	cond:         sync.Cond,         // a task came, or the pool stops (the workers)
	watch_cond:   sync.Cond,         // the same, for the watcher
	tasks:        [dynamic]Task,
	urgent:       [dynamic]Task,     // taken before the tasks
	threads:      [dynamic]^thread.Thread,   // the workers, those added included (an added one that ended is let go later)
	watch:        ^thread.Thread,    // starts the workers added (nil: the pool does not grow)
	newest_first: bool,
	grow:         int,               // the workers that may be added
	extras:       int,               // the workers added that run
	idle:         int,               // the workers waiting for a task
	moved:        time.Tick,         // the last time a worker took or ended a task
	quit:         bool,
}

pool_start :: proc(p: ^Pool, threads := POOL_THREADS, grow := 0, newest_first := false) {
	p.grow, p.newest_first, p.moved = grow, newest_first, time.tick_now()
	for _ in 0 ..< threads { append(&p.threads, thread.create_and_start_with_data(p, pool_work)) }
	if grow > 0 { p.watch = thread.create_and_start_with_data(p, pool_watch) }
}

// `urgent`: the task runs before those waiting (a tiny read the rows wait for, not to come after the pictures).
pool_submit :: proc(p: ^Pool, run: proc(data: rawptr), data: rawptr, urgent := false) {
	sync.mutex_lock(&p.mutex)
	append(urgent ? &p.urgent : &p.tasks, Task{run, data})
	sync.mutex_unlock(&p.mutex)
	sync.cond_signal(&p.cond)
	sync.cond_signal(&p.watch_cond)
}

// Ends the workers once the tasks that run have ended; the tasks that wait are dropped (`drop` gets their data). With
// `until`, a worker still in its task then is left to end alone (a read of a share that hangs: the process's end ends
// it): false, and the pool's memory stays, the worker reads it till it leaves.
pool_stop :: proc(p: ^Pool, drop: proc(data: rawptr) = nil, until: Maybe(time.Tick) = nil) -> bool {
	sync.mutex_lock(&p.mutex)
	p.quit = true
	sync.mutex_unlock(&p.mutex)
	sync.cond_broadcast(&p.cond)
	sync.cond_broadcast(&p.watch_cond)
	if end, limited := until.?; limited {
		// (no join with a time limit: the threads' ends looked at until then)
		for !pool_ended(p) && time.tick_diff(time.tick_now(), end) > 0 { time.sleep(2 * time.Millisecond) }
		if !pool_ended(p) {
			if drop != nil {
				sync.mutex_lock(&p.mutex)
				for task in p.urgent { drop(task.data) }
				for task in p.tasks { drop(task.data) }
				clear(&p.urgent)
				clear(&p.tasks)
				sync.mutex_unlock(&p.mutex)
			}
			return false
		}
	}
	// (the watcher first: it adds to the threads)
	if p.watch != nil {
		thread.join(p.watch)
		thread.destroy(p.watch)
	}
	for t in p.threads {
		if t == nil { continue }
		thread.join(t)
		thread.destroy(t)
	}
	if drop != nil {
		for task in p.urgent { drop(task.data) }
		for task in p.tasks { drop(task.data) }
	}
	delete(p.tasks)
	delete(p.urgent)
	delete(p.threads)
	p^ = {}
	return true
}

@(private = "file")
pool_ended :: proc(p: ^Pool) -> bool {
	if p.watch != nil && !thread.is_done(p.watch) { return false }
	for t in p.threads { if t != nil && !thread.is_done(t) { return false } }
	return true
}

@(private = "file")
pool_queued :: proc(p: ^Pool) -> int { return len(p.tasks) + len(p.urgent) }

@(private = "file")
pool_work :: proc(data: rawptr) { pool_loop((^Pool)(data), false) }

@(private = "file")
pool_work_extra :: proc(data: rawptr) { pool_loop((^Pool)(data), true) }

@(private = "file")
pool_loop :: proc(p: ^Pool, extra: bool) {
	for {
		sync.mutex_lock(&p.mutex)
		p.idle += 1
		for pool_queued(p) == 0 && !p.quit {
			if !extra {
				sync.cond_wait(&p.cond, &p.mutex)
			} else if !sync.cond_wait_with_timeout(&p.cond, &p.mutex, POOL_EXTRA_IDLE) && pool_queued(p) == 0 && !p.quit {
				// (an added worker idle: the hold that called it is over)
				p.idle -= 1
				p.extras -= 1
				sync.mutex_unlock(&p.mutex)
				return
			}
		}
		p.idle -= 1
		if p.quit {
			sync.mutex_unlock(&p.mutex)
			return
		}
		task: Task
		if len(p.urgent) > 0 {
			task = p.urgent[0]
			ordered_remove(&p.urgent, 0)
		} else if p.newest_first {
			task = pop(&p.tasks)
		} else {
			task = p.tasks[0]
			ordered_remove(&p.tasks, 0)
		}
		p.moved = time.tick_now()
		sync.mutex_unlock(&p.mutex)
		task.run(task.data)
		free_all(context.temp_allocator)
		sync.mutex_lock(&p.mutex)
		p.moved = time.tick_now()
		sync.mutex_unlock(&p.mutex)
	}
}

// The watcher: asleep while no task waits; else it looks four times per POOL_STUCK whether the workers are all held.
@(private = "file")
pool_watch :: proc(data: rawptr) {
	p := (^Pool)(data)
	sync.mutex_lock(&p.mutex)
	defer sync.mutex_unlock(&p.mutex)
	for !p.quit {
		if pool_queued(p) == 0 {
			sync.cond_wait(&p.watch_cond, &p.mutex)
			continue
		}
		sync.cond_wait_with_timeout(&p.watch_cond, &p.mutex, POOL_STUCK / 4)
		if p.quit || pool_queued(p) == 0 || p.idle > 0 || p.extras >= p.grow || time.tick_since(p.moved) < POOL_STUCK { continue }
		// (the added workers that ended go first: the list does not grow with each hold)
		for i := len(p.threads) - 1; i >= 0; i -= 1 {
			if thread.is_done(p.threads[i]) {
				thread.destroy(p.threads[i])
				unordered_remove(&p.threads, i)
			}
		}
		p.extras += 1
		p.moved = time.tick_now()
		append(&p.threads, thread.create_and_start_with_data(p, pool_work_extra))
	}
}
