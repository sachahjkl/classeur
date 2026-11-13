package classeur

// The session: what the window shows comes back at the next start (File Pilot's): its place and size, the sidebar, the
// panels and their tabs (the folder, the view's zoom, the lock), the panel with the keyboard; and the bookmarks and the
// recent folders. A text file, a line per thing, written when the window closes and, on a worker, as soon as any of it
// but the window's place changes (session_autosave: a program killed, a session of the system ended, loses nothing):
//
//   window <left> <top> <width> <height> [maximized]      (platform.placement_text)
//   sidebar <shown 0|1> <width>
//   focus <panel>
//   panel <active tab>
//   tab <zoom> <locked 0|1> <sort key> <descending 0|1> <path>
//   bookmark <path>
//   recent <path>
//
// A line not understood is skipped (a file of another version loses that line only). A tab whose folder is gone opens
// at the nearest folder above it that is still there (the read of the tab goes up: tab.odin's load_done).

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "gt:platform"
import store "gt:store"
import "gt:ui"
import "fs"

// Where the session is kept: <config>/classeur/session, unless the tests gave theirs.
session_file :: proc(app: ^App, allocator := context.temp_allocator) -> string {
	if app.session_path != "" { return strings.clone(app.session_path, allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.user_dir(.Config, APP_NAME, context.temp_allocator), "/session"}, allocator)
}

// `later`: written by its writer's thread (the session changed while the window runs); else now, waited for (the window
// closes: whatever was pending is superseded by this one).
session_save :: proc(app: ^App, later := false) {
	path := session_file(app)
	if path == "" { return }
	b := strings.builder_make(context.temp_allocator)
	pl := platform.get_placement(app.main.win)
	fmt.sbprintf(&b, "window %s\n", platform.placement_text(pl))
	session_rest(app, &b)
	store.writer_put(&app.session_writer, transmute([]u8)strings.to_string(b))
	if !later { store.writer_flush(&app.session_writer) }
}

// What the session holds but the window's place.
@(private = "file")
session_rest :: proc(app: ^App, b: ^strings.Builder) {
	fmt.sbprintf(b, "sidebar %d %d\n", app.sidebar ? 1 : 0, int(app.sidebar_px))
	panels_text(app, b)
	for p in app.bookmarks { fmt.sbprintf(b, "bookmark %s\n", p) }
	for p in app.recents { fmt.sbprintf(b, "recent %s\n", p) }
}

// After a frame: the session written again when what it holds changed and stayed so SESSION_SETTLE_MS (the window's
// place alone waits for the next write: a window moved or resized changes it every frame). Not while a press is held:
// a splitter dragged changes the sidebar's width every frame; once let go and settled it is written once.
SESSION_SETTLE_MS :: 400

session_autosave :: proc(app: ^App) {
	if session_file(app) == "" || ui.active_key() != 0 { return }
	b := strings.builder_make(context.temp_allocator)
	session_rest(app, &b)
	text := strings.to_string(b)
	if text == app.session_written {
		app.session_changed_ms = 0
		return
	}
	// (changed: written once it has not changed for a while; the loop is woken then, the window may be idle)
	now := ui.now_ms()
	if text != app.session_seen {
		delete(app.session_seen)
		app.session_seen = strings.clone(text)
		app.session_changed_ms = now
	}
	if left := SESSION_SETTLE_MS - (now - app.session_changed_ms); left > 0 {
		ui.wake_within(&app.main.state, int(left) + 1)   // (the loop sleeps: woken when it is due)
		return
	}
	delete(app.session_written)
	app.session_written = strings.clone(text)
	session_save(app, later = true)
}

// The panels and their tabs as lines (the session's, a layout's).
panels_text :: proc(app: ^App, b: ^strings.Builder) {
	fmt.sbprintf(b, "focus %d\n", app.focus)
	for p in app.panels {
		fmt.sbprintf(b, "panel %d%s\n", p.active, p.below ? " below" : "")
		for t in p.tabs { fmt.sbprintf(b, "tab %d %d %d %d %s\n", t.zoom, t.locked ? 1 : 0, int(t.folder.sort.key), t.folder.sort.descending ? 1 : 0, t.path) }
	}
}

// Opens the panels and tabs that `text`'s focus, panel and tab lines say, after the panels there are (none: the caller
// closed them). True: a panel opened.
panels_open :: proc(app: ^App, text: string) -> bool {
	rest_text := text
	panel: ^Panel
	focus := 0
	first := len(app.panels)
	for line in strings.split_lines_iterator(&rest_text) {
		word, _, rest := strings.partition(line, " ")
		switch word {
		case "focus":
			focus, _ = strconv.parse_int(rest)
		case "panel":
			panel = new(Panel)
			append(&app.panels, panel)
			active_text, _, flags := strings.partition(rest, " ")
			panel.active, _ = strconv.parse_int(active_text)
			panel.below = flags == "below" && len(app.panels) > first + 1
		case "tab":
			if panel == nil { continue }
			parts: [4]string
			dir := rest
			for i in 0 ..< 4 { parts[i], _, dir = strings.partition(dir, " ") }
			if dir == "" { continue }
			zoom, _ := strconv.parse_int(parts[0])
			key, _ := strconv.parse_int(parts[2])
			// (a folder gone since: the read, on a worker, goes up to the nearest one still there)
			tab_open(app, panel, dir)
			t := panel.tabs[len(panel.tabs) - 1]
			t.zoom = clamp(zoom, 0, len(ZOOMS) - 1)
			t.locked = parts[1] == "1"
			if key >= 0 && key <= int(max(fs.Sort_Key)) {
				t.folder.sort.key, t.folder.sort.descending = fs.Sort_Key(key), parts[3] == "1"
			}
		}
	}
	// (a panel left with no tab, a version's file cut short: dropped)
	for i := len(app.panels) - 1; i >= first; i -= 1 {
		if len(app.panels[i].tabs) == 0 {
			panel_destroy(app.panels[i])
			ordered_remove(&app.panels, i)
		}
	}
	for p in app.panels { p.active = clamp(p.active, 0, len(p.tabs) - 1) }
	app.focus = clamp(first + focus, 0, max(len(app.panels) - 1, 0))
	return len(app.panels) > first
}

// Reads the session: the window's place, the sidebar, the panels and tabs, the bookmarks and recents. True: a panel was
// opened. (Read on this thread: at the start, before the window is shown and the first frame.)
session_load :: proc(app: ^App) -> (opened: bool) {
	path := session_file(app)
	if path == "" { return }
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil { return }
	text := string(data)
	panel_lines := strings.builder_make(context.temp_allocator)
	place: platform.Placement
	has_place := false
	for line in strings.split_lines_iterator(&text) {
		word, _, rest := strings.partition(line, " ")
		switch word {
		case "window":
			if p, ok := platform.placement_parse(rest); ok && p.rect[2] > 200 && p.rect[3] > 150 { place, has_place = p, true }
		case "sidebar":
			f := strings.fields(rest, context.temp_allocator)
			if len(f) < 2 { continue }
			app.sidebar = f[0] == "1"
			if px, ok := strconv.parse_int(f[1]); ok { app.sidebar_px = clamp(f32(px), 140, 600) }
		case "focus", "panel", "tab":
			fmt.sbprintf(&panel_lines, "%s\n", line)
		case "bookmark":
			if rest != "" { append(&app.bookmarks, strings.clone(rest)) }
		case "recent":
			if rest != "" && len(app.recents) < RECENTS_MAX { append(&app.recents, strings.clone(rest)) }
		}
	}
	opened = panels_open(app, strings.to_string(panel_lines))
	if has_place && !app.headless { platform.set_placement(app.main.win, place) }
	return
}
