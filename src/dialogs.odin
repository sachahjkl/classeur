package classeur

// The questions the program asks: a name already taken where a job copies or moves (replace, skip, keep both, for the
// next ones too), and the confirmation before deleting for good.

import "core:fmt"
import "core:strings"
import "gt:ui"
import "fs"

CONFLICT_WIDTH_EM :: 38   // its four choices on one line

Confirm :: struct {
	open:  bool,
	paths: [dynamic]string,   // owned: what Delete for good deletes
}

confirm_free :: proc(c: ^Confirm) {
	for p in c.paths { delete(p) }
	delete(c.paths)
	c^ = {}
}

confirm_delete :: proc(app: ^App, paths: []string) {
	c := &app.confirm
	for p in c.paths { delete(p) }
	clear(&c.paths)
	for p in paths { append(&c.paths, strings.clone(p)) }
	c.open = true
}

dialogs_build :: proc(app: ^App, em: f32) {
	confirm_build(app, em)
	conflict_build(app, em)
}

// The toolkit's question (ui.confirm): what is deleted named, Enter cancels.
@(private = "file")
confirm_build :: proc(app: ^App, em: f32) {
	c := &app.confirm
	if !c.open || len(c.paths) == 0 { c.open = false; return }
	n := len(c.paths)
	names := make([]string, n, context.temp_allocator)
	for p, i in c.paths { names[i] = fs.base(p) }
	title := n == 1 ? fmt.tprintf("Delete %s for good?", names[0]) : fmt.tprintf("Delete %d items for good?", n)
	note := n == 1 ? "It does not go to the trash: this cannot be undone." : "They do not go to the trash: this cannot be undone."
	if ui.confirm("confirm_delete", &c.open, {title = title, note = note, lines = names, act = "Delete"}) == .Confirmed {
		job_add(app, .Delete, c.paths[:])
	}
}

// The question of a name taken, as shown.
Conflict_View :: struct {
	open: bool,
	all:  bool,
	job:  u64,
}

// Laid out as ui.confirm: the question, a weak note, then its choices (Enter: Keep both, which loses nothing).
@(private = "file")
conflict_build :: proc(app: ^App, em: f32) {
	job := job_asking(app)
	v := &app.conflict
	if job == nil {
		v.open = false
		return
	}
	if v.job != job.id || !v.open {
		v.job, v.open, v.all = job.id, true, false
	}
	answer := Conflict.Ask
	w := em * CONFLICT_WIDTH_EM
	if ui.modal("conflict", w, &v.open) {
		pad := em * 1.2
		ui.spacer(ui.px(pad))
		ui.next({width = ui.px(w), height = ui.children_sum()})
		if ui.row() {
			ui.spacer(ui.px(pad))
			ui.next({width = ui.px(w - 2 * pad), height = ui.children_sum(), axis = .Y})
			if ui.column() {
				ui.next({width = ui.fill(), font_size = em * 1.15})
				ui.paragraph(fmt.tprintf("%s is already in %s###title", shown_text(fs.base(job.ask_name)), shown_text(fs.base(fs.parent(job.ask_name)))))
				ui.spacer(ui.px(em * 0.4))
				if ui.tags("weak") {
					ui.next({width = ui.fill()})
					ui.paragraph("Replace it, keep both (the new one numbered), or skip it.###text")
				}
				ui.spacer(ui.px(em * 0.6))
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
				if ui.row(.Center) { ui.checkbox("###all", "Do the same for the next ones", &v.all) }
				ui.spacer(ui.px(em * 1.1))
				ui.next({width = ui.fill(), height = ui.children_sum()})
				if ui.row(id = "###buttons") {
					bw :: proc(em: f32) { ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))}) }
					bw(em)
					if ui.button("Cancel the job###cancel").clicked { job_cancel(job); v.open = false }
					ui.spacer(ui.fill())
					bw(em)
					if ui.button("Skip###skip").clicked { answer = .Skip }
					ui.spacer(ui.px(em * 0.6))
					bw(em)
					if ui.button("Keep both (Enter)###both").clicked || ui.key_press(.Return) { answer = .Keep_Both }
					ui.spacer(ui.px(em * 0.6))
					bw(em)
					if ui.tags("danger_button") { if ui.button("Replace###replace").clicked { answer = .Replace } }
				}
			}
		}
		ui.spacer(ui.px(pad))
	}
	// (Escape closes it: the file is skipped)
	if !v.open && answer == .Ask && !job.cancel { answer = .Skip }
	if answer != .Ask {
		job_answer(job, answer, v.all)
		v.open = false
	}
}
