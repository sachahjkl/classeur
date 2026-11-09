package classeur

// The workers: a few threads that run what must not hold the interface (reading a folder, measuring one, searching).
// A task runs on a worker and hands its result to the interface's thread with ui.post; the interface owns everything
// it reads. Tasks run in the order they came.

import "core:sync"
import "core:thread"

POOL_THREADS :: 3   // the workers that read folders (the measures have their own: MEASURE_THREADS)

Task :: struct {
	run:  proc(data: rawptr),
	data: rawptr,
}

Pool :: struct {
	mutex:   sync.Mutex,
	cond:    sync.Cond,
	tasks:   [dynamic]Task,
	threads: [dynamic]^thread.Thread,
	quit:    bool,
}

pool_start :: proc(p: ^Pool, threads := POOL_THREADS) {
	for _ in 0 ..< threads { append(&p.threads, thread.create_and_start_with_data(p, pool_work)) }
}

pool_submit :: proc(p: ^Pool, run: proc(data: rawptr), data: rawptr) {
	sync.mutex_lock(&p.mutex)
	append(&p.tasks, Task{run, data})
	sync.mutex_unlock(&p.mutex)
	sync.cond_signal(&p.cond)
}

// Ends the workers once the tasks that run have ended; the tasks that wait are dropped (`drop` gets their data).
pool_stop :: proc(p: ^Pool, drop: proc(data: rawptr) = nil) {
	sync.mutex_lock(&p.mutex)
	p.quit = true
	left := p.tasks[:]
	sync.mutex_unlock(&p.mutex)
	sync.cond_broadcast(&p.cond)
	for t in p.threads {
		if t == nil { continue }
		thread.join(t)
		thread.destroy(t)
	}
	if drop != nil { for task in left { drop(task.data) } }
	delete(p.tasks)
	delete(p.threads)
	p^ = {}
}

@(private = "file")
pool_work :: proc(data: rawptr) {
	p := (^Pool)(data)
	for {
		sync.mutex_lock(&p.mutex)
		for len(p.tasks) == 0 && !p.quit { sync.cond_wait(&p.cond, &p.mutex) }
		if p.quit {
			sync.mutex_unlock(&p.mutex)
			return
		}
		task := p.tasks[0]
		ordered_remove(&p.tasks, 0)
		sync.mutex_unlock(&p.mutex)
		task.run(task.data)
		free_all(context.temp_allocator)
	}
}
