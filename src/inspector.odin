package classeur

// The inspector, File Pilot's (Space): a pane at the right of the panel that shows what the cursor is on. A picture
// large, a text file's beginning in the monospaced font, a folder's content, any other file what it is. What it shows
// is read on the workers when the cursor stops on it; only the last one asked is kept.

import "core:fmt"
import config "gt:config"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
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
	tex:      render.Texture,
	has_tex:  bool,
	size:     [2]int,
	listing:  fs.Listing,
	props:    fs.Properties,   // owned strings: what the system says of it besides its size and date
	has_props: bool,
}

@(private = "file")
Inspect_Job :: struct {
	app:     ^App,
	serial:  u64,
	path:    string,           // owned
	kind:    Inspect_Kind,
	text:    string,           // owned until taken
	spans:   [dynamic]syntax.Span,   // owned until taken
	language: bool,
	rgba:    []u8,
	size:    [2]int,
	listing: fs.Listing,
	props:   fs.Properties,    // owned strings
	has_props: bool,
}

inspector_free :: proc(app: ^App) {
	insp := &app.inspector
	inspector_clear(app)
	delete(insp.path)
	insp.path = ""
}

@(private = "file")
inspector_clear :: proc(app: ^App) {
	insp := &app.inspector
	delete(insp.text)
	insp.text = ""
	delete(insp.spans)
	insp.spans, insp.language = nil, false
	if insp.has_tex { render.destroy_texture(&app.shared.r, insp.tex) }
	insp.has_tex = false
	fs.listing_destroy(&insp.listing)
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
	job^ = {app = app, serial = insp.serial, path = strings.clone(path)}
	switch {
	case e.kind == .Directory:                                job.kind = .Folder
	case e.kind == .File && thumb_mime(e.name) != "":         job.kind = .Picture
	case e.kind == .File && looks_textual(e.name, e.flags):   job.kind = .Text
	case:                                                     job.kind = .Other
	}
	pool_submit(&app.pool, inspect_run, job)
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
	case .Picture:
		info, ok := fs.stat(job.path)
		if !ok || info.size > THUMB_MAX_BYTES { job.kind = .Other; return }
		bytes, err := os.read_entire_file(job.path, context.temp_allocator)
		if err != nil { job.kind = .Other; return }
		img, decoded := platform.clipboard_image_decode(thumb_mime(job.path), bytes)
		if !decoded { job.kind = .Other; return }
		defer delete(img.rgba)
		job.rgba, job.size = shrink(img.rgba, img.size, INSPECTOR_PICTURE_PX)
	case .Text:
		f, err := os.open(job.path)
		if err != nil { job.kind = .Other; return }
		defer os.close(f)
		buf := make([]u8, INSPECTOR_TEXT_BYTES, context.temp_allocator)
		n, _ := os.read(f, buf)
		text := string(buf[:max(n, 0)])
		for len(text) > 0 && !utf8.valid_string(text) { text = text[:len(text) - 1] }   // (cut inside a character)
		if strings.index_byte(text, 0) >= 0 || (n > 0 && len(text) == 0) { job.kind = .Other; return }
		job.text = strings.clone(text)
		if l, ok := syntax.language_of_file(job.path); ok {
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
		insp.has_tex, insp.size = true, job.size
	case .Text:
		insp.text, job.text = job.text, ""
		insp.spans, job.spans = job.spans, nil
		insp.language = job.language
	case .Folder:
		insp.listing, job.listing = job.listing, {}
		order := make([]u32, len(insp.listing.entries), context.temp_allocator)
		for i in 0 ..< len(order) { order[i] = u32(i) }
		sorted := make([dynamic]fs.Entry, context.temp_allocator)
		fs.sort_order(insp.listing.entries[:], order, app.default_sort)
		for i in order { append(&sorted, insp.listing.entries[i]) }
		copy(insp.listing.entries[:], sorted[:])
	case .Other, .None:
	}
	app_frames(app)
}

// The pane, beside the list of the panel that has the keyboard.
inspector_build :: proc(app: ^App, t: ^Tab, em: f32) {
	insp := &app.inspector
	e := folder_cursor_entry(&t.folder)
	if e != nil { inspector_ask(app, fs.join(t.path, e.name, context.temp_allocator), e^) }
	// (its edge, the toolkit's: dragged, folded to a strip, Enter and the arrows)
	r := ui.pane_split("###insp_split", .X, &insp.pane, inspector_pane_options(app))
	if r.size <= 0 { return }
	ui.next({width = ui.px(r.size * ui.scale()), height = ui.fill(), axis = .Y})
	// (no line of its own: the edge that drags it is the line between it and the list)
	box := ui.build_box({.Clip}, "###inspector")
	if ui.parent(box) {
		if e == nil { return }
		// what it is: its icon, its name, its size and date
		ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 3.2))})
		if ui.row(.Center, {.Draw_Side_Bottom}, "###insp_head") {
			ui.spacer(ui.px(em * 0.6))
			entry_glyph(app, t.path, e^, em * 2.4)
			ui.spacer(ui.px(em * 0.4))
			ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
			if ui.column() {
				ui.spacer(ui.fill())
				ui.next({width = ui.fill(), height = ui.px(em * 1.4)})
				ui.label(fmt.tprintf("%s###name", shown_text(fs.base(e.name))))
				if ui.tags("weak") {
					size := e.size >= 0 ? size_text(e.size) : ""
					if m, ok := measure_of(app, t, e^); ok { size = fmt.tprintf("%s · %d folders · %d files", size_text(m.bytes), m.folders, m.files) }
					ui.next({width = ui.fill(), height = ui.px(em * 1.3), font_size = em * 0.86})
					ui.label(fmt.tprintf("%s · %s · %s###meta", type_text(e^), size, date_text(app, e.mtime)))
				}
				ui.spacer(ui.fill())
			}
			if ui.tags("weak") { if icon_action(app, "insp_close", lucide.X, command_tip(app, "inspector"), em) { act_inspector(app) } }
			ui.spacer(ui.px(em * 0.3))
		}
		if insp.ready && insp.has_props { inspector_props(app, t, e^, em) }
		ui.next({width = ui.fill(), height = ui.fill()})
		if !insp.ready {
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(em * 4), text_align = .Center})
				ui.label("Reading…###insp_wait")
			}
			return
		}
		switch insp.kind {
		case .Picture:
			d := ui.frame_new(Inspect_Picture)
			d^ = {insp.tex, {f32(insp.size.x), f32(insp.size.y)}, corner_k()}
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.row() {
				ui.spacer(ui.px(em * 0.8))
				ui.next({width = ui.fill(), height = ui.fill()})
				ui.custom("###insp_pic", inspect_picture_draw, d)
				ui.spacer(ui.px(em * 0.8))
			}
		case .Text:
			if ui.scroll_y("###insp_text") {
				ui.spacer(ui.px(em * 0.5))
				ui.next({width = ui.fill()})
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
			}
		case .Folder:
			if ui.scroll_y("###insp_folder") {
				for x, i in insp.listing.entries {
					if !app.show_hidden && .Hidden in x.flags { continue }
					ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.0))})
					if ui.row(.Center, {}, fmt.tprintf("###insp_e%d", i)) {
						ui.spacer(ui.px(em * 0.8))
						entry_glyph(app, insp.path, x, em * 1.8)
						ui.spacer(ui.px(em * 0.4))
						ui.next({width = ui.fill(), height = ui.pct(1)})
						ui.label(fmt.tprintf("%s###n", shown_text(x.name)))
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

@(private = "file")
Inspect_Picture :: struct {
	tex:  render.Texture,
	size: [2]f32,
	round: f32,   // corner_k(): the settings' rounding
}

@(private = "file")
inspect_picture_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Inspect_Picture)(user)
	r := b.rect
	room := r.max - r.min
	if d.size.x <= 0 || d.size.y <= 0 || room.x <= 0 || room.y <= 0 { return }
	scale := min(room.x / d.size.x, room.y / d.size.y, 1)
	sz := d.size * scale
	at := r.min + (room - sz) * 0.5
	draw.image(dc, d.tex, {at, at + sz}, radius = 3 * d.round)
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

// The runs of a source text in its language's colours (the theme's: keywords in the accent, strings good, comments weak,
// types and numbers warm, calls the text's).
@(private = "file")
code_runs :: proc(text: string, spans: []syntax.Span) -> []ui.Rich_Run {
	colors := [syntax.Class]ui.Color{
		.Plain = {}, .Keyword = ui.color("accent"), .Str = ui.color("good text"), .Comment = ui.color("weak text"),
		.Func = {}, .Type = ui.color("warn text"),
	}
	runs := make([dynamic]ui.Rich_Run, context.temp_allocator)
	at := 0
	for sp in spans {
		if sp.start > at { append(&runs, ui.Rich_Run{text = text[at:sp.start]}) }
		append(&runs, ui.Rich_Run{text = text[sp.start:sp.end], style = {color = colors[sp.class], bold = sp.class == .Func}})
		at = sp.end
	}
	if at < len(text) { append(&runs, ui.Rich_Run{text = text[at:]}) }
	return runs[:]
}
