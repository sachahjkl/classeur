package classeur

// The running program: one window, its panels of tabs, the workers that read the file system. The interface is built
// each frame from the App (view.odin); the workers change nothing of it themselves: their results come through ui.post.

import "base:runtime"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import config "gt:config"
import crash "gt:crash"
import "gt:devtools"
import "gt:font"
import "gt:host"
import "gt:i18n"
import "gt:instance"
import tk_log "gt:log"
import lucide "gt:lucide"
import "gt:platform"
import "gt:render"
import prefs_page "gt:prefs_page"
import process "gt:process"
import crash_bar "gt:crash_bar"
import setup "gt:setup"
import store "gt:store"
import tasks "gt:tasks"
import update "gt:update"
import "gt:ui"
import "fs"

// Frames owed after an event: what it set off settles (the layout, the reveal of the cursor's row).
FRAMES_AFTER_INPUT :: 3

App :: struct {
	shared:      host.Shared,
	main:        host.Host,
	icons:       font.Font_Id,      // Lucide: the thin icons of the bars' buttons
	mono:        font.Font_Id,
	devtools:    ^devtools.Server,  // TOOLKIT_DEVTOOLS=<port>: driven and captured over the Chrome DevTools Protocol
	theme_shown: ui.Theme_Shown,
	pool:        tasks.Pool,        // the reads of folders, the places, the launches: it grows while a share hangs
	measure_pool: tasks.Pool,
	thumb_pool:  tasks.Pool,        // the thumbnails of the grid (thumbs.odin): the newest asked first, the cards on screen
	edit_pool:   tasks.Pool,        // the changes to files the interface asks for (a rename, a new folder, an undo): one
	                                // worker, so that they are done in the order they were asked (edit_submit)
	answers_due: int,               // the tasks of edit_submit and places_load whose answer has not come back
	steps_due:   int,               // the changes on the edits' worker whose step of the undo is not there yet
	places_asked: u64,              // the last read of the places asked (an older answer is dropped)
	places_language: u32,           // i18n.version() the places' names were asked in (app_frame reads them again)
	thumbs:      map[string]Thumb,  // by path, size and date (thumb_key; the keys owned)
	icons_cache: map[string]Sys_Icon,   // the system's icons by key and size (icons.odin)
	icon_keys:   map[string]string,     // a file's name -> its icon's key (both owned)
	type_names:  map[string]Type_Name,  // an extension -> the system's name of its type (type_names.odin; keys owned)
	today:       datetime.Date,         // the local date, read once a frame by date_text (Relative dates) ...
	today_frame: u64,                   // ... in this frame
	vol_from, vol_to: string,           // owned: the last pair asked whether on one volume (a drag), and the answer
	vol_same:    bool,
	vol_known:   bool,                  // vol_same is the worker's answer (else the guess is used: dnd.odin)
	drag_first_folder: bool,            // the first of the files dragged is a folder (the ghost's icon)
	drag_checked: string,               // owned: the folder the dragged files were last checked against (drop_takes) ...
	drag_check_ok: bool,                // ... whether it takes them
	drag_check_valid: bool,             // ... for this drag's files (a new drag checks again)
	frame:       u64,               // the frames built (what a thumbnail was last used in)
	shown_frame: u64,               // atomic: the last frame built, for the workers (a thumbnail not wanted since is not read)
	default_zoom: int,             // the measures of folders (measure.odin)
	measures:    map[string]Measure,   // by path (the keys owned)
	measure_asks: map[u64]^Measure_Ask,   // by tab: what each asked on its folder (measure.odin)
	measures_serial: u64,              // raised as each measure comes (what is worked out of them is made again)
	recents:     [dynamic]string,   // owned: the folders visited, the last first (the sidebar)
	bookmarks:   [dynamic]string,   // owned
	undo:        [dynamic]Undo_Step,   // what was done to files, the last at the end (undo.odin)
	redo:        [dynamic]Undo_Step,   // what was undone, to do again (the last undone at the end)
	side_open:   [Side_Section]bool,   // the sections of the sidebar that are open
	side_order:  [len(Side_Section)]Side_Section,   // the sections in the person's order (side.order)
	side_heads:  [Side_Section]ui.Rect,   // each section's heading, as last laid out (where a dragged one lands)
	side_end_y:  f32,                   // the end of the last section (a heading dragged under it goes last)
	side_drag:   Side_Section,          // the heading dragged ...
	side_dragging: bool,                // ... while it is
	side_held:     bool,                // ... and its button is still down (let go: it lands)
	gesture_cancelled: bool,            // Escape ended a drag or a rectangle, its button still down: nothing starts till its release
	side_cancelled: bool,               // Escape cancelled it, its button still down
	side_menu_of:  Side_Section,
	side_touched:  bool,
	side_row_path: string,              // owned: the place it was opened on
	side_row_kind: Side_Row_Kind,
	bm_drag:       int,                 // the bookmark dragged ...
	bm_dragging:   bool,                // ... while it is
	bm_held:       bool,                // ... and its button is still down (let go: it lands)
	bm_cancelled:  bool,                // Escape cancelled it, its button still down (its release opens nothing)
	bm_line:       ui.Rect,             // where it lands, as shown ({}: none)
	no_dialog:     bool,                // this build: no dialog takes the keys (typing goes to the filter)                // a heading was clicked or dragged: the section the commands move is known
	side_filter: ui.Line_Edit,
	keys_at:     Keys_At,           // what has the keyboard: the panel's list, the sidebar, the inspector (F6)
	side_keys:   Side_Keys,         // the sidebar's cursor while it has the keyboard (sidebar.odin)
	volume_space: [dynamic]fs.Space,   // of each volume, read with the places
	panel_rects: [dynamic]ui.Rect,  // each panel's box as last laid out (the tabs above are as wide)
	tz:          ^datetime.TZ_Region,   // the local time zone (nil: UTC)

	panels:      [dynamic]^Panel,
	focus:       int,               // the panel the keyboard works in
	next_tab_id: u64,
	closed_tabs: [dynamic]string,   // owned: what Ctrl+Shift+T opens again, the last closed last
	home:        string,            // owned
	places:      [dynamic]Place,    // the sidebar (places.odin)
	volumes:     []fs.Volume,

	default_sort: fs.Sort,
	show_hidden:  bool,
	sidebar:      bool,             // shown
	sidebar_px:   f32,              // its width, logical pixels

	palette:     Palette,           // the command palette (palette.odin)
	goto:        Goto,              // GoTo (goto.odin)
	batch:       Batch,             // batch rename (batch.odin)
	band:        Band,              // the rectangle selection (band.odin)
	layouts:     Layouts,           // the layouts saved by name (layouts.odin)
	keymap:      Keymap,            // the person's keys and aliases (keymap.odin)
	jobs_view:   Jobs_View,         // the jobs' window (jobs_view.odin)
	tab_drag:    Tab_Drag,          // a tab dragged (tab_drag.odin)
	columns:      ui.Table_Layout,  // the details' columns: their order, the ones shown, their widths (view.columns)
	column_defs:  [Detail]ui.Table_Column,   // DETAIL_COLUMNS: the table's columns
	columns_menu_tab: u64,          // the tab whose header's menu is open (its sort is the menu's)
	zoom_slider_tab: u64,
	tab_rects:   [dynamic]Tab_Rect, // the tabs' boxes of this frame
	tab_rects_last: [dynamic]Tab_Rect,   // and of the last one (what a released tab is tested against)
	rename:      Rename,            // the rename in place (actions.odin)
	cut:         map[string]bool,   // owned keys: the paths cut, drawn dimmed until the paste or another copy or cut (a
	                                // set: each row shown asks it at each frame)
	paste:       Paste_Asked,       // the paste waiting for the clipboard's files (actions.odin)
	status:      string,            // owned: the last message said (say, announce), as the tests read it
	room:        f32,               // the window's width at this build, logical pixels
	window_px:   [2]f32,            // the window's size at this build, frame pixels (a tab dragged out of it)
	text_keys:   [dynamic]ui.Key,   // the text fields built in this frame (view.odin: the keys of the list are not theirs)
	text_keys_before: [dynamic]ui.Key,   // and in the last one
	menu:        Entry_Menu,        // the entries' menu (menu.odin)
	panel_menus: Panel_Menus,       // the history and the panel's menu (menu.odin)
	watch:       Folder_Watch,      // the folders of the tabs, watched (watcher.odin)
	jobs:        Jobs,              // copies, moves, the trash (jobs.odin)
	confirm:     Confirm,           // delete for good? (dialogs.odin)
	conflict:    Conflict_View,     // a name taken: what to do (dialogs.odin)
	prefs:       config.Prefs,      // the preferences (prefs.odin)
	settings:    Settings,          // their values as the program reads them
	standard:    prefs_page.Standard_Watch,   // the toolkit's standard settings applied as they change (prefs.odin)
	themes_file: prefs_page.Themes_File,      // the program's themes and the person's own (themes.txt): the themes shown
	options:     Options,
	licence:     Licence_View,      // who supports classeur (licence.odin): the settings' General page
	inspector:   Inspector,         // the pane of Space (inspector.odin)           // the options' list (options.odin)
	drop_zones:      [dynamic]Drop_Zone,   // where a drop goes, noted by this frame (dnd.odin)
	drop_zones_last: [dynamic]Drop_Zone,   // and by the last one (what a drop is tested against)
	drop_hover:  string,            // owned: the folder a drop would go into now ("": none)
	drag_paths:  [dynamic]string,   // owned: what the next drag_start carries
	dragging:    []string,          // the files of the drag that runs now (drag_paths'), nil between drags
	drag_started: bool,             // the press that is held has started its drag
	file_drag:   bool,              // drag_paths are dragged in the window (file_drag_frame) ...
	spring_target: string,          // owned: what the dragged files rest on ("": nothing to open), its timer set when it changed
	spring_done:   bool,            // ... and it was opened: not again till the target changes
	drag_out:    bool,              // ... or left it: the system's drag takes them after this frame (drag_run)
	install:     prefs_page.Install,   // the install: its offer, its dialog, the settings' page (integration.odin)
	launch_after: string,           // owned: this program again after an update (Restart), started once this one has ended ("": none)
	updater:        ^update.Updater,   // checks, downloads and puts in place a new classeur (updates.odin; nil headless)
	measures_sorted_at: f64,           // when measures_resort last sorted (ui.now_ms)
	update_serial:  int,               // the updater's state last said
	installed_copy: bool,              // this copy is the installed one: it updates itself by itself
	headless:    bool,              // the tests: no window of the system, no program started (open_system)
	announcer:     ui.Announcer,       // where a finished act is said (announce): general.messages
	system_thumbs: bool,            // the system's thumbnails are asked (desktop.thumbnail: its cache, its thumbnailers);
	                                // off headless, so a test never reaches the person's cache (one turns it on with its own)
	session_path: string,           // owned: the tests' session file ("": the person's, none when headless)
	standalone:  bool,              // a window of a torn-off tab (tab_drag.odin): no session
	exe:         string,            // owned: this program's file, read at the start (after an update puts a new one in
	                                // its place, Linux reads the running one as "<path> (deleted)")
	tab_out:     u64,               // a tab dragged out of the window: the drag of the system starts after this frame
	tab_out_home: bool,             // that drag came back and was dropped in this window
	tab_coming:   bool,             // a tab of another window is dragged over this one (tab_drop) ...
	tab_coming_at: [2]f32,          // ... the pointer there
	tab_coming_path: string,        // owned: ... its folder, "" until the system gives it (Linux: at the drop)
	session_writer: store.Writer,   // the files written as the window runs, each by a thread of its own: the window
	prefs_writer:   config.User_Writer,   // never waits for a disk, the latest text wins
	layouts_writer: store.Writer,
	prefs_words:    vmem.Arena,     // the standard preferences' descriptions (the registry keeps them: prefs.odin)
	crash_bar:      crash_bar.Bar,  // the report of the last session, which did not end cleanly: a bar at the top
	mounting:     [dynamic]string,  // owned: the shares being found or mounted on a worker (locations.odin)
	shares:       []fs.Share,       // the shares of the network mounted now (the sidebar's Network section)
	devices:      []fs.Network_Device,   // the devices of the network that share files, as last found (network.odin)
	devices_asked: u64,             // the last search asked (an older answer is dropped)
	devices_searching: bool,        // a search runs
	devices_seen_open: bool,        // the Network section was open at the last build (opened again: a new search)
	side_device_uris: [dynamic]string,   // owned: their URIs
	session_seen:    string,        // owned: the session's text at its last change (session_autosave waits for it to settle)
	session_changed_ms: f64,        // when it changed
	session_written: string,        // owned: the session (but the window's place) as last written (session_autosave)
	tab_image:    platform.Drag_Image,   // owned: the dragged tab's picture, read back from the renderer (tab_drag_poll)
	opened:      [dynamic]string,   // headless: what open_system would have opened (owned)
	launched_on: int,               // atomic: the thread that last started a program (launch: a worker, never this one)
	window_fails: bool,             // the tests: a tab's window of its own fails to start (tab_window)
	setup_known: bool,              // the start's reading of the install came (setup_follow)
}

WINDOW_SIZE :: [2]int{1180, 720}

// The window of this process (none in the tests): what a second start's message opens its folders in.
global_app: ^App

Open_Options :: struct {
	folders:  []string,   // a tab for each (none: the home folder)
	headless: bool,       // no window of the system: offscreen, the software renderer, the fonts compiled in (the tests)
	size:     [2]int,     // 0: WINDOW_SIZE
	home:     string,     // "": the person's (the tests give theirs)
	session:  string,     // the session file ("": the person's; headless: none)
	standalone: bool,     // a window of a torn-off tab: no session read or written
}

// `standalone`: a window of a tab torn off another (classeur --window): it owns nothing (no instance, no session).
app_run :: proc(folders: []string, setup_asked := false, standalone := false) -> int {
	// one window per person: a second start hands its folders to the first, which opens them in tabs, and ends
	outcome := instance.Outcome.Other_Instance
	owner: instance.Owner
	if !standalone {
		// (its launcher's activation token first: the first start's window comes up with it on Wayland)
		message := app_message_make(platform.activation_token_from_env(context.temp_allocator), folders)
		outcome, owner = instance.acquire({name = app_instance_name(), wait_ms = 2000}, transmute([]u8)message)
		if outcome == .Forwarded { return 0 }
	}
	// (a window's process only: a second start forwarded above writes nothing)
	logger := tk_log.install({program = APP_NAME, echo = true})
	program_logger = logger
	context.logger = logger
	defer {
		context.logger = {}
		program_logger = {}
		tk_log.close(logger)
	}
	crash.install({program = APP_NAME, version = APP_VERSION, log_tail = {tk_log.tail, logger.data}})
	// (the session's mark: the main window's alone, a torn-off one's process ends with its tab)
	report := ""
	if !standalone {
		crash.begin_session()
		report, _ = crash.last_report(context.temp_allocator)
	}
	app := app_open({folders = folders, standalone = standalone})
	if app == nil {
		if outcome == .First { instance.owner_stop(&owner) }
		if !standalone { crash.end_session() }
		return 1
	}
	if report != "" { crash_bar.init(&app.crash_bar, report) }
	server: ^instance.Server
	if outcome == .First { server = instance.serve_start(owner, app_message, app) }
	platform.show_window(app.main.win)
	// (the install read on a task; offered at the start on Windows. The tests read nothing of the person's)
	if !app.headless { prefs_page.install_offer(&app.install, &app.main.state, offer = SETUP_AT_START && !setup_asked) }
	if setup_asked && !app.headless { prefs_page.install_open(&app.install) }
	if !standalone { updates_start(app) }   // (one updater: the main window's; a torn-off one leaves the file alone)
	for !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		app_frame(app)
	}
	updates_stop(app)
	instance.serve_stop(server)
	launch := strings.clone(app.launch_after, context.temp_allocator)
	// (the window is closed and the instance let go: the installed copy the install opened may start now)
	prefs_page.install_end(&app.install)
	prefs_page.install_launch(&app.install)
	app_close(app)
	if !standalone {
		fs.archive_take_out_clear()   // (what was opened out of archives: the main window's to remove)
		crash.end_session()
	}
	// (Restart after an update: it starts once this one let go of the instance)
	if launch != "" { _ = setup.launch(launch) }
	return 0
}

// What a second start hands the first: its launcher's activation token on a line of its own (marked by a byte no path
// has), then its folders, one a line.
APP_MESSAGE_TOKEN :: "\x01"
// What `classeur --status` hands it: only whether it answers; the running classeur does nothing with it.
APP_MESSAGE_PING :: "\x02ping"

// The single instance's name: the person's (a debug build has its own).
@(private = "file")
app_instance_name :: proc() -> string {
	return instance.key(ODIN_DEBUG ? "classeur.dev" : "classeur", platform.user_dir(.Config, "", context.temp_allocator))
}

// Whether a classeur runs and answers (--status: setup.Setup_Options.running).
app_running :: proc() -> bool {
	return instance.send({name = app_instance_name(), wait_ms = 2000}, transmute([]u8)string(APP_MESSAGE_PING)) == .Forwarded
}

app_message_make :: proc(token: string, folders: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	if token != "" { strings.write_string(&b, APP_MESSAGE_TOKEN); strings.write_string(&b, token); strings.write_byte(&b, '\n') }
	for f, i in folders {
		if i > 0 { strings.write_byte(&b, '\n') }
		strings.write_string(&b, f)
	}
	return strings.to_string(b)
}

app_message_read :: proc(text: string) -> (token: string, folders: []string) {
	list := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(line, APP_MESSAGE_TOKEN) { token = line[len(APP_MESSAGE_TOKEN):]; continue }
		if line != "" { append(&list, line) }
	}
	return token, list[:]
}

// A second start's folders (on the instance's thread): copied, handed to the interface's.
@(private = "file")
app_message :: proc(user: rawptr, message: []byte) {
	app := (^App)(user)
	if string(message) == APP_MESSAGE_PING { return }
	text := strings.clone(string(message))
	if !ui.post(&app.main.state, app_message_open, rawptr(raw_data(text)), u64(len(text))) { delete(text) }
}

// The folders of a second start, each in a new tab of the panel with the keyboard (none: the home folder); the window
// comes to the front.
@(private = "file")
app_message_open :: proc(data: rawptr, word: u64) {
	text := string(([^]u8)(data)[:word])
	defer delete(text)
	app := global_app
	if app == nil { return }
	p := current_panel(app)
	token, folders := app_message_read(text)
	folders_show(app, folders)
	if len(folders) == 0 { tab_open(app, p, app.home, p.active + 1) }
	platform.raise_window_token(app.main.win, token)
	app_frames(app)
}

// Opens the window and its first tabs. nil: no window (said why).
app_open :: proc(o: Open_Options) -> ^App {
	app := new(App)
	if !o.headless { global_app = app }
	app.headless = o.headless
	app.system_thumbs = !o.headless
	app.session_path = strings.clone(o.session)
	app.standalone = o.standalone
	app.exe = strings.clone(process.executable_path())
	app.home = o.home != "" ? fs.clean(o.home) : fs.home()
	app.sidebar = true
	app.sidebar_px = 210
	app.tz, _ = timezone.region_load("local")

	platform.set_app_id(APP_NAME)
	size := o.size != {} ? o.size : WINDOW_SIZE
	if !host.host_open(&app.main, &app.shared, {title = "Classeur", size = size, integrated_title = !o.headless, headless = o.headless}, view_build, app) {
		log.error("classeur: no window")
		free(app)
		return nil
	}
	h := &app.main
	win := h.win
	// (its mode: general.messages, settings_apply; its toasts this window's, also for a message said between builds)
	app.announcer.state = &h.state
	if !o.headless { app.announcer.window = win }
	app.icons, _ = font.load_embedded(&app.shared.fonts, lucide.DATA)
	app.mono, _ = font.load_embedded(&app.shared.fonts, font.FALLBACK_MONO_DATA)
	h.state.icon_font = app.icons   // (the menus' icons are the commands' Lucide ones; the widgets keep the toolkit's marks)
	h.after_input = FRAMES_AFTER_INPUT
	dnd_start(app)
	ui.table_layout_init(&app.columns, detail_columns(app))   // (before the preferences: they say its columns)
	prefs_open(app)   // (and h.partial_redraw: rendering.partial_redraw)
	prefs_page.install_init(&app.install, &app.prefs, setup_options())
	h.params = app_params
	h.input = app_input
	app.devtools = devtools.start_from_env(win, APP_NAME)
	h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }

	pools_start(app)
	licence_open(app)
	desktop_follow(app)
	palette_start(app)
	app.side_open = {.Recents = false, .Bookmarks = true, .Storage = true, .Network = true, .Places = true}
	jobs_start(app)
	watcher_start(app)
	places_load(app)
	layouts_load(app)
	// (the files written as the window runs: their paths known now, a test's included)
	if path := session_file(app); path != "" { store.writer_open(&app.session_writer, path) }
	if path := layouts_file(app); path != "" { store.writer_open(&app.layouts_writer, path) }
	// (the session's tabs come back; folders given open beside them, as the second start's do)
	if session_load(app) {
		folders_show(app, o.folders)
	} else {
		first := new(Panel)
		append(&app.panels, first)
		if len(o.folders) == 0 {
			tab_open(app, first, app.home)
		} else {
			for f in o.folders { tab_open(app, first, f) }
			first.active = 0
		}
	}
	// (the keys go to the list from the start: the arrows did nothing until a click)
	if t := current_tab(app); t != nil { t.focus_due = .List }
	return app
}

// Folders asked for (the command line, a second start): each one's tab in the panel with the keyboard shown, a new one
// after the shown tab when the panel has none on it.
folders_show :: proc(app: ^App, folders: []string) {
	p := current_panel(app)
	if p == nil { return }
	next: for f in folders {
		want := fs.clean(f, context.temp_allocator)
		for t, i in p.tabs {
			if t.path == want {
				p.active = i
				continue next
			}
		}
		tab_open(app, p, f, p.active + 1)
	}
}

app_frame :: proc(app: ^App) {
	host.host_frame(&app.main)
	session_autosave(app)
	prefs_tidy(app)   // (each round, a frame drawn or not: a change made with no frame is written too)
	drag_run(app)   // (between frames: it blocks until the drop)
	tab_out_run(app)
	// (the places' names are translated on the worker that reads them: a new language reads them again)
	if app.places_language != i18n.version() { places_load(app) }
}

// How long closing waits for the workers' tasks (a walk, a measure stop at their next folder; a read of one folder
// does not stop).
QUIT_WAIT_MS :: 500

// The workers that read folders (the measures and the thumbnails have their own: MEASURE_THREADS, THUMB_THREADS), and
// the ones the reads may add while theirs are held by a share that hangs.
POOL_THREADS :: 3
POOL_GROW    :: 8

// The program's log, for the workers' context ({}: none, as in the tests).
program_logger: runtime.Logger

// The workers' context: the heap and each thread's own temporary memory, never the opener's (a test's tracking
// allocator is not shared between threads).
@(private = "file")
pools_start :: proc(app: ^App) {
	context = runtime.default_context()
	if program_logger.procedure != nil { context.logger = program_logger }
	tasks.start(&app.pool, {threads = POOL_THREADS, grow = POOL_GROW})
	tasks.start(&app.measure_pool, {threads = MEASURE_THREADS})
	tasks.start(&app.thumb_pool, {threads = THUMB_THREADS, grow = THUMB_THREADS, newest_first = true})
	tasks.start(&app.edit_pool, {threads = 1})
}

// Stops a pool, the work that waits dropped (its memory goes with the process), and waits for its threads until
// `until`. A read of a share that hangs never ends and tasks.stop joins it: the stop runs on a thread of its own, and
// one still running then is left to the process's end. False: the pool's threads may still read the App.
@(private = "file")
pool_stop_until :: proc(p: ^tasks.Pool, until: time.Tick) -> bool {
	stopper := thread.create_and_start_with_data(p, proc(data: rawptr) { tasks.stop((^tasks.Pool)(data), proc(data: rawptr) {}) })
	for !thread.is_done(stopper) && time.tick_diff(time.tick_now(), until) > 0 { time.sleep(2 * time.Millisecond) }
	if !thread.is_done(stopper) { return false }
	thread.join(stopper)
	thread.destroy(stopper)
	return true
}

app_close :: proc(app: ^App) {
	watcher_stop(app)
	jobs_stop(app)
	// the walks and the measures running end at their next folder; no tab points to its walk any more (its job is
	// freed by its worker once the posts are refused)
	for p in app.panels {
		for t in p.tabs {
			if t.walk != nil { sync.atomic_store(&t.walk.cancel, true) }
			t.walk = nil
		}
	}
	measures_cancel(app)
	// (from now a worker's result is refused, the worker frees it; a worker never waits for room in the queue)
	ui.post_close(&app.main.state)
	// A read of a share that hangs never ends, and a thread cannot be joined with a time limit: the workers get until
	// QUIT_WAIT_MS, then one still in its task is left to the process's end. It still reads the App: then it is not freed.
	until := time.tick_add(time.tick_now(), QUIT_WAIT_MS * time.Millisecond)
	reads_ended := pool_stop_until(&app.pool, until)
	edits_ended := pool_stop_until(&app.edit_pool, until)
	session_save(app)   // (after the workers: a bookmark asked of one of them is in it)
	// (what is pending written now: the process may end before their threads would)
	store.writer_flush(&app.layouts_writer)
	measures_ended := pool_stop_until(&app.measure_pool, until)
	thumbs_ended := pool_stop_until(&app.thumb_pool, until)
	thumbs_free(app)
	icons_free(app)
	type_names_free(app)
	delete(app.type_names)
	inspector_free(app)   // (before the renderer goes: the textures are its)
	devtools.stop(app.devtools)
	if global_app == app { global_app = nil }
	prefs_page.install_end(&app.install)   // (again for a window app_run did not end: it does nothing the second time)
	crash_bar.destroy(&app.crash_bar)
	host.host_close(&app.main)
	if !reads_ended || !edits_ended || !measures_ended || !thumbs_ended { return }
	app_free(app)
	free(app)
}

@(private = "file")
app_free :: proc(app: ^App) {
	for p in app.panels { panel_destroy(p) }
	delete(app.panels)
	for p in app.closed_tabs { delete(p) }
	delete(app.closed_tabs)
	places_free(app)
	delete(app.places)
	devices_free(app)
	palette_free(&app.palette)
	entry_menu_free(&app.menu)
	goto_free(&app.goto)
	batch_free(&app.batch)
	band_free(&app.band)
	layouts_free(&app.layouts)
	keymap_free(&app.keymap)
	delete(app.launch_after)
	delete(app.exe)
	tab_image_free(app)
	delete(app.tab_rects)
	ui.table_layout_destroy(&app.columns)
	delete(app.tab_rects_last)
	rename_free(&app.rename)
	cut_forget(app)
	delete(app.cut)
	delete(app.paste.dir)
	confirm_free(&app.confirm)
	options_free(&app.options)
	licence_close(app)
	prefs_close(app)
	delete(app.home)
	delete(app.session_path)
	delete(app.status)
	delete(app.text_keys)
	measures_free(app)
	for p in app.recents { delete(p) }
	delete(app.recents)
	for p in app.bookmarks { delete(p) }
	delete(app.bookmarks)
	undo_free(app)
	dnd_free(app)
	delete(app.vol_from)
	delete(app.vol_to)
	delete(app.tab_coming_path)
	delete(app.session_written)
	delete(app.session_seen)
	store.writer_close(&app.session_writer)
	_ = config.user_writer_stop(&app.prefs_writer, &app.prefs)
	store.writer_close(&app.layouts_writer)
	for u in app.mounting { delete(u) }
	delete(app.mounting)
	ui.line_edit_destroy(&app.side_filter)
	delete(app.side_row_path)
	delete(app.volume_space)
	delete(app.panel_rects)
	delete(app.text_keys_before)
	for p in app.opened { delete(p) }
	delete(app.opened)
	if app.tz != nil { timezone.region_destroy(app.tz) }
}

// What each build is given: the palette and the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	s := &app.settings
	choice := ui.Theme_Choice{name = s.theme, mode = s.mode, finish = s.finish, glow = s.glow}
	if ui.theme_show(&app.shared.theme, themes(app), choice, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
	}
	bp.disable_zoom = true   // (Ctrl+wheel zooms a panel's view: app_input)
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(26)}, font = app.shared.font, font_size = app.settings.font_size, text_pad = 5, cursor = .Arrow}
}

// More frames: something changed outside of an input (a worker's result).
app_frames :: proc(app: ^App) {
	app.main.settle = max(app.main.settle, FRAMES_AFTER_INPUT)
}

// A message in the window for a few seconds (a toast): what went wrong, a hint, a state just changed.
say :: proc(app: ^App, format: string, args: ..any) {
	status_keep(app, fmt.tprintf(format, ..args))
	// (in the main window's toasts whatever general.messages says: a message said between builds, a task's, shows there)
	if !app.headless { ui.announce(&app.announcer, .Info, app.status, in_window = true) }
}

// A finished act (copied, saved, deleted, moved), said where general.messages says: the system's notifications, the
// window, or nowhere. A failure (.Bad) is always said.
announce :: proc(app: ^App, kind: ui.Toast_Kind, format: string, args: ..any) {
	status_keep(app, fmt.tprintf(format, ..args))
	if !app.headless { ui.announce(&app.announcer, kind, app.status) }
}

@(private = "file")
status_keep :: proc(app: ^App, text: string) {
	delete(app.status)
	app.status = strings.clone(text)
}

// How round classeur's own drawings are (the rows' pill, the boxes) against the default: 1 at appearance.rounding's
// default, 0 square, 2 at the slider's end (the toolkit's boxes follow ui.set_rounding by themselves).
corner_k :: proc() -> f32 { return ui.rounding(ui.current_state()) }

// appearance.density's compact step (the Density command's other; 1, the default, is the comfortable one).
DENSITY_COMPACT :: 0.82

// The selection's fill: the theme's (its accent, a tint), as in the toolkit's lists.
selection_color :: proc(app: ^App) -> ui.Color { return ui.color("selection") }

// The themes the window can show: the toolkit's (gui_toolkit docs/themes.md), the same as its other programs', then the
// person's own (themes.txt).
themes :: proc(app: ^App) -> []ui.Theme_Def { return app.themes_file.all[:] }

// The window's input before the interface: Ctrl+wheel over a panel zooms its view (File Pilot's), and the list under it
// does not scroll. The clipboard's answers go to what asked for them.
@(private = "file")
app_input :: proc(h: ^host.Host, events: []platform.Event) -> []platform.Event {
	app := (^App)(h.user)
	out := make([dynamic]platform.Event, 0, len(events), context.temp_allocator)
	for e in events {
		// a drag of another program's: where it would go, and the drop
		#partial switch e.kind {
		case .Drop_Enter, .Drop_Over, .Drop_Leave, .Drop:
			platform.drop_set_effect(h.win, drop_answer(app, e.kind, e.pos, e.mods, e.drop_allowed))
			if e.kind == .Drop || e.kind == .Drop_Leave { platform.drop_data_release(h.win) }
			continue
		case .Clipboard_Data:
			// (a paste's files, the batch rename's names: asked, they come here. The event goes on to the interface: a
			// field's paste is its own request, each side takes only the ids it asked)
			clipboard_answer(app, e.clipboard)
		}
		if e.kind == .Scroll && .Ctrl in e.mods {
			for r, i in app.panel_rects {
				if i >= len(app.panels) { break }
				if e.pos.x < r.min.x || e.pos.x >= r.max.x || e.pos.y < r.min.y || e.pos.y >= r.max.y { continue }
				if t := panel_tab(app.panels[i]); t != nil && e.delta.y != 0 {
					tab_set_zoom(app, t, t.zoom + (e.delta.y < 0 ? 1 : -1))
				}
			}
			continue
		}
		append(&out, e)
	}
	return out[:]
}
