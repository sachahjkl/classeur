package classeur

// The inspector, File Pilot's (Space): a pane at the right of the panel that shows what the cursor is on. A picture
// large, a text file's beginning in the monospaced font, a folder's content, any other file what it is. What it shows
// is read on the workers when the cursor stops on it; only the last one asked is kept.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import "gt:draw"
import lucide "gt:lucide"
import "gt:platform"
import "gt:render"
import "gt:ui"
import "fs"

INSPECTOR_TEXT_BYTES :: 64 * 1024
INSPECTOR_PICTURE_PX :: 1600
INSPECTOR_MIN_PX     :: 220

Inspect_Kind :: enum u8 { None, Picture, Text, Folder, Other }

Inspector :: struct {
	open:     bool,
	width_px: f32,             // logical pixels
	path:     string,          // owned: what is shown (or asked)
	serial:   u64,             // the ask the pane waits for
	ready:    bool,
	kind:     Inspect_Kind,
	text:     string,          // owned
	tex:      render.Texture,
	has_tex:  bool,
	size:     [2]int,
	listing:  fs.Listing,
}

@(private = "file")
Inspect_Job :: struct {
	app:     ^App,
	serial:  u64,
	path:    string,           // owned
	kind:    Inspect_Kind,
	text:    string,           // owned until taken
	rgba:    []u8,
	size:    [2]int,
	listing: fs.Listing,
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
	if insp.has_tex { render.destroy_texture(&app.shared.r, insp.tex) }
	insp.has_tex = false
	fs.listing_destroy(&insp.listing)
	insp.ready, insp.kind = false, .None
}

act_inspector :: proc(app: ^App) {
	insp := &app.inspector
	insp.open = !insp.open
	if insp.width_px <= 0 { insp.width_px = 380 }
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
	case .Other, .None:
	}
}

@(private = "file")
inspect_free :: proc(job: ^Inspect_Job) {
	delete(job.path)
	delete(job.text)
	delete(job.rgba)
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
	switch job.kind {
	case .Picture:
		insp.tex = render.create_texture_rgba(&app.shared.r, job.size.x, job.size.y)
		render.update_texture_rgba(&app.shared.r, insp.tex, 0, 0, job.size.x, job.size.y, job.rgba)
		insp.has_tex, insp.size = true, job.size
	case .Text:
		insp.text, job.text = job.text, ""
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
	ui.next({width = ui.px(insp.width_px * ui.scale()), height = ui.fill(), axis = .Y})
	box := ui.build_box({.Clip, .Draw_Side_Left}, "###inspector")
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
			if ui.tags("weak") { if icon_action(app, "insp_close", lucide.X, command_tip("inspector"), em) { act_inspector(app) } }
			ui.spacer(ui.px(em * 0.3))
		}
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
						ui.paragraph(fmt.tprintf("%s###insp_body", shown_text(insp.text)))
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
