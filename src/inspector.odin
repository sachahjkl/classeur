package classeur

// The inspector, File Pilot's (Space): a pane at the right of the panel that shows what the cursor is on. A picture
// large, a PDF's first page or a frame of a video (the system's large thumbnail), a text file's beginning in the
// monospaced font, a folder's content, any other file what it is. What it shows is read on the workers when the cursor
// stops on it; only the last one asked is kept.

import "core:fmt"
import config "gt:config"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import desktop "gt:desktop"
import "gt:draw"
import lucide "gt:lucide"
import "gt:platform"
import "gt:render"
import syntax "gt:syntax"
import "gt:ui"
import "fs"

INSPECTOR_TEXT_BYTES :: 64 * 1024
INSPECTOR_PICTURE_PX :: 1600
INSPECTOR_MIN_PX     :: 220
INSPECTOR_DEFAULT_PX :: 380
INSPECTOR_THUMB_PX   :: 1024   // the system's thumbnail of a PDF or a video: its largest (the xx-large of freedesktop.org)

Inspect_Kind :: enum u8 { None, Picture, Text, Folder, Other }

Inspector :: struct {
	open:     bool,
	pane:     ui.Pane,         // its width, dragged by its edge (ui.pane_split), folded to a strip; kept in inspector.width
	path:     string,          // owned: what is shown (or asked)
	serial:   u64,             // the ask the pane waits for
	ready:    bool,
	kind:     Inspect_Kind,
	text:     string,          // owned
	spans:    [dynamic]syntax.Span,   // its colours (worked out with it, on the worker: not each frame)
	language: bool,            // the text is a source file's: shown in its colours
	cut:      bool,            // the text is the file's first INSPECTOR_TEXT_BYTES only
	tex:      render.Texture,
	has_tex:  bool,
	size:     [2]int,          // the texture's (shrunk to INSPECTOR_PICTURE_PX)
	pixels:   [2]int,          // the picture's own, as its file holds it
	caption:  string,          // the picture is the system's thumbnail of the file: what it is of ("": the file's own)
	preview:  ui.Preview,      // the picture's zoom and pan (the wheel, a drag, a double click: the toolkit's preview)
	listing:  fs.Listing,      // sorted (on the worker)
	visible:  [dynamic]u32,    // its entries that are not hidden (made on the worker: a frame goes through none)
	props:    fs.Properties,   // owned strings: what the system says of it besides its size and date
	has_props: bool,
	box:      ui.Key,          // its box: the toolkit's focus while it has the keyboard (F6)
	moved_by: platform.Key,    // (this build: the key that scrolls what it shows, .None: none)
	summary:  Summary,         // several selected: what the pane says of them
}

// Several selected: how many, of which kinds, their size, the first of them; worked out when the selection, the rows or
// a measure change (summary_update), read by the frames.
Summary :: struct {
	key:     Summary_Key,
	count:   int,
	folders: int,
	files:   int,
	bytes:   i64,
	rows:    [dynamic]u32,     // the first INSPECTOR_SUMMARY_ROWS selected, their entries' indices, in the rows' order
	made:    int,              // the times it was worked out
}

Summary_Key :: struct { tab, selection, ids, measures: u64, entries: int }

@(private = "file")
Inspect_Job :: struct {
	app:     ^App,
	serial:  u64,
	path:    string,           // owned
	kind:    Inspect_Kind,
	text:    string,           // owned until taken
	spans:   [dynamic]syntax.Span,   // owned until taken
	language: bool,
	cut:     bool,
	rgba:    []u8,
	size:    [2]int,
	pixels:  [2]int,
	caption: string,           // asked of the system's thumbnail (preview_caption; a constant)
	listing: fs.Listing,
	sort:    fs.Sort,          // the listing's order
	visible: [dynamic]u32,     // owned until taken
	props:   fs.Properties,    // owned strings
	has_props: bool,
}

inspector_free :: proc(app: ^App) {
	insp := &app.inspector
	inspector_clear(app)
	delete(insp.path)
	insp.path = ""
	delete(insp.summary.rows)
	insp.summary = {}
}

@(private = "file")
inspector_clear :: proc(app: ^App) {
	insp := &app.inspector
	delete(insp.text)
	insp.text = ""
	delete(insp.spans)
	insp.spans, insp.language, insp.cut = nil, false, false
	insp.pixels, insp.caption = {}, ""
	if insp.has_tex { render.destroy_texture(&app.shared.r, insp.tex) }
	insp.has_tex = false
	insp.preview = {}   // (another picture: fitted again)
	fs.listing_destroy(&insp.listing)
	delete(insp.visible)
	insp.visible = nil
	props_free(&insp.props)
	insp.ready, insp.kind, insp.has_props = false, .None, false
}

@(private = "file")
props_free :: proc(p: ^fs.Properties) {
	delete(p.permissions)
	delete(p.owner)
	p^ = {}
}

// Its edge: dragged from INSPECTOR_MIN_PX to most of the panel, folded to a strip, saved when let go.
inspector_pane_options :: proc(app: ^App) -> ui.Pane_Options {
	return ui.Pane_Options{side = .After, default_size = INSPECTOR_DEFAULT_PX, min_size = INSPECTOR_MIN_PX, collapsible = true, title = "Inspector",
		user = app, on_save = proc(user: rawptr, p: ^ui.Pane) {
			app := (^App)(user)
			config.set_int(&app.prefs, config.ref_of(&app.prefs, "inspector.width"), i64(p.size[.X]))
			prefs_save(app)
		}}
}

act_inspector :: proc(app: ^App) {
	insp := &app.inspector
	insp.open = !insp.open
	if insp.pane.size[.X] <= 0 { insp.pane.size[.X] = f32(config.int_of(&app.prefs, "inspector.width")) }
	insp.pane.collapsed = false
	if !insp.open {
		inspector_clear(app)
		delete(insp.path)
		insp.path = ""
	}
}

// Asks for what `path` shows, unless it is what the pane has.
@(private = "file")
inspector_ask :: proc(app: ^App, path: string, e: fs.Entry) {
	insp := &app.inspector
	if insp.path == path { return }
	inspector_clear(app)
	delete(insp.path)
	insp.path = strings.clone(path)
	insp.serial += 1
	job := new(Inspect_Job)
	job^ = {app = app, serial = insp.serial, path = strings.clone(path), sort = app.default_sort}
	switch {
	case e.kind == .Directory:                                job.kind = .Folder
	case e.kind == .File && thumb_mime(e.name) != "":         job.kind = .Picture
	case e.kind == .File && app.system_thumbs && preview_caption(e.name) != "":
		job.kind, job.caption = .Picture, preview_caption(e.name)
	case e.kind == .File && looks_textual(e.name, e.flags):   job.kind = .Text
	case:                                                     job.kind = .Other
	}
	pool_submit(&app.pool, inspect_run, job)
}

// What the system's thumbnail of a file shows, by its name: a PDF's first page, a frame of a video; "" for the others
// (their thumbnail, when the system has one, is no closer look than their icon).
@(private = "file")
preview_caption :: proc(name: string) -> string {
	switch strings.to_lower(fs.extension(name), context.temp_allocator) {
	case "pdf":
		return "First page"
	case "mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "flv", "mpg", "mpeg", "ogv", "3gp", "ts", "mts", "m2ts":
		return "A frame of the video"
	}
	return ""
}

// A name whose content reads as text (the content decides at last: a zero byte, or no valid UTF-8, is no text).
@(private = "file")
looks_textual :: proc(name: string, flags: fs.Flags) -> bool {
	binary := [?]string{"png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "avif", "heic", "tif", "tiff", "mp3", "flac", "wav", "ogg",
		"m4a", "opus", "mp4", "mkv", "webm", "mov", "avi", "zip", "tar", "gz", "xz", "bz2", "7z", "rar", "zst", "iso", "pdf", "doc",
		"docx", "odt", "xls", "xlsx", "ods", "ppt", "pptx", "exe", "dll", "so", "o", "a", "bin", "class", "jar", "ttf", "otf", "woff2"}
	ext := strings.to_lower(fs.extension(name), context.temp_allocator)
	for b in binary { if b == ext { return false } }
	return true
}

@(private = "file")
inspect_run :: proc(data: rawptr) {
	job := (^Inspect_Job)(data)
	defer if !ui.post(&job.app.main.state, inspect_done, job) { inspect_free(job) }
	// (what the system says of it, whatever it is)
	if p, ok := fs.properties(job.path); ok {
		job.props = {created = p.created, accessed = p.accessed, permissions = strings.clone(p.permissions), owner = strings.clone(p.owner)}
		job.has_props = true
	}
	switch job.kind {
	case .Folder:
		fs.list(&job.listing, job.path)
		// (sorted here, and the entries not hidden found here: not on the interface's thread)
		entries := job.listing.entries[:]
		order := make([]u32, len(entries), context.temp_allocator)
		for &o, i in order { o = u32(i) }
		fs.sort_order(entries, order, job.sort)
		sorted := make([]fs.Entry, len(entries), context.temp_allocator)
		for i, k in order { sorted[k] = entries[i] }
		copy(entries, sorted)
		job.visible = make([dynamic]u32, 0, len(entries))
		for e, i in entries { if .Hidden not_in e.flags { append(&job.visible, u32(i)) } }
	case .Picture:
		if job.caption != "" {
			// (the system's: its cache, else its thumbnailer, which this worker waits for)
			th, ok := desktop.thumbnail(job.path, INSPECTOR_THUMB_PX)
			if !ok { job.kind = .Other; return }
			job.rgba, job.size = th.rgba, th.size
			return
		}
		info, ok := fs.stat(job.path)
		if !ok || info.size > THUMB_MAX_BYTES { job.kind = .Other; return }
		bytes, err := os.read_entire_file(job.path, context.temp_allocator)
		if err != nil { job.kind = .Other; return }
		img, decoded := platform.clipboard_image_decode(thumb_mime(job.path), bytes)
		if !decoded { job.kind = .Other; return }
		defer delete(img.rgba)
		job.pixels = img.size
		job.rgba, job.size = shrink(img.rgba, img.size, INSPECTOR_PICTURE_PX)
	case .Text:
		f, err := os.open(job.path)
		if err != nil { job.kind = .Other; return }
		defer os.close(f)
		// (one byte more than is shown: whether the file goes on past it)
		buf := make([]u8, INSPECTOR_TEXT_BYTES + 1, context.temp_allocator)
		n, _ := os.read(f, buf)
		job.cut = n > INSPECTOR_TEXT_BYTES
		text := string(buf[:clamp(n, 0, INSPECTOR_TEXT_BYTES)])
		for len(text) > 0 && !utf8.valid_string(text) { text = text[:len(text) - 1] }   // (cut inside a character)
		if strings.index_byte(text, 0) >= 0 || (n > 0 && len(text) == 0) { job.kind = .Other; return }
		job.text = strings.clone(text)
		// (its language by its name, else by what it holds: a script with no extension)
		l, ok := syntax.language_of_file(job.path)
		if !ok { l, ok = syntax.guess(job.text) }
		if ok {
			job.spans = make([dynamic]syntax.Span)
			syntax.spans(job.text, l, &job.spans)
			job.language = true
		}
	case .Other, .None:
	}
}

@(private = "file")
inspect_free :: proc(job: ^Inspect_Job) {
	delete(job.path)
	delete(job.text)
	delete(job.spans)
	delete(job.rgba)
	props_free(&job.props)
	fs.listing_destroy(&job.listing)
	delete(job.visible)
	free(job)
}

@(private = "file")
inspect_done :: proc(data: rawptr, word: u64) {
	job := (^Inspect_Job)(data)
	defer inspect_free(job)
	app := job.app
	insp := &app.inspector
	if job.serial != insp.serial || !insp.open { return }
	insp.kind, insp.ready = job.kind, true
	insp.props, insp.has_props = job.props, job.has_props
	job.props = {}
	switch job.kind {
	case .Picture:
		insp.tex = render.create_texture_rgba(&app.shared.r, job.size.x, job.size.y)
		render.update_texture_rgba(&app.shared.r, insp.tex, 0, 0, job.size.x, job.size.y, job.rgba)
		insp.has_tex, insp.size, insp.pixels, insp.caption = true, job.size, job.pixels, job.caption
	case .Text:
		insp.text, job.text = job.text, ""
		insp.spans, job.spans = job.spans, nil
		insp.language, insp.cut = job.language, job.cut
	case .Folder:
		insp.listing, job.listing = job.listing, {}
		insp.visible, job.visible = job.visible, nil
	case .Other, .None:
	}
	app_frames(app)
}

// The pane, beside the list of the panel that has the keyboard.
inspector_build :: proc(app: ^App, t: ^Tab, em: f32) {
	insp := &app.inspector
	e := folder_cursor_entry(&t.folder)
	several := t.folder.count > 1
	// (several selected: a summary of them, nothing to read)
	if e != nil && !several { inspector_ask(app, fs.join(t.path, e.name, context.temp_allocator), e^) }
	// (its edge, the toolkit's: dragged, folded to a strip, Enter and the arrows)
	r := ui.pane_split("###insp_split", .X, &insp.pane, inspector_pane_options(app))
	if r.size <= 0 { return }
	width := r.size * ui.scale()
	ui.next({width = ui.px(width), height = ui.fill(), axis = .Y})
	// (no line of its own: the edge that drags it is the line between it and the list)
	box := ui.build_box({.Clip}, "###inspector")
	insp.box = box.key
	if app.keys_at == .Inspector { inspector_keys_mark(box) }
	// (with the keyboard: Escape gives it back to the list; the moves are taken here, whatever it shows, or the toolkit's
	// arrows would move the focus away; its text or its rows scroll by them)
	insp.moved_by = .None
	if app.keys_at == .Inspector && app.no_dialog {
		if ui.key_press(.Escape) { keys_to(app, .List) }
		for k in ([]platform.Key{.Page_Down, .Page_Up, .Down, .Up, .Home, .End, .Left, .Right}) {
			if ui.key_press(k) { insp.moved_by = k }
		}
	}
	if ui.parent(box) {
		if several {
			inspector_summary(app, t, em)
			return
		}
		if e == nil {
			// (the folder itself in the head: the pane keeps its close button)
			name := fs.base(t.path)
			if name == "" { name = t.path }
			inspector_head(app, t.path, true, name, "", em)
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 4), text_align = .Center})
				ui.label(len(t.folder.shown) == 0 ? "This folder is empty.###insp_nothing" : "Nothing selected.###insp_nothing")
			}
			return
		}
		// what it is: its icon, its name, its size, its pixels (a picture) and its date
		size := e.size >= 0 ? size_text(e.size) : ""
		if m, ok := measure_of(app, t, e^); ok { size = fmt.tprintf("%s · %d folders · %d files", size_text(m.bytes), m.folders, m.files) }
		if insp.ready && insp.kind == .Picture && insp.pixels.x > 0 { size = fmt.tprintf("%s · %d × %d", size, insp.pixels.x, insp.pixels.y) }
		meta := fmt.tprintf("%s · %s · %s", type_text(app, e^), size, date_text(app, e.mtime))
		inspector_head(app, fs.join(t.path, e.name, context.temp_allocator), e.kind == .Directory, fs.base(e.name), meta, em)
		if insp.ready && insp.has_props { inspector_props(app, t, e^, em) }
		if !insp.ready {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 4), text_align = .Center})
				ui.label("Reading…###insp_wait")
			}
			return
		}
		switch insp.kind {
		case .Picture:
			// (fitted; the wheel zooms about the pointer, a drag moves it, a double click goes to its pixels and back; its
			// keys stay the list's: the arrows move the cursor, Space closes the inspector)
			// (at the top of its room, under the properties: its box as tall as the picture fitted to the pane's width,
			// shorter when the pane is not that tall)
			room := width - em * 1.6
			fitted := min(f32(insp.size.y), room * f32(insp.size.y) / f32(max(insp.size.x, 1)))
			ui.spacer(ui.px(em * 0.6))
			ui.next({width = ui.fill(), height = ui.px(max(fitted, em), 0)})
			if ui.row() {
				ui.spacer(ui.px(em * 0.8))
				ui.next({width = ui.fill(), height = ui.fill()})
				ui.preview_image("###insp_pic", &insp.preview, insp.tex, {f32(insp.size.x), f32(insp.size.y)}, {buttons = true, radius = 3 * corner_k(), no_keys = true})
				ui.spacer(ui.px(em * 0.8))
			}
			if insp.caption != "" {
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(em * 2.2), text_align = .Center, font_size = em * 0.86})
					ui.label(fmt.tprintf("%s###insp_caption", insp.caption))
				}
			}
		case .Text:
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.scroll_y("###insp_text") {
				inspector_scroll_keys(app, ui.parent_box(), em)
				ui.spacer(ui.px(em * 0.5))
				// (as tall as its text: a row of the style's height let the text run past it, and the view had nothing to scroll)
				ui.next({width = ui.fill(), height = ui.children_sum()})
				if ui.row() {
					ui.spacer(ui.px(em * 0.8))
					ui.next({width = ui.fill()})
					if ui.style({font = app.mono, font_size = em * 0.92}) {
						// (a source file in its language's colours: the toolkit's syntax lexer; plain text as it is)
						if insp.language {
							ui.rich_paragraph("###insp_body", code_runs(insp.text, insp.spans[:]))
						} else {
							ui.paragraph(fmt.tprintf("%s###insp_body", shown_text(insp.text)))
						}
					}
					ui.spacer(ui.px(em * 0.8))
				}
				if insp.cut {
					if ui.tags("weak") {
						ui.next({width = ui.fill(), height = ui.px(em * 3), text_align = .Center, font_size = em * 0.86})
						ui.label(fmt.tprintf("The first %s are shown.###insp_cut", size_text(INSPECTOR_TEXT_BYTES)))
					}
				}
			}
		case .Folder:
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.scroll_y("###insp_folder") {
				inspector_scroll_keys(app, ui.parent_box(), em)
				// (a glance, as the summary: its first rows built, the others counted; a frame goes through no more)
				n := app.show_hidden ? len(insp.listing.entries) : len(insp.visible)
				for k in 0 ..< min(n, INSPECTOR_SUMMARY_ROWS) {
					i := app.show_hidden ? k : int(insp.visible[k])
					x := insp.listing.entries[i]
					// (a double click opens it, as in the list: a folder in the tab, a file with its application)
					ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
					sig: ui.Signal
					if ui.row(.Center, {.Clickable, .Draw_Hot_Effects, .Hot_Within}, fmt.tprintf("###insp_e%d", i)) {
						sig = ui.signal(ui.parent_box())
						ui.spacer(ui.px(em * 0.8))
						entry_glyph(app, insp.path, x, em * 1.8)
						ui.spacer(ui.px(em * 0.4))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label(fmt.tprintf("%s###n", shown_text(x.name)))
					}
					if sig.double_clicked {
						open_entry(app, t, insp.path, x)
						break
					}
				}
				if n > INSPECTOR_SUMMARY_ROWS {
					if ui.tags("weak") {
						ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0)), text_pad = em * 3.0})
						ui.label(fmt.tprintf("and %d more###insp_more", n - INSPECTOR_SUMMARY_ROWS))
					}
				}
				if len(insp.listing.entries) == 0 {
					if ui.tags("weak") {
						ui.next({width = ui.fill(), height = ui.px(em * 4), text_align = .Center})
						ui.label("This folder is empty.###insp_empty")
					}
				}
			}
		case .Other, .None:
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 4), text_align = .Center})
				ui.label("No preview for this kind of file.###insp_none")
			}
		}
	}
}

// With the keyboard (F6): Page Up and Page Down, Home and End, Up and Down by a line scroll `view`.
@(private = "file")
inspector_scroll_keys :: proc(app: ^App, view: ^ui.Box, em: f32) {
	line := em * 1.5
	page := max(view.size.y - line, line)
	y := view.view_target.y
	#partial switch app.inspector.moved_by {
	case .Page_Down: y += page
	case .Page_Up:   y -= page
	case .Down:      y += line
	case .Up:        y -= line
	case .Home:      y = 0
	case .End:       y = ui.view_limit(view)
	case:            return
	}
	view.view_target.y = clamp(y, 0, ui.view_limit(view))
	app_frames(app)
}

// It has the keyboard: a line of the accent along its top, as the shown tab of the panel that has it.
@(private = "file")
inspector_keys_mark :: proc(b: ^ui.Box) {
	b.custom = proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
		w := max(2, ui.scale() * 2)
		draw.rect(dc, {b.rect.min, {b.rect.max.x, b.rect.min.y + w}}, ui.color("accent"))
	}
}

// Its head: an icon, a title, a weak line under it (none when `meta` is empty) and the close button. The icon is the
// system's for `path`; with no path, Lucide's files (several selected).
@(private = "file")
inspector_head :: proc(app: ^App, path: string, folder: bool, title, meta: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.2))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###insp_head") {
		ui.spacer(ui.px(em * 0.6))
		if path != "" {
			path_icon(app, path, folder, em * 2.4)
		} else {
			if ui.tags("weak") {
				ui.next({width = ui.px(em * 2.4), height = ui.pct(1), font = app.icons, text_align = .Center, font_size = em * 1.5})
				ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###icon", lucide.FILES))
			}
		}
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.4)})
			ui.label(fmt.tprintf("%s###name", shown_text(title)))
			if meta != "" {
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(em * 1.3), font_size = em * 0.86})
					ui.label(fmt.tprintf("%s###meta", meta))
				}
			}
			ui.spacer(ui.fill())
		}
		if ui.tags("weak") { if icon_action(app, "insp_close", lucide.X, command_tip(app, "inspector"), em) { act_inspector(app) } }
		ui.spacer(ui.px(em * 0.3))
	}
}

INSPECTOR_SUMMARY_ROWS :: 200   // the rows a list of the pane names (the selection, a folder's entries); the others counted

// Several selected: how many, of which kinds, their size (the files' and the folders' measured), then their list.
@(private = "file")
inspector_summary :: proc(app: ^App, t: ^Tab, em: f32) {
	s := summary_update(app, t)
	parts := make([dynamic]string, context.temp_allocator)
	if s.folders > 0 { append(&parts, fmt.tprintf("%d %s", s.folders, s.folders == 1 ? "folder" : "folders")) }
	if s.files > 0 { append(&parts, fmt.tprintf("%d %s", s.files, s.files == 1 ? "file" : "files")) }
	append(&parts, size_text(s.bytes))
	inspector_head(app, "", false, fmt.tprintf("%d items", s.count), strings.join(parts[:], " · ", context.temp_allocator), em)
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.scroll_y("###insp_items") {
		inspector_scroll_keys(app, ui.parent_box(), em)
		// (a list to glance at, not to page through: Ctrl+A in a large folder built every row at each frame)
		for i, k in s.rows {
			x := t.folder.listing.entries[i]
			ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
			if ui.row(.Center, {}, fmt.tprintf("###insp_s%d", k)) {
				ui.spacer(ui.px(em * 0.8))
				entry_glyph(app, t.path, x, em * 1.8)
				ui.spacer(ui.px(em * 0.4))
				ui.next({width = ui.fill(), height = ui.pct(1)})
				ui.label(fmt.tprintf("%s###n", shown_text(x.name)))
			}
		}
		if s.count > len(s.rows) {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0)), text_pad = em * 3.0})
				ui.label(fmt.tprintf("and %d more###insp_more", s.count - len(s.rows)))
			}
		}
	}
}

// The summary of the selection of `t`, worked out again only when the selection, the rows or a measure changed since:
// a frame with nothing changed goes through none of the selected rows.
summary_update :: proc(app: ^App, t: ^Tab) -> ^Summary {
	s := &app.inspector.summary
	f := &t.folder
	key := Summary_Key{t.id, f.sel_serial, f.ids_version, app.measures_serial, len(f.listing.entries)}
	if s.made > 0 && s.key == key { return s }
	s.key = key
	s.made += 1
	s.count, s.folders, s.files, s.bytes = 0, 0, 0, 0
	clear(&s.rows)
	add :: proc(app: ^App, t: ^Tab, s: ^Summary, i: u32) {
		x := t.folder.listing.entries[i]
		if x.kind == .Directory {
			s.folders += 1
			if m, ok := measure_of(app, t, x); ok { s.bytes += m.bytes }
		} else {
			s.files += 1
			if x.size > 0 { s.bytes += x.size }
		}
		if len(s.rows) < INSPECTOR_SUMMARY_ROWS { append(&s.rows, i) }
		s.count += 1
	}
	// (the selected rows, as folder_targets has them: shown only for several, never the cursor's entry alone)
	if f.count == 0 { return s }
	for i in f.shown {
		if !f.selected[i] { continue }
		add(app, t, s, i)
		if s.count == f.count { break }
	}
	return s
}

// Its properties (File Pilot's): where it is, its dates, its permissions and its owner (Linux) or attributes (Windows).
@(private = "file")
inspector_props :: proc(app: ^App, t: ^Tab, e: fs.Entry, em: f32) {
	insp := &app.inspector
	p := insp.props
	line :: proc(app: ^App, id, key, value: string, em: f32, mono := false) {
		if value == "" { return }
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8))})
		if ui.row(.Center, {}, id) {
			ui.spacer(ui.px(em * 0.8))
			if ui.tags("weak") {
				ui.next({width = ui.px(em * 6.5), height = ui.pct(1), font_size = em * 0.88})
				ui.label(fmt.tprintf("%s###k", key))
			}
			if mono {
				ui.next({width = ui.fill(), height = ui.pct(1), font = app.mono, font_size = em * 0.86})
			} else {
				ui.next({width = ui.fill(), height = ui.pct(1), font_size = em * 0.9})
			}
			ui.label(fmt.tprintf("%s###v", shown_text(value)))
			ui.spacer(ui.px(em * 0.5))
		}
	}
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
	if ui.column(.Start, {.Draw_Side_Bottom}, "###insp_props") {
		ui.spacer(ui.px(em * 0.3))
		line(app, "###p_where", "Where", home_path(app, fs.parent(insp.path)), em, mono = true)
		line(app, "###p_modified", "Modified", date_text(app, e.mtime), em)
		if p.created != 0 { line(app, "###p_created", "Created", date_text(app, p.created), em) }
		if p.accessed != 0 { line(app, "###p_accessed", "Accessed", date_text(app, p.accessed), em) }
		line(app, "###p_perm", PERMISSIONS_WORD, p.permissions, em, mono = true)
		line(app, "###p_owner", "Owner", p.owner, em, mono = true)
		ui.spacer(ui.px(em * 0.3))
	}
}

// The runs of a source text in its language's colours: the theme's code colours (ui.code_color, as the toolkit's
// code_runs), the spans worked out on the worker (not lexed again each frame).
@(private = "file")
code_runs :: proc(text: string, spans: []syntax.Span) -> []ui.Rich_Run {
	runs := make([dynamic]ui.Rich_Run, context.temp_allocator)
	at := 0
	for sp in spans {
		if sp.start > at { append(&runs, ui.Rich_Run{text = text[at:sp.start]}) }
		append(&runs, ui.Rich_Run{text = text[sp.start:sp.end], style = {color = sp.class == .Plain ? ui.Color{} : ui.code_color(sp.class), italic = sp.class == .Comment}})
		at = sp.end
	}
	if at < len(text) { append(&runs, ui.Rich_Run{text = text[at:]}) }
	return runs[:]
}
