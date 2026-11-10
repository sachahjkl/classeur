package classeur

// The icons of files and folders are the system's (gui_toolkit's desktop.file_icon): the person's icon theme on Linux,
// the shell's on Windows, as their file manager shows them. A picture is made once per key and size, on a worker (an
// SVG of the theme is rendered then), and kept as a texture; the rows ask for it each frame. A key: a file's extension
// (its type decides its icon), a person's folder or a volume its path (they have icons of their own), any other folder
// "folder". The logo alone is drawn.

import "core:fmt"
import "core:math"
import "core:strings"
import "gt:desktop"
import "gt:draw"
import lucide "gt:lucide"
import "gt:render"
import "gt:ui"
import "fs"

ICONS_KEPT :: 600

Sys_Icon :: struct {
	state: Thumb_State,
	tex:   render.Texture,
	size:  [2]int,
	used:  u64,
}

@(private = "file")
Icon_Job :: struct {
	app:    ^App,
	key:    string,   // owned: the cache's key
	path:   string,   // owned
	folder: bool,
	px:     int,
	icon:   desktop.File_Icon,
	ok:     bool,
}

// The key of the icon of `path`: what decides its picture. A file's is the toolkit's (desktop.file_icon_key: its type
// from its name, or the file itself when it has an icon of its own), kept per name; a person's folder, a volume and the
// root have their own icons, any other folder is "folder".
@(private = "file")
icon_key :: proc(app: ^App, path: string, folder: bool, px: int) -> string {
	if folder {
		special := path == app.home || fs.is_root(path)
		for p in app.places { if p.path == path { special = true } }
		for v in app.volumes { if v.path == path { special = true } }
		return special ? fmt.tprintf("dir:%s@%d", path, px) : fmt.tprintf("dir@%d", px)
	}
	name := fs.base(path)
	key, known := app.icon_keys[name]
	if !known {
		if len(app.icon_keys) > ICON_KEYS_KEPT { icon_keys_free(app) }
		key = desktop.file_icon_key(path, false, context.temp_allocator)
		// (a file with an icon of its own, a program's on Windows: its key is its path, not to be kept by its name)
		if strings.has_prefix(key, "file:") { return fmt.tprintf("%s@%d", key, px) }
		key = strings.clone(key)
		app.icon_keys[strings.clone(name)] = key
	}
	return fmt.tprintf("%s@%d", key, px)
}

ICON_KEYS_KEPT :: 20000

icon_keys_free :: proc(app: ^App) {
	for k, v in app.icon_keys { delete(k); delete(v) }
	clear(&app.icon_keys)
}

// The sizes the pictures are made at: a size asked is the next one up, drawn smaller. A zoom that moves smoothly asks
// every size on its way: made at these alone, a step reuses the pictures of the last and asks a few new ones.
ICON_SIZES := [?]int{16, 20, 24, 32, 40, 48, 64, 96, 128, 192, 256}

icon_size_for :: proc(px: int) -> int {
	for s in ICON_SIZES { if s >= px { return s } }
	return ICON_SIZES[len(ICON_SIZES) - 1]
}

// The system's icon of `path` at `px` pixels (made at icon_size_for(px)), if it is made; else it is asked (once), and
// meanwhile the picture of another size made already stands in (`ready` false then): no box goes blank as the zoom moves.
sys_icon :: proc(app: ^App, path: string, folder: bool, px: int) -> (ic: ^Sys_Icon, ready: bool, failed: bool) {
	made := icon_size_for(px)
	key := icon_key(app, path, folder, made)
	if c, ok := &app.icons_cache[key]; ok {
		c.used = app.frame
		if c.state == .Ready { return c, true, false }
		stand, other_failed := icon_stand_in(app, key, made)
		return stand, false, c.state == .Failed || other_failed
	}
	app.icons_cache[strings.clone(key)] = {state = .Asked, used = app.frame}
	job := new(Icon_Job)
	job^ = {app = app, key = strings.clone(key), path = strings.clone(path), folder = folder, px = made}
	pool_submit(&app.thumb_pool, icon_run, job)
	stand, other_failed := icon_stand_in(app, key, made)
	return stand, false, other_failed
}

// The picture of the same icon at the nearest size made already (nil: none).
@(private = "file")
icon_stand_in :: proc(app: ^App, key: string, made: int) -> (best: ^Sys_Icon, failed: bool) {
	at := strings.last_index_byte(key, '@')
	if at < 0 { return }
	best_gap := max(int)
	for s in ICON_SIZES {
		if s == made { continue }
		c, ok := &app.icons_cache[fmt.tprintf("%s@%d", key[:at], s)]
		if !ok { continue }
		// (a size that failed: this one will too, the system has no picture for it)
		if c.state == .Failed { failed = true }
		if c.state != .Ready { continue }
		if gap := abs(s - made); gap < best_gap { best, best_gap = c, gap }
	}
	if best != nil { best.used = app.frame }
	return
}

@(private = "file")
icon_run :: proc(data: rawptr) {
	job := (^Icon_Job)(data)
	job.icon, job.ok = desktop.file_icon(job.path, job.folder, job.px)
	if !ui.post(&job.app.main.state, icon_done, job) { icon_free(job) }
}

@(private = "file")
icon_free :: proc(job: ^Icon_Job) {
	delete(job.key)
	delete(job.path)
	desktop.file_icon_destroy(&job.icon)
	free(job)
}

@(private = "file")
icon_done :: proc(data: rawptr, word: u64) {
	job := (^Icon_Job)(data)
	defer icon_free(job)
	app := job.app
	ic, ok := &app.icons_cache[job.key]
	if !ok { return }
	if !job.ok || job.icon.size.x <= 0 {
		ic.state = .Failed
		return
	}
	r := &app.shared.r
	ic.tex = render.create_texture_rgba(r, job.icon.size.x, job.icon.size.y)
	render.update_texture_rgba(r, ic.tex, 0, 0, job.icon.size.x, job.icon.size.y, job.icon.rgba)
	ic.size, ic.state = job.icon.size, .Ready
	app_frames(app)
}

// Each frame: the pictures least used go when too many are kept.
icons_tidy :: proc(app: ^App) {
	if len(app.icons_cache) <= ICONS_KEPT { return }
	Old :: struct { key: string, used: u64 }
	all := make([dynamic]Old, context.temp_allocator)
	for k, ic in app.icons_cache { if ic.state != .Asked { append(&all, Old{k, ic.used}) } }
	limit := app.frame
	for o in all { limit = min(limit, o.used) }
	cut := limit + (app.frame - limit) / 4
	for o in all {
		if o.used > cut { continue }
		key, ic := delete_key(&app.icons_cache, o.key)
		if ic.state == .Ready { render.destroy_texture(&app.shared.r, ic.tex) }
		delete(key)
	}
}

icons_free :: proc(app: ^App) {
	for k, ic in app.icons_cache {
		if ic.state == .Ready { render.destroy_texture(&app.shared.r, ic.tex) }
		delete(k)
	}
	delete(app.icons_cache)
	icon_keys_free(app)
	delete(app.icon_keys)
}

@(private = "file")
Icon_Draw :: struct {
	tex:  render.Texture,
	size: [2]f32,
	px:   f32,
}

// The picture centred in its box, `px` pixels on its longer side, on whole pixels (made at that size: sharp).
@(private = "file")
icon_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Icon_Draw)(user)
	r := b.rect
	scale := d.px / max(d.size.x, d.size.y)
	sz := d.size * (abs(scale - 1) < 0.001 ? 1 : scale)
	sz = {math.round(sz.x), math.round(sz.y)}
	at := (r.min + r.max - sz) * 0.5
	at = {math.round(at.x), math.round(at.y)}
	draw.image(dc, d.tex, {at, at + sz})
}

// The system's icon of `path` in a box `width` wide (a square of about 80 % of it, in whole pixels).
path_icon :: proc(app: ^App, path: string, folder: bool, width: f32) {
	px := max(16, int(math.round(width * 0.8)))
	ui.next({width = ui.px(width), height = ui.pct(1)})
	ic, ready, failed := sys_icon(app, path, folder, px)
	if ic != nil {
		// (made at its size: never larger than the theme drew it; a stand-in at another size: scaled to fit)
		side := f32(max(ic.size.x, ic.size.y))
		d := ui.frame_new(Icon_Draw)
		d^ = {ic.tex, {f32(ic.size.x), f32(ic.size.y)}, ready ? min(f32(px), side) : f32(px)}
		ui.custom("###icon", icon_draw, d)
	} else if failed {
		// (no picture of the system's: no icon theme, a type it does not know): Lucide's folder or file
		ui.next_merge({font = app.icons, text_align = .Center, font_size = math.round(width * 0.62)})
		if ui.tags("weak") { ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###icon", folder ? lucide.FOLDER : lucide.FILE)) }
	} else {
		ui.build_box({}, "###icon")   // (the first time it is asked: an instant)
	}
}

// The icon of an entry of the folder `dir`.
entry_glyph :: proc(app: ^App, dir: string, e: fs.Entry, width: f32) {
	path_icon(app, fs.join(dir, e.name, context.temp_allocator), e.kind == .Directory, width)
}

// The colours of the logo (sRGB): a folder in the logo's blues.
LOGO_BACK  :: 0x1f4f8aff
LOGO_FRONT :: 0x4f97e0ff

@(private = "file")
Logo_Draw :: struct { back, front: ui.Color }

// classeur's mark, drawn: a folder, its back with the tab, its front lower.
logo_icon :: proc(width: f32) {
	d := ui.frame_new(Logo_Draw)
	d^ = {draw.hex(LOGO_BACK), draw.hex(LOGO_FRONT)}
	ui.next({width = ui.px(width), height = ui.pct(1)})
	ui.custom("###logo", logo_draw, d)
}

@(private = "file")
logo_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Logo_Draw)(user)
	r := b.rect
	s := min(r.max.x - r.min.x, r.max.y - r.min.y) * 0.72
	o := (r.min + r.max) * 0.5 - s * 0.5
	rad := max(1, s * 0.08)
	draw.rect(dc, {{o.x, o.y + s * 0.10}, {o.x + s * 0.45, o.y + s * 0.30}}, d.back, radius = rad)
	draw.rect(dc, {{o.x, o.y + s * 0.20}, {o.x + s, o.y + s * 0.90}}, d.back, radius = rad)
	draw.rect(dc, {{o.x, o.y + s * 0.34}, {o.x + s, o.y + s * 0.90}}, d.front, radius = rad)
}
