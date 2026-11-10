package classeur

// The session: what the window shows comes back at the next start (File Pilot's): its place and size, the sidebar, the
// panels and their tabs (the folder, the view's zoom, the lock), the panel with the keyboard; and the bookmarks and the
// recent folders. A text file, a line per thing, written when the window closes and when a bookmark changes:
//
//   window <left> <top> <width> <height> <maximized 0|1>
//   sidebar <shown 0|1> <width>
//   focus <panel>
//   panel <active tab>
//   tab <zoom> <locked 0|1> <path>
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
import "fs"

// Where the session is kept: <config>/classeur/session, unless the tests gave theirs.
session_file :: proc(app: ^App, allocator := context.temp_allocator) -> string {
	if app.session_path != "" { return strings.clone(app.session_path, allocator) }
	if app.headless || app.standalone { return "" }
	return strings.concatenate({platform.config_dir(context.temp_allocator), "/", APP_NAME, "/session"}, allocator)
}

// `later`: written on a worker (a bookmark changed); else now (the window closes).
session_save :: proc(app: ^App, later := false) {
	path := session_file(app)
	if path == "" { return }
	b := strings.builder_make(context.temp_allocator)
	pl := platform.get_placement(app.main.win)
	fmt.sbprintf(&b, "window %d %d %d %d %d\n", pl.rect[0], pl.rect[1], pl.rect[2], pl.rect[3], pl.maximized ? 1 : 0)
	fmt.sbprintf(&b, "sidebar %d %d\n", app.sidebar ? 1 : 0, int(app.sidebar_px))
	panels_text(app, &b)
	for p in app.bookmarks { fmt.sbprintf(&b, "bookmark %s\n", p) }
	for p in app.recents { fmt.sbprintf(&b, "recent %s\n", p) }
	if later {
		Write :: struct { path, text: string }
		w := new(Write)
		w^ = {strings.clone(path), strings.clone(strings.to_string(b))}
		pool_submit(&app.pool, proc(data: rawptr) {
			w := (^Write)(data)
			session_write(w.path, w.text)
			delete(w.path)
			delete(w.text)
			free(w)
		}, w)
		return
	}
	session_write(path, strings.to_string(b))
}

// The panels and their tabs as lines (the session's, a layout's).
panels_text :: proc(app: ^App, b: ^strings.Builder) {
	fmt.sbprintf(b, "focus %d\n", app.focus)
	for p in app.panels {
		fmt.sbprintf(b, "panel %d%s\n", p.active, p.below ? " below" : "")
		for t in p.tabs { fmt.sbprintf(b, "tab %d %d %s\n", t.zoom, t.locked ? 1 : 0, t.path) }
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
			zoom_text, _, rest2 := strings.partition(rest, " ")
			lock_text, _, dir := strings.partition(rest2, " ")
			if dir == "" { continue }
			zoom, _ := strconv.parse_int(zoom_text)
			// (a folder gone since: the read, on a worker, goes up to the nearest one still there)
			tab_open(app, panel, dir)
			t := panel.tabs[len(panel.tabs) - 1]
			t.zoom = clamp(zoom, 0, len(ZOOMS) - 1)
			t.locked = lock_text == "1"
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

// (written beside, then renamed over: a crash while writing leaves the last session whole)
@(private = "file")
session_write :: proc(path, text: string) {
	_ = os.make_directory_all(fs.parent(path))
	tmp := strings.concatenate({path, ".new"}, context.temp_allocator)
	if os.write_entire_file(tmp, transmute([]u8)text) != nil { return }
	_ = os.rename(tmp, path)
}

// Reads the session. `tabs`: the panels and tabs come back too (no folder was given on the command line). true: a
// panel was opened.
session_load :: proc(app: ^App, tabs: bool) -> (opened: bool) {
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
			f := strings.fields(rest, context.temp_allocator)
			if len(f) < 5 { continue }
			for i in 0 ..< 4 { place.rect[i], _ = strconv.parse_int(f[i]) }
			place.maximized = f[4] == "1"
			has_place = place.rect[2] > 200 && place.rect[3] > 150
		case "sidebar":
			f := strings.fields(rest, context.temp_allocator)
			if len(f) < 2 { continue }
			app.sidebar = f[0] == "1"
			if px, ok := strconv.parse_int(f[1]); ok { app.sidebar_px = clamp(f32(px), 140, 600) }
		case "focus", "panel", "tab":
			if tabs { fmt.sbprintf(&panel_lines, "%s\n", line) }
		case "bookmark":
			if rest != "" { append(&app.bookmarks, strings.clone(rest)) }
		case "recent":
			if rest != "" && len(app.recents) < RECENTS_MAX { append(&app.recents, strings.clone(rest)) }
		}
	}
	opened = tabs && panels_open(app, strings.to_string(panel_lines))
	if has_place && !app.headless { platform.set_placement(app.main.win, place) }
	return
}
