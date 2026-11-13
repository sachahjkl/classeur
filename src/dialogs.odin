package classeur

// The questions the program asks: a name already taken where a job copies or moves (replace, skip, keep both, for the
// next ones too), the confirmation before deleting for good (some items, or the trash emptied), and the report of a
// last session that did not end cleanly.

import "core:fmt"
import "core:strings"
import "core:sync"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

CONFLICT_WIDTH_EM :: 38   // its four choices on one line

Confirm :: struct {
	open:  bool,
	paths: [dynamic]string,   // owned: what Delete for good deletes
	names: [dynamic]string,   // owned: each one as the question names it
	trash: bool,              // they are every item of the trash: emptied
	records: bool,            // they are items of the trash: each one's record goes with it
}

confirm_free :: proc(c: ^Confirm) {
	for p in c.paths { delete(p) }
	delete(c.paths)
	for n in c.names { delete(n) }
	delete(c.names)
	c^ = {}
}

// `names`: what the question lists, one per path (nil: each path's last part; an item of the Recycle Bin of Windows
// is named by its original name, not by its $R file's).
confirm_delete :: proc(app: ^App, paths: []string, trash := false, names: []string = nil, records := false) {
	c := &app.confirm
	for p in c.paths { delete(p) }
	clear(&c.paths)
	for n in c.names { delete(n) }
	clear(&c.names)
	for p, i in paths {
		append(&c.paths, strings.clone(p))
		append(&c.names, strings.clone(names != nil && i < len(names) ? names[i] : fs.base(p)))
	}
	c.open, c.trash, c.records = true, trash, trash || records
}

confirm_empty_trash :: proc(app: ^App, paths: []string, names: []string = nil) { confirm_delete(app, paths, trash = true, names = names) }

dialogs_build :: proc(app: ^App, em: f32) {
	confirm_build(app, em)
	conflict_build(app, em)
	crash_build(app, em)
}

// The last session crashed or was killed (gt:crash): its report is offered at this start, to open or to copy where it
// is. Nothing is sent anywhere.
crash_offer :: proc(app: ^App, report: string) {
	delete(app.crash_report)
	app.crash_report = strings.clone(report)
	app.crash_asking = true
}

CRASH_WIDTH_EM :: 34

@(private = "file")
crash_build :: proc(app: ^App, em: f32) {
	if !app.crash_asking { return }
	if ui.modal("crash_report", em * CRASH_WIDTH_EM, &app.crash_asking) {
		if ui.dialog_header("crash_title", "classeur stopped unexpectedly", {icon = lucide.BUG, icon_font = app.icons, close = true}) {}
		if ui.dialog_body("crash_body") {
			ui.next({width = ui.fill()})
			ui.paragraph("Its last session ended without closing. What happened is written in a report on this computer; nothing was sent anywhere.###crash_note")
			ui.spacer(ui.px(em * 0.6))
			if ui.tags("weak") {
				ui.next({width = ui.fill(), font = app.mono})
				ui.paragraph(fmt.tprintf("%s###crash_path", ui.text_shown(app.crash_report)))
			}
		}
		if ui.dialog_buttons("crash_buttons") {
			if ui.button_icon("crash_copy", lucide.COPY, "Copy its path", icon_font = app.icons).clicked {
				ui.window_clipboard_set(app.crash_report)
				announce(app, .Good, "The report's path is copied.")
			}
			ui.spacer(ui.px(em * 0.6))
			if ui.button_icon("crash_open", lucide.FILE_TEXT, "Open the report (Enter)", icon_font = app.icons, intent = .Primary).clicked || ui.key_press(.Return) {
				ui.open(app.crash_report)
				app.crash_asking = false
			}
		}
	}
}

// The toolkit's question (ui.confirm): what is deleted named, Enter cancels.
@(private = "file")
confirm_build :: proc(app: ^App, em: f32) {
	c := &app.confirm
	if !c.open || len(c.paths) == 0 { c.open = false; return }
	n := len(c.paths)
	names := c.names[:]
	title := n == 1 ? fmt.tprintf("Delete %s for good?", names[0]) : fmt.tprintf("Delete %d items for good?", n)
	note := n == 1 ? "It does not go to the trash: this cannot be undone." : "They do not go to the trash: this cannot be undone."
	act := "Delete"
	if c.trash {
		title, act = "Empty the trash?", "Empty the trash"
		note = n == 1 ? "Its item is deleted for good: this cannot be undone." : fmt.tprintf("Its %d items are deleted for good: this cannot be undone.", n)
	}
	if ui.confirm("confirm_delete", &c.open, {title = title, note = note, lines = names, act = act}) == .Confirmed {
		job_add(app, .Delete, c.paths[:])
		// (then their records, by a job after it: the jobs run one after the other; a record's path is made from the
		// item's, with no disk read)
		if c.records {
			records := make([dynamic]string, context.temp_allocator)
			for p in c.paths { if r := fs.trash_record(p); r != "" { append(&records, r) } }
			if len(records) > 0 { job_add(app, .Delete, records[:]) }
		}
	}
}

// The question of a name taken, as shown.
Conflict_View :: struct {
	open: bool,
	all:  bool,
	job:  u64,
}

// The toolkit's three parts of a dialog: the question in the header, the two files and a weak note in the body, then
// its choices (Enter: Keep both, which loses nothing).
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
	if ui.modal("conflict", em * CONFLICT_WIDTH_EM, &v.open) {
		title := fmt.tprintf("%s is already in %s", ui.text_shown(fs.base(job.ask_name)), ui.text_shown(fs.base(fs.parent(job.ask_name))))
		if ui.dialog_header("title", title, {icon = lucide.FILES, icon_font = app.icons, close = true}) {}
		if ui.dialog_body("body") {
			// (the two files side by side, as the job read them: which to keep is seen before it is chosen)
			sync.mutex_lock(&job.mutex)
			there, coming := job.ask_there, job.ask_coming
			sync.mutex_unlock(&job.mutex)
			conflict_file_line(app, "There", there, coming, em, "###there")
			conflict_file_line(app, job.kind == .Move ? "Moved" : job.kind == .Restore ? "Put back" : "Copied", coming, there, em, "###coming")
			ui.spacer(ui.px(em * 0.4))
			if ui.tags("weak") {
				ui.next({width = ui.fill()})
				ui.paragraph("Replace it, keep both (the new one numbered), or skip it.###text")
			}
			ui.spacer(ui.px(em * 0.6))
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
			if ui.row(.Center) { ui.checkbox("###all", "Do the same for the next ones", &v.all) }
		}
		if ui.dialog_buttons("buttons") {
			bw :: proc(em: f32) { ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))}) }
			bw(em)
			if ui.button("Cancel the job###cancel", intent = .Cancel).clicked { job_cancel(job); v.open = false }
			ui.spacer(ui.px(em * 0.6))
			bw(em)
			if ui.button("Skip###skip").clicked { answer = .Skip }
			ui.spacer(ui.px(em * 0.6))
			bw(em)
			if ui.button("Keep both (Enter)###both", intent = .Primary).clicked || ui.key_press(.Return) { answer = .Keep_Both }
			ui.spacer(ui.px(em * 0.6))
			bw(em)
			if ui.button("Replace###replace", intent = .Danger).clicked { answer = .Replace }
		}
	}
	// (Escape closes it: the file is skipped)
	if !v.open && answer == .Ask && !job.cancel { answer = .Skip }
	if answer != .Ask {
		job_answer(job, answer, v.all)
		v.open = false
	}
}

// A line of the name-taken question: "There: 12 KB · 2026-11-10 14:02", then "· newer" in the accent's colour when it is
// the newer of the two.
@(private = "file")
conflict_file_line :: proc(app: ^App, word: string, f, other: fs.Info, em: f32, id: string) {
	what := f.kind == .Directory ? "Folder" : size_text(f.size)
	text := what
	if date := date_text(app, f.mtime); date != "" { text = fmt.tprintf("%s · %s", what, date) }
	ui.next({width = ui.fill(), height = ui.px(em * 1.5)})
	if ui.row(.Center, id = id) {
		ui.next({width = ui.text_size(0, 0), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s: %s###file", word, text))
		if other.mtime != 0 && f.mtime > other.mtime {
			ui.spacer(ui.px(em * 0.3))
			ui.next({width = ui.text_size(0, 0), height = ui.pct(1), fg = ui.color("accent")})
			ui.label("· newer###newer")
		}
	}
}
