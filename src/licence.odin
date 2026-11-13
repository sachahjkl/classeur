package classeur

// classeur's licence (gui_toolkit's gt:licence, docs/licence.md): a key signed by the shop, checked here with no
// network. A licence changes nothing of what classeur does: it says who supports it. The settings' General page shows
// it (licence_section): who it is registered to, or how to get one, a key to paste or a file to choose, and Remove.
// Every read and write of its file is a task (the store blocks on the disk).

import "base:runtime"
import "core:fmt"
import "core:strings"
import "gt:i18n"
import licence "gt:licence"
import lucide "gt:lucide"
import "gt:platform"
import "gt:ui"
import classeur_licence "licence"

// classeur's licence: src/licence/product.odin (the tool's too).
LICENCE :: classeur_licence.PRODUCT

// Where a licence is bought: the site's pricing page.
LICENCE_PRICING_URL :: SITE_URL + "pricing/"

// The licence as the interface knows it: the store's last status, what is asked of it, what came of it.
Licence_View :: struct {
	store:  ^licence.Store,
	status: licence.Status,   // the last one read (heap: its licence's strings)
	known:  bool,             // a status was read
	busy:   bool,             // a task on the store is on its way
	key:    ui.Text_Field,    // the key pasted
	said:   string,           // owned: what the last act came to ("": nothing)
}

licence_open :: proc(app: ^App) {
	v := &app.licence
	v.store = new(licence.Store)
	// (the tests keep it in memory: the person's folder is never touched)
	licence.store_init(v.store, {product = LICENCE, program = APP_NAME, memory = app.headless, accept_dev = ODIN_DEBUG})
	licence_ask(app, .Read, "")
}

licence_close :: proc(app: ^App) {
	v := &app.licence
	// (a task on its way still uses the store: it is left to the process's end)
	if v.store != nil && !v.busy {
		licence.store_destroy(v.store)
		free(v.store)
	}
	licence.status_destroy(&v.status, runtime.heap_allocator())
	ui.field_wipe(&v.key)
	ui.field_destroy(&v.key)
	delete(v.said)
	v^ = {}
}

@(private = "file")
Licence_Act :: enum u8 { Read, Install, Install_File, Remove }

@(private = "file")
Licence_Job :: struct {
	app:    ^App,      // (read by `done` alone: the App may be gone while the work runs)
	store:  ^licence.Store,
	act:    Licence_Act,
	text:   string,   // the key or the file (heap)
	err:    licence.Error,
	status: licence.Status,   // read after the act (heap)
}

// An act on the store, then its status read again: both in a task; the answer comes at a next build.
@(private = "file")
licence_ask :: proc(app: ^App, act: Licence_Act, text: string) {
	a := runtime.heap_allocator()
	j := new(Licence_Job, a)
	j^ = {app = app, store = app.licence.store, act = act, text = strings.clone(text, a)}
	app.licence.busy = true
	work :: proc(d: rawptr) {
		j := (^Licence_Job)(d)
		s := j.store
		switch j.act {
		case .Read:
		case .Install:      j.err = licence.store_install(s, j.text)
		case .Install_File: j.err = licence.store_install_file(s, j.text)
		case .Remove:       if !licence.store_remove(s) { j.err = .Not_Written }
		}
		j.status = licence.store_read(s, runtime.heap_allocator())
	}
	done :: proc(d: rawptr, _: u64) {
		j := (^Licence_Job)(d)
		defer licence_job_free(j)
		app := j.app
		v := &app.licence
		v.busy = false
		licence.status_destroy(&v.status, runtime.heap_allocator())
		v.status, j.status = j.status, {}
		v.known = true
		said := ""
		switch {
		case j.err != .None:  said = licence_error_words(j.err)
		case j.act == .Remove: said = i18n.tr("The licence is removed.")
		case j.act != .Read && v.status.registered:
			said = fmt.tprintf(i18n.tr("Registered to %s. Thank you."), ui.text_shown(v.status.licence.name))
			ui.field_wipe(&v.key)
		}
		delete(v.said)
		v.said = strings.clone(said)
		app_frames(app)
	}
	lost :: proc(d: rawptr) { licence_job_free((^Licence_Job)(d)) }
	ui.task(&app.main.state, work, done, j, lost)
}

@(private = "file")
licence_job_free :: proc(j: ^Licence_Job) {
	a := runtime.heap_allocator()
	licence.status_destroy(&j.status, a)
	// (a key is a secret of the person's: nothing of it stays in memory)
	if j.act == .Install { runtime.mem_zero(raw_data(j.text), len(j.text)) }
	delete(j.text, a)
	free(j, a)
}

// classeur's words for what went wrong.
@(private = "file")
licence_error_words :: proc(e: licence.Error) -> string {
	#partial switch e {
	case .Empty:         return i18n.tr("Paste a key first.")
	case .Wrong_Product: return i18n.tr("This licence is not classeur's.")
	case .Bad_Signature: return i18n.tr("This key is not one the shop signed: check that it was copied whole.")
	case .No_Public_Key: return i18n.tr("This version of classeur accepts no licence yet.")
	case .Not_Read:      return i18n.tr("The licence file cannot be read.")
	case .Not_Written:   return i18n.tr("The licence cannot be written in classeur's folder.")
	}
	return licence.error_text(e)
}

// The Licence section at the foot of the settings' General page.
licence_section :: proc(app: ^App, em: f32) {
	v := &app.licence
	st := &v.status
	ui.spacer(ui.px(em * 1.2))
	ui.next({width = ui.fill(), text_pad = 0})
	ui.label(fmt.tprintf("%s###lic_title", i18n.tr("Licence")))
	ui.hline(ui.fill())
	ui.spacer(ui.px(em * 0.5))
	switch {
	case !v.known:
		if ui.tags("weak") {
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s###lic_reading", i18n.tr("Reading the licence…")))
		}
	case st.registered:
		ui.next({width = ui.fill(), text_pad = 0})
		edition := licence.edition_title(LICENCE, st.licence.edition)
		ui.paragraph(fmt.tprintf("%s###lic_who", fmt.tprintf(i18n.tr("Registered to %s (%s). Thank you for supporting classeur."), ui.text_shown(st.licence.name), edition)))
		if ui.tags("weak") {
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s###lic_order", fmt.tprintf(i18n.tr("Order %s, %s."), ui.text_shown(st.licence.order), ui.text_shown(st.licence.date))))
		}
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.children_sum(), height = ui.px(ui.dense(em * 2.2))})
		if ui.row(.Center, {}, "###lic_registered") {
			ui.next({width = ui.text_size(em * 1.2), height = ui.fill()})
			if ui.button(fmt.tprintf("%s###lic_remove", i18n.tr("Remove the licence")), intent = .Danger, disabled = v.busy).clicked { licence_ask(app, .Remove, "") }
		}
	case:
		ui.next({width = ui.fill(), text_pad = 0})
		ui.paragraph(fmt.tprintf("%s###lic_none", i18n.tr("Unregistered. classeur is free; a licence supports its work.")))
		ui.next({width = ui.children_sum(), height = ui.px(ui.dense(em * 2.0))})
		if ui.row(.Center, {}, "###lic_buy_row") {
			if ui.hint_action("###lic_buy", i18n.tr("Support classeur: buy a licence"), lucide.HEART, app.icons, .Primary).clicked {
				ui.open(LICENCE_PRICING_URL, .Url)
			}
		}
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2))})
		if ui.row(.Center, {}, "###lic_enter") {
			ui.next({width = ui.fill(), height = ui.fill()})
			entered := ui.line_edit("###lic_key", &v.key, i18n.tr("Paste the key of your licence"), secret = true).committed
			ui.spacer(ui.px(em * 0.5))
			ui.next({width = ui.text_size(em * 1.2), height = ui.fill()})
			key := strings.trim_space(ui.field_string(&v.key))
			if ui.button(fmt.tprintf("%s###lic_register", i18n.tr("Register")), intent = .Primary, disabled = v.busy || key == "").clicked || (entered && key != "") {
				licence_ask(app, .Install, key)
			}
			ui.spacer(ui.px(em * 0.5))
			ui.next({width = ui.text_size(em * 1.2), height = ui.fill()})
			if ui.button(fmt.tprintf("%s###lic_file", i18n.tr("Choose a file…")), disabled = v.busy).clicked {
				d := licence.file_dialog(LICENCE, i18n.tr("Choose a licence file"), i18n.tr("classeur licence"))
				ui.file_dialog(&app.main.state, .Open, d, proc(r: platform.Dialog_Result, user: rawptr) {
					if r.status != .Chosen || len(r.paths) == 0 { return }
					licence_ask((^App)(user), .Install_File, r.paths[0])   // (copied: the result is freed after this call)
				}, app)
			}
		}
	}
	if v.said != "" {
		ui.spacer(ui.px(em * 0.4))
		if ui.tags("weak") {
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s###lic_said", v.said))
		}
	}
}
