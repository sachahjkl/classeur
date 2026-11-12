package classeur

// The questions the program asks: a name already taken where a job copies or moves (replace, skip, keep both, for the
// next ones too), and the confirmation before deleting for good.

import "core:fmt"
import "core:strings"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

DIALOG_WIDTH_EM :: 30
@(private = "file") DIALOG_PAD_EM :: 0.9        // the room at the sides of every part
@(private = "file") DIALOG_ITEMS_SHOWN :: 5     // what Delete for good names, one per line; the others counted

Confirm :: struct {
	open:    bool,
	paths:   [dynamic]string,   // owned: what Delete for good deletes
	folders: [dynamic]bool,     // each one is a folder (its icon: known from the listing, no disk read)
}

confirm_free :: proc(c: ^Confirm) {
	for p in c.paths { delete(p) }
	delete(c.paths)
	delete(c.folders)
	c^ = {}
}

confirm_delete :: proc(app: ^App, paths: []string, folders: []bool) {
	c := &app.confirm
	for p in c.paths { delete(p) }
	clear(&c.paths)
	clear(&c.folders)
	for p, i in paths {
		append(&c.paths, strings.clone(p))
		append(&c.folders, i < len(folders) && folders[i])
	}
	c.open = true
}

dialogs_build :: proc(app: ^App, em: f32) {
	confirm_build(app, em)
	conflict_build(app, em)
}

// As the inspector: what it is at the top (its icon, a title, a line of details), then the files it is about, a note,
// and the buttons on a strip of their own.
@(private = "file")
confirm_build :: proc(app: ^App, em: f32) {
	c := &app.confirm
	if ui.modal("confirm_delete", em * DIALOG_WIDTH_EM, &c.open) {
		n := len(c.paths)
		if n == 0 { c.open = false; return }
		where_ := home_path(app, fs.parent(c.paths[0]))
		detail := n == 1 ? fmt.tprintf("in %s", where_) : fmt.tprintf("%d items in %s", n, where_)
		dialog_head(app, lucide.TRASH_2, ui.color("danger_button background"), "Delete for good?", detail, em)
		dialog_items(app, c, em)
		dialog_note("They do not go to the trash: this cannot be undone.", em)
		go := false
		buttons_place(em)
		if ui.row(.Center, {.Draw_Side_Top}, "###buttons") {
			ui.spacer(ui.fill())
			if ui.button("Cancel###cancel").clicked { c.open = false }
			ui.spacer(ui.px(em * 0.5))
			if ui.tags("danger_button") { go = ui.button("Delete###delete").clicked }
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
		}
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
		name := fs.base(job.ask_name)
		dialog_head(app, lucide.ALERT_CIRCLE, ui.color("accent"), fmt.tprintf("%s is already there", name),
			fmt.tprintf("in %s", home_path(app, fs.parent(job.ask_name))), em)
		ui.spacer(ui.px(em * 0.6))
		dialog_note("Replace it with the one you copy, keep both (the new one numbered), or skip it.", em)
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
		if ui.row(.Center, id = "###all_row") {
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
			ui.checkbox("###all", "Do the same for the next ones", &v.all)
		}
		ui.spacer(ui.px(em * 0.5))
		buttons_place(em)
		if ui.row(.Center, {.Draw_Side_Top}, "###buttons") {
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
			if ui.button("Cancel the job###cancel").clicked { job_cancel(job); v.open = false }
			ui.spacer(ui.fill())
			if ui.button("Skip###skip").clicked { answer = .Skip }
			ui.spacer(ui.px(em * 0.5))
			if ui.button("Keep both###both").clicked { answer = .Keep_Both }
			ui.spacer(ui.px(em * 0.5))
			if ui.tags("accent_button") { if ui.button("Replace###replace").clicked { answer = .Replace } }
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
		}
	}
	// (Escape closes it: the file is skipped)
	if !v.open && answer == .Ask && !job.cancel { answer = .Skip }
	if answer != .Ask {
		job_answer(job, answer, v.all)
		v.open = false
	}
}

// The top, as the inspector's: the icon, the title, a weak line under it; a line below.
@(private = "file")
dialog_head :: proc(app: ^App, icon: string, tint: ui.Color, title, detail: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.6))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###dlg_head") {
		ui.spacer(ui.px(em * DIALOG_PAD_EM))
		glyph(app, icon, em * 1.7, tint)
		ui.spacer(ui.px(em * 0.7))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.5), font_size = em * 1.05})
			ui.label(fmt.tprintf("%s###dlg_title", shown_text(title)))
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 1.3), font_size = em * 0.86})
				ui.label(fmt.tprintf("%s###dlg_detail", shown_text(detail)))
			}
			ui.spacer(ui.fill())
		}
		ui.spacer(ui.px(em * DIALOG_PAD_EM))
	}
}

// What Delete for good takes: a line each (its icon and name, as the inspector lists a folder), the others counted.
@(private = "file")
dialog_items :: proc(app: ^App, c: ^Confirm, em: f32) {
	ui.spacer(ui.px(em * 0.4))
	for p, i in c.paths {
		if i == DIALOG_ITEMS_SHOWN { break }
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.9))})
		if ui.row(.Center, {}, fmt.tprintf("###dlg_item%d", i)) {
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
			path_icon(app, p, c.folders[i], em * 1.6)
			ui.spacer(ui.px(em * 0.4))
			ui.next({width = ui.fill(), height = ui.pct(1)})
			ui.label(fmt.tprintf("%s###n", shown_text(fs.base(p))))
			ui.spacer(ui.px(em * DIALOG_PAD_EM))
		}
	}
	if more := len(c.paths) - DIALOG_ITEMS_SHOWN; more > 0 {
		if ui.tags("weak") {
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.7))})
			if ui.row(.Center, {}, "###dlg_more") {
				ui.spacer(ui.px(em * (DIALOG_PAD_EM + 2.0)))
				ui.label(fmt.tprintf("and %d more###t", more))
			}
		}
	}
	ui.spacer(ui.px(em * 0.4))
}

// A weak note, folded in the dialog's width (a width of its own: the paragraph knows where to fold before the layout).
@(private = "file")
dialog_note :: proc(text: string, em: f32) {
	ui.next({width = ui.fill()})
	if ui.row(id = "###dlg_note_row") {
		ui.spacer(ui.px(em * DIALOG_PAD_EM))
		if ui.tags("weak") {
			ui.next({width = ui.px(em * (DIALOG_WIDTH_EM - 2 * DIALOG_PAD_EM)), font_size = em * 0.92})
			ui.paragraph(fmt.tprintf("%s###dlg_note", text))
		}
	}
	ui.spacer(ui.px(em * 0.8))
}

// The strip of the buttons: its size (the next `ui.row(.Center, {.Draw_Side_Top}, "###buttons")` is it, a line above it).
@(private = "file")
buttons_place :: proc(em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.0))})
}
