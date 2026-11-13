package classeur

// classeur on the user's desktop (gui_toolkit's desktop and setup): a launcher in the application menu with its icons,
// classeur on the PATH, "Open folders with classeur" in the menus that offer it. Everything in the user's profile.
//
//   classeur install [--no-path]   the running copy integrated where it is (a build, a Nix profile's)
//   classeur uninstall             the integration taken away
//   classeur status                what is installed
//   classeur --setup               the Setup: the copy installed in a folder of its own, repaired, upgraded, uninstalled
//
// On Windows a copy that is not installed offers the Setup at its start, once per version unless the person keeps it
// standalone; on Linux `classeur install` integrates the copy where it is, and Nix installs it.

import "core:fmt"
import "core:os"
import "core:strings"
import config "gt:config"
import desktop "gt:desktop"
import "gt:i18n"
import "gt:platform"
import "gt:process"
import "gt:render"
import setup "gt:setup"
import store "gt:store"
import "core:math"
import "gt:draw"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import tasks "gt:tasks"
import "gt:ui"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

classeur_identity :: proc() -> desktop.Identity {
	return desktop.Identity{
		name = "Classeur", key = "Classeur", slug = APP_NAME, aumid = "FromentSoftware.Classeur",
		description = "A fast file manager: tabs in panels, a command palette, GoTo, batch rename, undo.",
		vendor = "Froment Software",
		entry_marker = "X-Classeur-Integration", registry_mark = "ClasseurIntegration", vendor_key = "FromentSoftware",
		manifest_name = "classeur_install.txt",
		generic_name = "File Manager", categories = "System;FileTools;FileManager;Utility;Core;",
		keywords = "folder;manager;explore;disk;filesystem;files;",
		env_prefix = "CLASSEUR_DESKTOP_",
		uninstall_arguments = "--setup",
		launcher_mark = LAUNCHER_MARK,
	}
}

// classeur's own parts of an install: the PATH.
classeur_parts :: proc(o: ^desktop.Integration_Options) {
	o.add_to_path = true
	o.launcher = CONSOLE_LAUNCHER   // (Windows: classeur.com with the PATH entry; nothing elsewhere)
}

// What classeur.com carries (the toolkit finds it there before it replaces or removes the file); the same as
// classeurtool's LAUNCHER_DEFINES.
LAUNCHER_MARK :: "(classeur console launcher)"

@(private = "file")
integration_options :: proc(args: []string) -> desktop.Integration_Options {
	o := desktop.options_make(classeur_identity())
	o.exe = process.executable_path()
	o.icons = ICON_PNGS[:]
	classeur_parts(&o)
	for a in args { if a == "--no-path" { o.add_to_path = false } }
	desktop.roots_from_env(&o, proc(name: string) -> string { return os.get_env(name, context.temp_allocator) })
	return o
}

cmd_install :: proc(args: []string) -> int {
	o := integration_options(args)
	if r := desktop.install(&o); r.error != .None {
		fmt.eprintfln("classeur: %s %s", desktop.error_text(r.error), r.detail)
		return 1
	}
	fmt.printfln("classeur: installed for %s (%s)", o.exe, desktop.targets(false))
	return 0
}

cmd_uninstall :: proc(args: []string) -> int {
	o := integration_options(args)
	if r := desktop.remove(&o); r.error != .None {
		fmt.eprintfln("classeur: %s %s", desktop.error_text(r.error), r.detail)
		return 1
	}
	fmt.println("classeur: the launcher, the icons and the link are gone")
	return 0
}

cmd_status :: proc(args: []string) -> int {
	o := integration_options(args)
	s := desktop.status(&o)
	defer desktop.status_destroy(&s)
	fmt.printfln("%s", desktop.describe(&s))
	for part in s.wanted {
		ps := s.parts[part]
		state := ps.present ? (ps.stale ? "points to another program" : ps.partial ? "incomplete" : "present") : "absent"
		fmt.printfln("  %v: %s", part, state)
	}
	return s.state == .Installed ? 0 : 1
}

////////////////////////////////
// The Setup (a window of its own over the page)

setup_config :: proc() -> setup.Setup_Options {
	return setup.Setup_Options{
		identity = classeur_identity(), version = APP_VERSION, install_folder = APP_NAME, icons = ICON_PNGS[:],
		choices = SETUP_CHOICES[:], square = true,
		prepare = proc(o: ^desktop.Integration_Options, choices: []bool, user: rawptr) {
			classeur_parts(o)
			if len(choices) == len(SETUP_CHOICES) { o.add_to_path = choices[0] }
		},
	}
}

// (not rodata: i18n.later marks the labels for the catalogue; tr where they are shown)
@(private = "file")
SETUP_CHOICES := [?]setup.Choice{
	{label = i18n.later("classeur in the terminal (on the PATH)"), on = true},
}

// What the person answered the Setup (setup.CHOICE_*), kept in <config>/classeur/setup.
setup_choice_file :: proc() -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_NAME, context.temp_allocator), "/setup"}, context.temp_allocator)
}

@(private = "file")
setup_choice_read :: proc() -> string {
	data, err := os.read_entire_file(setup_choice_file(), context.temp_allocator)
	return err == nil ? strings.trim_space(string(data)) : ""
}

// (by its writer's thread: the interface's never waits for the disk)
@(private = "file")
setup_choice_write :: proc(app: ^App, choice: string) {
	store.writer_put(&app.setup_writer, transmute([]u8)choice)
}

// At a start with the window: the Setup when there is something to do (Windows), unless the person answered for this
// version or keeps this copy standalone; `asked`: classeur --setup. The install's facts and the answer are read on a
// worker (they reach the disk, the registry): the offer comes when they land, and whether this copy is the installed one
// with them (the updater's auto). Headless (the tests), the worker reads nothing of the person's and offers nothing.
setup_offer :: proc(app: ^App, asked: bool) {
	if asked && !app.headless { setup.open(&app.setup, setup_config()) }
	job := new(Setup_Facts)
	job^ = {app = app, offer = SETUP_AT_START && !asked, headless = app.headless}
	tasks.add(&app.pool, setup_facts_run, job)
}

@(private = "file")
Setup_Facts :: struct {
	app:        ^App,
	offer:      bool,   // the Setup is offered if wanted
	headless:   bool,
	wanted:     bool,   // the worker's answers
	running_it: bool,
}

@(private = "file")
setup_facts_run :: proc(data: rawptr) {
	job := (^Setup_Facts)(data)
	if !job.headless {
		// (the facts' strings are in this worker's temp memory: only the answers are kept)
		f := setup.facts(setup_config())
		job.running_it = f.running_it
		job.wanted = job.offer && setup.wanted(f, APP_VERSION, setup_choice_read())
	}
	if !ui.post(&job.app.main.state, setup_facts_done, job) { free(job) }
}

@(private = "file")
setup_facts_done :: proc(data: rawptr, word: u64) {
	job := (^Setup_Facts)(data)
	defer free(job)
	app := job.app
	app.setup_known = true
	app.installed_copy = job.running_it
	updates_auto(app)
	if job.wanted { setup.open(&app.setup, setup_config()) }
	app_frames(app)
}

act_setup :: proc(app: ^App) { setup.open(&app.setup, setup_config()) }

////////////////////////////////
// The settings' general.menu and general.autostart (the toolkit's standard ones)

// The Setup (Windows) or `classeur install` (Linux) integrates a copy; the settings then say whether that copy is in
// the application menu and starts with the session, and desktop.apply makes it so. Only the integrated copy follows
// them: a build or a copy that is not integrated (Nix's, which Nix integrates) never installs anything because of a
// preference. So at the start, and after each change of the two, a worker reads the integration's status: when its parts
// are this copy's, it applies the two (the PATH part stays as the Setup or the install left it), and the settings show
// their switches. `classeur uninstall` and the Setup's Uninstall stay the way to take the whole integration away.
desktop_follow :: proc(app: ^App) {
	if app.headless || app.standalone { return }   // (the tests touch nothing of the person's; a torn-off tab's window owns nothing)
	job := new(Desktop_Follow)
	job^ = {app = app, menu = config.bool_of(&app.prefs, prefs_page.MENU_PREF), autostart = config.bool_of(&app.prefs, prefs_page.AUTOSTART_PREF)}
	// (the edits' worker: one at a time, in the order asked, so that the last change wins)
	tasks.add(&app.edit_pool, desktop_follow_run, job)
}

@(private = "file")
Desktop_Follow :: struct {
	app:        ^App,
	menu:       bool,
	autostart:  bool,
	integrated: bool,     // the worker's answer
	failed:     string,   // owned: what desktop.apply said went wrong
}

@(private = "file")
desktop_follow_run :: proc(data: rawptr) {
	job := (^Desktop_Follow)(data)
	o := integration_options(nil)
	st := desktop.status(&o, context.temp_allocator)
	job.integrated = st.state != .Absent && st.error == .None && st.stale_exe == ""
	if job.integrated {
		o.add_to_path = st.parts[.Path].present
		o.start_menu, o.autostart = job.menu, job.autostart
		if r := desktop.apply(&o); r.error != .None {
			job.failed = fmt.aprintf("%s %s", desktop.error_text(r.error), r.detail)
		}
	}
	if !ui.post(&job.app.main.state, desktop_follow_done, job) {
		delete(job.failed)
		free(job)
	}
}

@(private = "file")
desktop_follow_done :: proc(data: rawptr, word: u64) {
	job := (^Desktop_Follow)(data)
	defer { delete(job.failed); free(job) }
	app := job.app
	names := [?]string{prefs_page.MENU_PREF, prefs_page.AUTOSTART_PREF}
	for name in names {
		if r := config.ref_of(&app.prefs, name); r != config.NO_REF { config.entry(&app.prefs, r).def.hidden = !job.integrated }
	}
	if job.failed != "" { say(app, i18n.tr("The desktop's launcher cannot be changed: %s"), job.failed) }
	app_frames(app)
}

// classeur's own Setup screen over the toolkit's controller (gt:setup: the state, what is offered, the work on its
// thread): a head (the mark, what is offered, the versions, the state in its colour), then sections as the settings
// page has them (a small title, lines under a rule, no frame in a frame), and the buttons in a bar at the foot.
setup_build :: proc(app: ^App, em: f32) {
	d := &app.setup
	c := setup_config()
	ev := setup.update(d, c)
	if d.open {
		if !app.logo_made {
			img, ok := platform.clipboard_image_decode("image/png", ICON_PNGS[3].png, context.temp_allocator)
			if ok {
				app.logo = render.create_texture_rgba(&app.shared.r, img.size.x, img.size.y)
				render.update_texture_rgba(&app.shared.r, app.logo, 0, 0, img.size.x, img.size.y, img.rgba)
				app.logo_made = true
			}
		}
		was_open := d.open
		if ui.modal("setup", &d.open, {width_em = SETUP_PREFERRED_EM.x, height_em = SETUP_PREFERRED_EM.y, min_width_em = SETUP_MIN_EM.x, min_height_em = SETUP_MIN_EM.y, size = &d.size}) {
			setup_head(app, c, em)
			ui.hline(ui.fill())
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.scroll_y("###setup_body") {
				if d.known { setup_body(app, c, em) }
			}
			ui.hline(ui.fill())
			if bev := setup_buttons(app, c, em); bev != .None { ev = bev }
		}
		// (Escape, a click outside: closed without an answer; the controller says what to keep)
		if was_open && !d.open && ev == .None {
			d.open = true
			ev = setup.close(d, .Close)
		}
	}
	// (the answer is kept in the person's config: never by the tests)
	if app.headless { return }
	switch ev {
	case .Installed:       setup_choice_write(app, setup.CHOICE_INSTALLED)
		desktop_follow(app)   // (the switches of the menu and the session, for the copy just integrated)
	case .Kept_Standalone: setup_choice_write(app, setup.CHOICE_STANDALONE)
	case .Dismissed:       setup_choice_write(app, setup.choice_dismissed(APP_VERSION))
	case .Launched:
		// (the installed copy starts once this one has ended: app_run's end)
		delete(app.launch_after)
		app.launch_after = strings.clone(app.setup.installed)
		platform.request_close(app.main.win)
	case .Uninstalled:     desktop_follow(app)
	case .None:
	}
}

// Its size when first opened, and the least it can be made (em).
SETUP_PREFERRED_EM :: [2]f32{44, 31}
SETUP_MIN_EM :: [2]f32{30, 18}

@(private = "file")
setup_head :: proc(app: ^App, c: setup.Setup_Options, em: f32) {
	d := &app.setup
	f := &d.facts
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 5.2))})
	if ui.row(.Center, {}, "###setup_head") {
		ui.spacer(ui.px(em * 1.2))
		if app.logo_made {
			side := em * 3.2
			ui.next({width = ui.px(side), height = ui.px(side)})
			tex := ui.frame_new(render.Texture)
			tex^ = app.logo
			ui.custom("###setup_logo", proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) { draw.image(dc, (^render.Texture)(user)^, b.rect) }, tex)
			ui.spacer(ui.px(em * 0.9))
		}
		title, badge := i18n.tr("Reading the install…"), ""
		if d.known { title, badge = setup.headline(f^, c) }
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
		if ui.column(id = "###setup_words") {
			ui.next({width = ui.fill(), height = ui.px(em * 1.9), font_size = math.round(em * 1.35), text_pad = 0})
			ui.label(fmt.tprintf("%s###setup_title", title))
			installed := i18n.tr("none")
			if d.known && f.state != .Not_Installed && f.state != .Nix_Package { installed = f.version != "" ? fmt.tprintf("v%s", f.version) : i18n.tr("a copy") }
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 1.4), font_size = math.round(em * 0.9), text_pad = 0})
				ui.label(fmt.tprintf("%s###setup_versions", fmt.tprintf(i18n.tr("This copy: v%s   Installed copy: %s   %s"), c.version, installed, c.identity.vendor)))
			}
		}
		if badge != "" {
			_, tone := setup.state_words(f^, c)
			if ui.tags(tone == "accent" ? "" : tone) {
				ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1), text_pad = 0})
				ui.label(fmt.tprintf("%s###setup_badge", badge))
			}
		}
		ui.spacer(ui.px(em * 1.2))
		if ui.tags("weak") { if icon_action(app, "setup_close_x", lucide.X, i18n.tr("Close (Escape)"), em) { d.open = false } }
		ui.spacer(ui.px(em * 0.6))
	}
}

@(private = "file")
setup_body :: proc(app: ^App, c: setup.Setup_Options, em: f32) {
	d := &app.setup
	f := &d.facts
	// the state in a sentence, and what the last action said
	words, tone := setup.state_words(f^, c)
	ui.spacer(ui.px(em * 0.8))
	setup_paragraph("setup_state", words, tone == "accent" ? "" : tone, em)
	if d.note != "" || setup.busy(d) {
		setup_paragraph("setup_note", setup.busy(d) ? i18n.tr("Working…") : d.note, setup.busy(d) ? "weak" : d.note_good ? "good" : "bad", em)
	}
	setup_section(i18n.tr("Location"), em)
	setup_line(app, "setup_where", i18n.tr("Installed program"), f.exe, true, em)
	if !f.from_nix {
		setup_section(i18n.tr("Options"), em)
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.3))})
		if ui.row(.Center, {.Draw_Side_Bottom}, "###setup_opt_desk") {
			ui.spacer(ui.px(em * 1.2))
			ui.checkbox("###setup_shortcut", i18n.tr("Shortcut on the Desktop"), &d.shortcut)
		}
		for ch, i in setup_choices() {
			if i >= len(d.choices) { break }
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.3))})
			if ui.row(.Center, {.Draw_Side_Bottom}, fmt.tprintf("###setup_opt_%d", i)) {
				ui.spacer(ui.px(em * 1.2))
				ui.checkbox(fmt.tprintf("###setup_choice_%d", i), i18n.tr(ch.label), &d.choices[i])
			}
		}
	}
	setup_section(i18n.tr("On this system"), em)
	// (missing: of an install that is there; none: no install)
	absent := f.state == .Not_Installed || f.state == .Nix_Package ? i18n.tr("none") : i18n.tr("missing")
	setup_line(app, "setup_menu", i18n.tr(SETUP_MENU_WORDS), f.start_lnk ? i18n.tr("in place") : absent, false, em)
	setup_line(app, "setup_record", i18n.tr(SETUP_RECORD_WORDS), f.record ? i18n.tr("in place") : absent, false, em)
	setup_line(app, "setup_desk", i18n.tr("Desktop shortcut"), f.desk_lnk ? i18n.tr("in place") : i18n.tr("none"), false, em)
	setup_line(app, "setup_running", i18n.tr("This copy"), f.running, true, em)
	if f.nixos && f.state != .Nix_Package && f.state != .This_Copy {
		ui.spacer(ui.px(em * 0.6))
		setup_paragraph("setup_nixos", i18n.tr("On NixOS, a Nix package is the better install: Nix updates it. An install here makes this copy run by itself (nix-build makes the libraries it needs)."), "weak", em)
	}
	ui.spacer(ui.px(em * 0.8))
}

// A section's title, as the settings page has them: small capitals, weak, a rule under it.
@(private = "file")
setup_section :: proc(title: string, em: f32) {
	ui.spacer(ui.px(em * 1.0))
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8))})
	if ui.row(.Center, {.Draw_Side_Bottom}, fmt.tprintf("###setup_sec_%s", title)) {
		ui.spacer(ui.px(em * 1.2))
		if ui.tags("weak") {
			ui.next({width = ui.fill(), height = ui.pct(1), font_size = math.round(em * 0.8), text_pad = 0})
			ui.label(fmt.tprintf("%s###t", strings.to_upper(title, context.temp_allocator)))
		}
	}
}

// A line of a section: what, weak at a fixed width, then its value (a path in the mono face, copied by its button).
@(private = "file")
setup_line :: proc(app: ^App, id, key, value: string, path: bool, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2))})
	if ui.row(.Center, {.Draw_Side_Bottom}, fmt.tprintf("###%s", id)) {
		ui.spacer(ui.px(em * 1.2))
		if ui.tags("weak") {
			ui.next({width = ui.px(em * 10), height = ui.pct(1), text_pad = 0})
			ui.label(fmt.tprintf("%s###k", key))
		}
		if path {
			ui.next({width = ui.fill(), height = ui.pct(1), text_pad = 0, font = app.mono, font_size = math.round(em * 0.88)})
		} else {
			ui.next({width = ui.fill(), height = ui.pct(1), text_pad = 0})
		}
		ui.label(fmt.tprintf("%s###v", value))
		if path && value != "" {
			if ui.tags("weak") {
				if icon_action(app, fmt.tprintf("%s_copy", id), lucide.COPY, i18n.tr("Copy the path"), em) {
					ui.window_clipboard_set(value)
					announce(app, .Good, i18n.tr("Copied: %s"), value)
				}
			}
		}
		ui.spacer(ui.px(em * 0.8))
	}
}

@(private = "file")
setup_paragraph :: proc(id, text, tone: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Start, {}, fmt.tprintf("###%s_row", id)) {
		ui.spacer(ui.px(em * 1.2))
		if tone != "" { ui.push_tags(tone) }
		ui.next({width = ui.fill(), text_pad = 0})
		ui.paragraph(fmt.tprintf("%s###%s", text, id))
		if tone != "" { ui.pop_tags() }
		ui.spacer(ui.px(em * 1.2))
	}
}

// The bar of the buttons: Uninstall at the left (a second click does it), then what closes, what opens the copy just
// installed, what installs.
@(private = "file")
setup_buttons :: proc(app: ^App, c: setup.Setup_Options, em: f32) -> (ev: setup.Event) {
	d := &app.setup
	button :: proc(id, label: string, intent: ui.Intent, em: f32) -> bool {
		ui.next({width = ui.text_size(em * 1.2), height = ui.px(ui.dense(em * 2.2))})
		return ui.button(id, label, o = {intent = intent}).clicked
	}
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.4))})
	if ui.row(.Center, {}, "###setup_buttons") {
		ui.spacer(ui.px(em * 1.2))
		if setup.can_uninstall(d) {
			if button("setup_uninstall", d.confirm ? i18n.tr("Click again to uninstall") : i18n.tr("Uninstall"), .Danger, em) && !setup.busy(d) {
				if d.confirm { setup.start_uninstall(d, c) } else { d.confirm = true }
			}
		}
		ui.spacer(ui.fill())
		how := setup.closing(d, c)
		CLOSING_WORDS := [setup.Closing]string{.Close = i18n.tr("Close"), .Not_Now = i18n.tr("Not now"), .Keep_Standalone = i18n.tr("Keep standalone")}
		CLOSING_IDS := [setup.Closing]string{.Close = "setup_close", .Not_Now = "setup_later", .Keep_Standalone = "setup_standalone"}
		if button(CLOSING_IDS[how], CLOSING_WORDS[how], .Neutral, em) { ev = setup.close(d, how) }
		if d.installed != "" && d.facts.state != .This_Copy {
			ui.spacer(ui.px(em * 0.5))
			if button("setup_launch", i18n.tr("Open the installed copy"), .Primary, em) { ev = setup.open_installed(d) }
		}
		if label := setup.install_label(d, c); label != "" {
			ui.spacer(ui.px(em * 0.5))
			if button("setup_install", label, .Primary, em) && !setup.busy(d) { setup.start_install(d, c) }
		}
		ui.spacer(ui.px(em * 1.2))
	}
	if d.confirm && ui.key_press(.Escape) { d.confirm = false }
	return
}

@(private = "file")
setup_choices :: proc() -> []setup.Choice { return SETUP_CHOICES[:] }
