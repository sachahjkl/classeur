package classeur

// The questions the program asks: a name already taken where a job copies or moves (replace, skip, keep both, for the
// next ones too), and the confirmation before deleting for good.

import "core:fmt"
import "core:strings"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

DIALOG_WIDTH_EM :: 30

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

@(private = "file")
confirm_build :: proc(app: ^App, em: f32) {
	c := &app.confirm
	if ui.modal("confirm_delete", em * DIALOG_WIDTH_EM, &c.open) {
		dialog_body(app, lucide.TRASH_2, em)
		n := len(c.paths)
		title := n == 1 ? fmt.tprintf("Delete %s for good?", fs.base(c.paths[0])) : fmt.tprintf("Delete %d items for good?", n)
		dialog_text(title, "They do not go to the trash: this cannot be undone.", em)
		go := false
		buttons_place(em)
		if ui.row(.Center, id = "###buttons") {
			ui.spacer(ui.fill())
			if ui.button("Cancel###cancel").clicked { c.open = false }
			ui.spacer(ui.px(em * 0.5))
			if ui.tags("danger_button") { go = ui.button("Delete###delete").clicked }
			ui.spacer(ui.px(em * 1.2))
		}
		dialog_end(em)
		if go {
			job_add(app, .Delete, c.paths[:])
			c.open = false
		}
	}
}

// The question of a name taken, as shown.
Conflict_View :: struct {
	open: bool,
	all:  bool,
	job:  u64,
}

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
	if ui.modal("conflict", em * DIALOG_WIDTH_EM, &v.open) {
		dialog_body(app, lucide.ALERT_CIRCLE, em)
		dialog_text(fmt.tprintf("%s is already in %s.", fs.base(job.ask_name), fs.base(fs.parent(job.ask_name))),
			"Replace it with the one you copy, keep both (the new one numbered), or skip it.", em)
		ui.next({width = ui.fill()})
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 1.2))
			ui.checkbox("###all", "Do the same for the next ones", &v.all)
		}
		buttons_place(em)
		if ui.row(.Center, id = "###buttons") {
			ui.spacer(ui.px(em * 1.2))
			if ui.button("Cancel the job###cancel").clicked { job_cancel(job); v.open = false }
			ui.spacer(ui.fill())
			if ui.button("Skip###skip").clicked { answer = .Skip }
			ui.spacer(ui.px(em * 0.5))
			if ui.button("Keep both###both").clicked { answer = .Keep_Both }
			ui.spacer(ui.px(em * 0.5))
			if ui.tags("accent_button") { if ui.button("Replace###replace").clicked { answer = .Replace } }
			ui.spacer(ui.px(em * 1.2))
		}
		dialog_end(em)
	}
	// (Escape closes it: the file is skipped)
	if !v.open && answer == .Ask && !job.cancel { answer = .Skip }
	if answer != .Ask {
		job_answer(job, answer, v.all)
		v.open = false
	}
}

@(private = "file")
dialog_body :: proc(app: ^App, icon: string, em: f32) {
	ui.spacer(ui.px(em * 1.0))
	ui.next({width = ui.fill(), height = ui.px(em * 2.4)})
	if ui.row(.Center) {
		ui.spacer(ui.px(em * 1.2))
		glyph(app, icon, em * 2.2, ui.color("accent"))
	}
}

@(private = "file")
dialog_text :: proc(title, text: string, em: f32) {
	ui.next({width = ui.fill()})
	if ui.row() {
		ui.spacer(ui.px(em * 1.2))
		ui.next({width = ui.fill()})
		if ui.column() {
			if ui.style({font_size = em * 1.1}) {
				ui.next({width = ui.fill()})
				ui.paragraph(fmt.tprintf("%s###title", shown_text(title)))
			}
			ui.spacer(ui.px(em * 0.4))
			if ui.tags("weak") {
				ui.next({width = ui.fill()})
				ui.paragraph(fmt.tprintf("%s###text", text))
			}
		}
		ui.spacer(ui.px(em * 1.2))
	}
	ui.spacer(ui.px(em * 0.8))
}

// The row of the buttons: its height and the room above it (the next `ui.row` is it).
@(private = "file")
buttons_place :: proc(em: f32) {
	ui.spacer(ui.px(em * 0.4))
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2))})
}

@(private = "file")
dialog_end :: proc(em: f32) {
	ui.spacer(ui.px(em * 1.0))
}
