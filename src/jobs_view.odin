package classeur

// The jobs' window (Ctrl+Alt+J, or the footer's button while a job runs or failed): every job of the session, the last
// first: what it does, how far, what failed; Cancel for one that runs, Retry for one that failed or was cancelled (the
// same job again: a name taken asks again).

import "core:fmt"
import "core:sync"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

JOBS_VIEW_ROWS :: 8

Jobs_View :: struct {
	open:   bool,
	scroll: int,
}

act_jobs :: proc(app: ^App) {
	app.jobs_view.open = !app.jobs_view.open
	app.jobs_view.scroll = 0
}

// The same job again.
job_retry :: proc(app: ^App, job: ^Job) {
	retry := job_add(app, job.kind, job.sources, job.dest, targets = job.targets)
	retry.undoing, retry.redoing = job.undoing, job.redoing
	say(app, "%s again.", JOB_VERB[job.kind])
}

// What a job is about: its first item, and how many more.
@(private = "file")
job_title :: proc(job: ^Job) -> string {
	if len(job.sources) == 0 { return JOB_VERB[job.kind] }
	more := len(job.sources) > 1 ? fmt.tprintf(" and %d more", len(job.sources) - 1) : ""
	to := job.dest != "" ? fmt.tprintf(" to %s", fs.base(job.dest)) : ""
	return fmt.tprintf("%s %s%s%s", JOB_VERB[job.kind], fs.base(job.sources[0]), more, to)
}

jobs_view_build :: proc(app: ^App, em: f32) {
	v := &app.jobs_view
	if !v.open { return }
	w := min(em * 44, app.room * ui.scale() * 0.9)
	list := app.jobs.list[:]
	n := len(list)
	if ui.key_press(.Down) { v.scroll += 1 }
	if ui.key_press(.Up) { v.scroll -= 1 }
	v.scroll = clamp(v.scroll, 0, max(n - JOBS_VIEW_ROWS, 0))
	if ui.modal("jobs", w, &v.open, 0.1) {
		ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 2.8))})
		if ui.row(.Center, id = "###jobs_head") {
			ui.spacer(ui.px(em * 0.9))
			if ui.tags("weak") { glyph(app, lucide.LAYERS_2, em * 1.6) }
			ui.next({width = ui.fill(), height = ui.pct(1)})
			ui.label(n == 0 ? "No job yet###jobs_title" : fmt.tprintf("Jobs: %d###jobs_title", n))
		}
		ui.hline(ui.px(w))
		ui.next({width = ui.px(w), height = ui.children_sum(), axis = .Y})
		if ui.column(.Start, {}, "###jobs_rows") {
			// (the last first)
			for vi in 0 ..< min(n, JOBS_VIEW_ROWS) {
				job := list[n - 1 - (v.scroll + vi)]
				st := sync.atomic_load(&job.state)
				ui.next({width = ui.px(w), height = ui.children_sum(), axis = .Y})
				if ui.column(.Start, {.Draw_Side_Bottom}, fmt.tprintf("###job%d", job.id)) {
					ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 2.4))})
					if ui.row(.Center, id = "###line") {
						ui.spacer(ui.px(em * 0.9))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label(fmt.tprintf("%s###what", shown_text(job_title(job))))
						state := ""
						switch st {
						case .Waiting:   state = "waiting"
						case .Counting:  state = "counting…"
						case .Running:   state = fmt.tprintf("%d of %d", sync.atomic_load(&job.files_done), sync.atomic_load(&job.files_total))
						case .Asking:    state = "asks"
						case .Done:      state = "done"
						case .Failed:    state = fmt.tprintf("%d failed", len(job.errors))
						case .Cancelled: state = "cancelled"
						}
						if ui.tags("weak") {
							ui.next({width = ui.text_size(em * 0.6), height = ui.pct(1)})
							ui.label(fmt.tprintf("%s###state", state))
						}
						running := st == .Waiting || st == .Counting || st == .Running || st == .Asking
						if running {
							total, done := sync.atomic_load(&job.bytes_total), sync.atomic_load(&job.bytes_done)
							ui.next({width = ui.px(em * 6), height = ui.px(em * 0.45)})
							ui.progress("###bar", total > 0 ? clamp(f32(f64(done) / f64(total)), 0, 1) : 0, st == .Counting)
							ui.spacer(ui.px(em * 0.4))
							ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 1.9))})
							if ui.button("Cancel###cancel").clicked { job_cancel(job) }
						}
						if st == .Failed || st == .Cancelled {
							ui.spacer(ui.px(em * 0.4))
							ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 1.9))})
							if ui.tags("accent_button") { if ui.button("Retry###retry").clicked { job_retry(app, job) } }
						}
						ui.spacer(ui.px(em * 0.9))
					}
					// what failed, a line each (the first few)
					sync.mutex_lock(&job.mutex)
					for e, i in job.errors {
						if i == 3 {
							ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 1.7)), font_size = em * 0.85})
							if ui.tags("weak") { ui.label(fmt.tprintf("    and %d more###more", len(job.errors) - 3)) }
							break
						}
						ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 1.7)), font_size = em * 0.85, fg = ui.color("bad text")})
						ui.label(fmt.tprintf("    %s###err%d", shown_text(e), i))
					}
					sync.mutex_unlock(&job.mutex)
				}
			}
		}
		ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 2.2))})
		if ui.row(.Center, id = "###jobs_foot") {
			ui.spacer(ui.px(em * 0.9))
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.pct(1), font_size = em * 0.85})
				ui.label("Up, Down: the jobs before   Esc: close###jobs_help")
			}
		}
	}
}
