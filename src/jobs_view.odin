package classeur

// The jobs' view: a panel over the footer's jobs button that leaves the rest of the window working (the jobs run on their
// own thread whatever is shown). It opens by itself once for a job still running after JOBS_VIEW_AFTER_MS; Background
// (or Escape) sends it away, the footer's button (its progress) or Ctrl+Alt+J brings it back. Every job of the session,
// the last first: what it does, how far, what failed; Cancel for one that runs, Retry for one that failed or was
// cancelled (the same job again: a name taken asks again).

import "core:fmt"
import "core:sync"
import "gt:i18n"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

JOBS_VIEW_ROWS :: 8
JOBS_VIEW_AFTER_MS :: 700

Jobs_View :: struct {
	open:      bool,
	anchor:    ui.Rect,   // the footer's jobs button, as last laid out (the panel stands over it)
	shown_for: u64,       // the last job the panel opened by itself for (once per job)
}

act_jobs :: proc(app: ^App) { app.jobs_view.open = !app.jobs_view.open }

// Each frame: the panel opens by itself for a job that runs on (once per job; one sent to the background stays there).
jobs_view_follow :: proc(app: ^App) {
	v := &app.jobs_view
	now := ui.now_ms()
	for job in app.jobs.list { if job.ended_ms == 0 { job_rate_update(app, job, now) } }
	for job in app.jobs.list {
		if job.ended_ms != 0 || job.id <= v.shown_for { continue }
		if job.started_ms == 0 { job.started_ms = now }
		if now - job.started_ms >= JOBS_VIEW_AFTER_MS {
			v.shown_for = job.id
			v.open = true
		} else {
			ui.wake_within(&app.main.state, int(JOBS_VIEW_AFTER_MS - (now - job.started_ms)) + 1)
		}
	}
}

// The progress of the jobs that run (0..1), and whether one runs.
jobs_progress :: proc(app: ^App) -> (t: f32, running: bool) {
	total, done: i64
	for job in app.jobs.list {
		if job.ended_ms != 0 { continue }
		running = true
		total += sync.atomic_load(&job.bytes_total)
		done += sync.atomic_load(&job.bytes_done)
	}
	if total > 0 { t = clamp(f32(f64(done) / f64(total)), 0, 1) }
	return
}

// The same job again.
job_retry :: proc(app: ^App, job: ^Job) {
	retry := job_add(app, job.kind, job.sources, job.dest, targets = job.targets)
	retry.undoing, retry.redoing = job.undoing, job.redoing
	say(app, i18n.tr("%s again."), i18n.tr(JOB_VERB[job.kind]))
}

// What a job is about: its first item, and how many more.
@(private = "file")
job_title :: proc(job: ^Job) -> string {
	if len(job.sources) == 0 { return i18n.tr(JOB_VERB[job.kind]) }
	// (a whole sentence for each kind, with or without more items and a destination: a language orders them its way)
	name, more, to := fs.base(job.sources[0]), len(job.sources) - 1, fs.base(job.dest)
	switch job.kind {
	case .Copy:
		switch {
		case more > 0 && to != "": return fmt.tprintf(i18n.tr(more, "Copying %s and %d more to %s", "Copying %s and %d more to %s"), name, more, to)
		case more > 0:             return fmt.tprintf(i18n.tr(more, "Copying %s and %d more", "Copying %s and %d more"), name, more)
		case to != "":             return fmt.tprintf(i18n.tr("Copying %s to %s"), name, to)
		}
		return fmt.tprintf(i18n.tr("Copying %s"), name)
	case .Move:
		switch {
		case more > 0 && to != "": return fmt.tprintf(i18n.tr(more, "Moving %s and %d more to %s", "Moving %s and %d more to %s"), name, more, to)
		case more > 0:             return fmt.tprintf(i18n.tr(more, "Moving %s and %d more", "Moving %s and %d more"), name, more)
		case to != "":             return fmt.tprintf(i18n.tr("Moving %s to %s"), name, to)
		}
		return fmt.tprintf(i18n.tr("Moving %s"), name)
	case .Trash:
		if more > 0 { return fmt.tprintf(i18n.tr(more, "Moving to the trash %s and %d more", "Moving to the trash %s and %d more"), name, more) }
		return fmt.tprintf(i18n.tr("Moving to the trash %s"), name)
	case .Delete:
		if more > 0 { return fmt.tprintf(i18n.tr(more, "Deleting %s and %d more", "Deleting %s and %d more"), name, more) }
		return fmt.tprintf(i18n.tr("Deleting %s"), name)
	case .Restore:
		if more > 0 { return fmt.tprintf(i18n.tr(more, "Putting back %s and %d more", "Putting back %s and %d more"), name, more) }
		return fmt.tprintf(i18n.tr("Putting back %s"), name)
	}
	return ""
}

jobs_view_build :: proc(app: ^App, em: f32) {
	v := &app.jobs_view
	jobs_view_follow(app)
	if !v.open { return }
	w := min(em * 44, app.room * ui.scale() * 0.9)
	list := app.jobs.list[:]
	n := len(list)
	anchor := v.anchor
	if anchor == {} { anchor = {{app.window_px.x - em, app.window_px.y - em * 2}, {app.window_px.x - em, app.window_px.y - em * 2}} }
	if ui.popover("###jobs_view", anchor, w, .Above, true) {
		ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 2.8))})
		if ui.row(.Center, id = "###jobs_head") {
			ui.spacer(ui.px(em * 0.9))
			if ui.tags("weak") { glyph(app, lucide.LAYERS_2, em * 1.6) }
			ui.next({width = ui.fill(), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###jobs_title", n == 0 ? i18n.tr("No job yet") : fmt.tprintf(i18n.tr("Jobs: %d"), n)))
			// (the jobs go on: the panel alone goes, the footer's button brings it back)
			ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 1.9))})
			if ui.button("jobs_bg", i18n.tr("Background")).clicked { v.open = false }
			ui.spacer(ui.px(em * 0.9))
		}
		ui.hline(ui.px(w))
		ui.next({width = ui.px(w), height = ui.children_sum(), axis = .Y})
		if ui.column(.Start, {}, "###jobs_rows") {
			// (the last first)
			for vi in 0 ..< min(n, JOBS_VIEW_ROWS) {
				job := list[n - 1 - vi]
				st := sync.atomic_load(&job.state)
				ui.next({width = ui.px(w), height = ui.children_sum(), axis = .Y})
				if ui.column(.Start, {.Draw_Side_Bottom}, fmt.tprintf("###job%d", job.id)) {
					ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 2.4))})
					if ui.row(.Center, id = "###line") {
						ui.spacer(ui.px(em * 0.9))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label(fmt.tprintf("%s###what", ui.text_shown(job_title(job))))
						state := ""
						switch st {
						case .Waiting:   state = i18n.tr("waiting")
						case .Counting:  state = i18n.tr("counting…")
						case .Running:   state = fmt.tprintf(i18n.tr("%d of %d%s"), sync.atomic_load(&job.files_done), sync.atomic_load(&job.files_total), job_rate_fields(job, ui.now_ms()))
						case .Asking:    state = i18n.tr("asks")
						case .Done:      state = i18n.tr("done")
						case .Failed:    state = fmt.tprintf(i18n.tr(len(job.errors), "%d failed", "%d failed"), len(job.errors))
						case .Cancelled: state = i18n.tr("a job's state", "cancelled")
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
							if ui.button("cancel", i18n.tr("Cancel")).clicked { job_cancel(job) }
						}
						if st == .Failed || st == .Cancelled {
							ui.spacer(ui.px(em * 0.4))
							ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 1.9))})
							if ui.button("retry", i18n.tr("Retry"), o = {intent = .Primary}).clicked { job_retry(app, job) }
						}
						ui.spacer(ui.px(em * 0.9))
					}
					// what failed, a line each (the first few)
					sync.mutex_lock(&job.mutex)
					for e, i in job.errors {
						if i == 3 {
							ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 1.7)), font_size = em * 0.85})
							if ui.tags("weak") { ui.label(fmt.tprintf("%s###more", fmt.tprintf(i18n.tr(len(job.errors) - 3, "    and %d more", "    and %d more"), len(job.errors) - 3))) }
							break
						}
						ui.next({width = ui.px(w), height = ui.px(ui.dense(em * 1.7)), font_size = em * 0.85, fg = ui.color("bad text")})
						ui.label(fmt.tprintf("    %s###err%d", ui.text_shown(e), i))
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
				ui.label(fmt.tprintf("%s###jobs_help", n > JOBS_VIEW_ROWS ? fmt.tprintf(i18n.tr("The last %d of %d   Esc: to the background"), JOBS_VIEW_ROWS, n) : i18n.tr("They run on in the background   Esc: hide")))
			}
		}
	}
}
