package classeur

// The questions the program asks: a name already taken where a job copies or moves (replace, skip, keep both, for the
// next ones too), the confirmation before deleting for good (some items, or the trash emptied), and the report of a
// last session that did not end cleanly.

import "core:fmt"
import "core:strings"
import "core:sync"
import "gt:i18n"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:render"
import "gt:timefmt"
import "gt:ui"
import "fs"

CONFLICT_WIDTH_EM :: 38   // its four choices on one line

Confirm :: struct {
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
	c.trash, c.records = trash, trash || records
	n := len(c.paths)
	if n == 0 { return }
	// the toolkit's question: what is deleted named, Enter cancels
	shown := c.names[:]
	title := n == 1 ? fmt.tprintf(i18n.tr("Delete %s for good?"), shown[0]) : fmt.tprintf(i18n.tr(n, "Delete %d item for good?", "Delete %d items for good?"), n)
	note := n == 1 ? i18n.tr("It does not go to the trash: this cannot be undone.") : i18n.tr("They do not go to the trash: this cannot be undone.")
	act := i18n.tr("Delete")
	if c.trash {
		title, act = i18n.tr("Empty the trash?"), i18n.tr("Empty the trash")
		note = n == 1 ? i18n.tr("Its item is deleted for good: this cannot be undone.") : fmt.tprintf(i18n.tr(n, "Its %d item is deleted for good: this cannot be undone.", "Its %d items are deleted for good: this cannot be undone."), n)
	}
	ui.confirm_open(CONFIRM_DELETE_VIEW, {title = title, note = note, lines = shown, act = act})
}

confirm_empty_trash :: proc(app: ^App, paths: []string, names: []string = nil) { confirm_delete(app, paths, trash = true, names = names) }

// Each frame: the questions' answers, and the question of a name taken opened or closed as a job asks it.
dialogs_build :: proc(app: ^App) {
	confirm_follow(app)
	conflict_follow(app)
	about_build(app)
}

@(private = "file")
about_diagnostics :: proc(app: ^App) -> string {
	b := strings.builder_make(context.temp_allocator)
	ai := render.adapter_info(&app.shared.r)
	if ai.name != "" || ai.api != "" {
		fmt.sbprintf(&b, "Renderer: %s (%s)%s", ai.name, ai.api, ai.software ? ", software" : "")
	}
	if app.settings.theme != "" {
		if strings.builder_len(b) > 0 { strings.write_byte(&b, '\n') }
		fmt.sbprintf(&b, "Theme: %s", app.settings.theme)
	}
	return strings.to_string(b)
}

// About Classeur: toolkit's generic modal with drawn logo, built-in "What's new" jumping to Settings, links via launch,
// and non-blocking diagnostics.
@(private = "file")
about_build :: proc(app: ^App) {
	if !app.about_open { return }
	ui.about_modal("classeur_about", &app.about_open, {
		name         = APP_TITLE,
		version      = APP_VERSION,
		licence      = "MIT",
		copyright    = "© 2026 Froment Software",
		logo_draw    = logo_draw,
		logo_user    = logo_draw_data(),
		on_whats_new = proc(user: rawptr) { options_show((^App)(user), prefs_page.CHANGELOG_PAGE) },
		website_url  = SITE_URL,
		releases_url = REPOSITORY_URL + "/releases",
		diagnostics  = about_diagnostics(app),
		on_link      = proc(url: string, user: rawptr) { launch((^App)(user), .Open, url) },
		user         = app,
	})
}

// The answer of the question before deleting for good.
@(private = "file")
confirm_follow :: proc(app: ^App) {
	c := &app.confirm
	if ui.confirm_answer(CONFIRM_DELETE_VIEW) == .Confirmed && len(c.paths) > 0 {
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

// The question of a name taken, as shown: the job it is of.
Conflict_View :: struct {
	all:  bool,
	job:  u64,
}

conflict_register :: proc(app: ^App) {
	ui.view_register(&app.views, CONFLICT_VIEW, conflict_view, ui.View_Options{title = i18n.later("A name is taken"), icon = lucide.FILES, icon_font = app.icons, width_em = CONFLICT_WIDTH_EM})
}

// The view is open while a job asks (the program opens and closes it, whatever the person does). Closed by the person
// (Escape, its close cross): the file is skipped.
@(private = "file")
conflict_follow :: proc(app: ^App) {
	vs := &app.views
	v := &app.conflict
	job := job_asking(app)
	if code, ok := ui.view_ended(vs, CONFLICT_VIEW); ok {
		if code == ui.VIEW_CANCELLED && job != nil && job.id == v.job && !job.cancel { job_answer(job, .Skip, v.all) }
		return   // (asked again from the next frame, once the job has taken the answer)
	}
	if job == nil {
		ui.view_close(vs, CONFLICT_VIEW)
		return
	}
	if v.job != job.id { v.job, v.all = job.id, false }
	if !ui.view_is_open(vs, CONFLICT_VIEW) { ui.view_open(vs, CONFLICT_VIEW, app) }
}

// The question in the header, the two files and a weak note in the body, then its choices (Enter: Keep both, which
// loses nothing). The answer goes to the job at once.
@(private = "file")
conflict_view :: proc(view: ^ui.View, app: ^App) {
	v := &app.conflict
	job := job_asking(app)
	if job == nil || job.id != v.job { return }
	em := ui.font_size()
	answer := Conflict.Ask
	ui.view_title(view, fmt.tprintf(i18n.tr("%s is already in %s"), ui.text_shown(fs.base(job.ask_name)), ui.text_shown(fs.base(fs.parent(job.ask_name)))))
	if ui.dialog_body("body") {
		// (the two files side by side, as the job read them: which to keep is seen before it is chosen)
		sync.mutex_lock(&job.mutex)
		there, coming := job.ask_there, job.ask_coming
		sync.mutex_unlock(&job.mutex)
		conflict_file_line(app, i18n.tr("There"), there, coming, em, "###there")
		conflict_file_line(app, job.kind == .Move ? i18n.tr("Moved") : job.kind == .Restore ? i18n.tr("the file coming, put back from the trash", "Put back") : i18n.tr("Copied"), coming, there, em, "###coming")
		ui.space(ui.LINE_GAP)
		if ui.tags("weak") {
			ui.next({width = ui.fill()})
			ui.paragraph(fmt.tprintf("%s###text", i18n.tr("Replace it, keep both (the new one numbered), or skip it.")))
		}
		ui.space(ui.LINE_GAP)
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
		if ui.row(.Center) { ui.checkbox("###all", i18n.tr("Do the same for the next ones"), &v.all) }
	}
	cancel := false
	if ui.dialog_buttons("buttons") {
		bw :: proc(em: f32) { ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))}) }
		bw(em)
		if ui.button("cancel", i18n.tr("Cancel the job")).clicked { cancel = true }
		bw(em)
		if ui.button("skip", i18n.tr("Skip")).clicked { answer = .Skip }
		bw(em)
		if ui.button("both", i18n.tr("Keep both (Enter)"), o = {intent = .Primary}).clicked || ui.key_press(.Return) { answer = .Keep_Both }
		bw(em)
		if ui.button("replace", i18n.tr("Replace"), o = {intent = .Danger}).clicked { answer = .Replace }
	}
	// (the job cancelled: its question ends with it; Conflict.Ask is the answer's code)
	if cancel {
		job_cancel(job)
		ui.view_end(view, int(Conflict.Ask))
	} else if answer != .Ask {
		job_answer(job, answer, v.all)
		ui.view_end(view, int(answer))
	}
}

// A line of the name-taken question: "There: 12 KB · 2026-11-10 14:02", then "· newer" in the accent's colour when it is
// the newer of the two.
@(private = "file")
conflict_file_line :: proc(app: ^App, word: string, f, other: fs.Info, em: f32, id: string) {
	what := f.kind == .Directory ? i18n.tr("Folder") : timefmt.size(f.size)
	text := what
	if date := date_text(app, f.mtime); date != "" { text = fmt.tprintf("%s · %s", what, date) }
	ui.next({width = ui.fill(), height = ui.px(em * 1.5)})
	if ui.row(.Center, id = id) {
		ui.next({width = ui.text_size(0, 0), height = ui.pct(1), flags = {.Selectable}})   // (content: its size and date)
		ui.label(fmt.tprintf("%s: %s###file", word, text))
		if other.mtime != 0 && f.mtime > other.mtime {
			ui.space(ui.SPACE_1)
			ui.next({width = ui.text_size(0, 0), height = ui.pct(1), fg = ui.color("accent")})
			ui.label(fmt.tprintf("%s###newer", i18n.tr("· newer")))
		}
	}
}
