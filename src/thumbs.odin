package classeur

// The thumbnails of the grid: a picture file is read and decoded on a pool of its own (a photo of 24 megapixels takes a
// fifth of a second), made at most THUMB_PX on its longer side with a box filter, then given to the interface's thread,
// which makes its texture. Only the cards built ask for theirs; the textures not used for a while go when more than
// THUMBS_KEPT are kept.

import "core:os"
import "core:strings"
import "gt:platform"
import "gt:render"
import "gt:ui"
import "fs"

THUMB_THREADS   :: 2
THUMB_PX        :: 256
THUMBS_KEPT     :: 400
THUMB_MAX_BYTES :: 64 * 1024 * 1024   // a larger file is not read for its thumbnail

Thumb_State :: enum u8 { Asked, Ready, Failed }

Thumb :: struct {
	state: Thumb_State,
	tex:   render.Texture,
	size:  [2]int,
	used:  u64,   // the frame it was last drawn in
}

@(private = "file")
Thumb_Job :: struct {
	app:  ^App,
	path: string,   // owned
	rgba: []u8,     // owned until the texture is made
	size: [2]int,
	ok:   bool,
}

// The MIME type the decoder reads for this name, "" for none.
thumb_mime :: proc(name: string) -> string {
	ext := fs.extension(name)
	if len(ext) > 5 { return "" }
	buf: [5]u8
	for i in 0 ..< len(ext) { c := ext[i]; buf[i] = c >= 'A' && c <= 'Z' ? c + 32 : c }
	switch string(buf[:len(ext)]) {
	case "png":         return "image/png"
	case "jpg", "jpeg": return "image/jpeg"
	case "bmp":         return "image/bmp"
	}
	return ""
}

// The thumbnail of `path` if it is ready; else it is asked (once).
thumb_get :: proc(app: ^App, path: string) -> (^Thumb, bool) {
	if th, ok := &app.thumbs[path]; ok {
		th.used = app.frame
		return th, th.state == .Ready
	}
	app.thumbs[strings.clone(path)] = {state = .Asked, used = app.frame}
	job := new(Thumb_Job)
	job^ = {app = app, path = strings.clone(path)}
	pool_submit(&app.thumb_pool, thumb_run, job)
	return nil, false
}

@(private = "file")
thumb_run :: proc(data: rawptr) {
	job := (^Thumb_Job)(data)
	defer if !ui.post(&job.app.main.state, thumb_done, job) { thumb_free(job) }
	info, ok := fs.stat(job.path)
	if !ok || info.size <= 0 || info.size > THUMB_MAX_BYTES { return }
	bytes, err := os.read_entire_file(job.path, context.temp_allocator)
	if err != nil { return }
	img, decoded := platform.clipboard_image_decode(thumb_mime(job.path), bytes)
	if !decoded { return }
	defer delete(img.rgba)
	job.rgba, job.size = shrink(img.rgba, img.size, THUMB_PX)
	job.ok = true
}

// The picture at most `side` on its longer side: each pixel the mean of the block it covers.
shrink :: proc(rgba: []u8, size: [2]int, side: int) -> ([]u8, [2]int) {
	w, h := size.x, size.y
	scale := max(f32(w), f32(h)) / f32(side)
	if scale <= 1 {
		out := make([]u8, len(rgba))
		copy(out, rgba)
		return out, size
	}
	ow, oh := max(1, int(f32(w) / scale)), max(1, int(f32(h) / scale))
	out := make([]u8, ow * oh * 4)
	for y in 0 ..< oh {
		y0, y1 := y * h / oh, max(y * h / oh + 1, (y + 1) * h / oh)
		for x in 0 ..< ow {
			x0, x1 := x * w / ow, max(x * w / ow + 1, (x + 1) * w / ow)
			sum: [4]u32
			for sy in y0 ..< y1 {
				row := rgba[(sy * w) * 4:]
				for sx in x0 ..< x1 {
					p := row[sx * 4:]
					sum += {u32(p[0]), u32(p[1]), u32(p[2]), u32(p[3])}
				}
			}
			n := u32((y1 - y0) * (x1 - x0))
			o := out[(y * ow + x) * 4:]
			o[0], o[1], o[2], o[3] = u8(sum[0] / n), u8(sum[1] / n), u8(sum[2] / n), u8(sum[3] / n)
		}
	}
	return out, {ow, oh}
}

@(private = "file")
thumb_free :: proc(job: ^Thumb_Job) {
	delete(job.path)
	delete(job.rgba)
	free(job)
}

@(private = "file")
thumb_done :: proc(data: rawptr, word: u64) {
	job := (^Thumb_Job)(data)
	defer thumb_free(job)
	app := job.app
	th, ok := &app.thumbs[job.path]
	if !ok { return }
	if !job.ok {
		th.state = .Failed
		return
	}
	r := &app.shared.r
	th.tex = render.create_texture_rgba(r, job.size.x, job.size.y)
	render.update_texture_rgba(r, th.tex, 0, 0, job.size.x, job.size.y, job.rgba)
	th.size, th.state = job.size, .Ready
	app_frames(app)
}

// Each frame: the textures least used go when too many are kept.
thumbs_tidy :: proc(app: ^App) {
	if len(app.thumbs) <= THUMBS_KEPT { return }
	Old :: struct { key: string, used: u64 }
	all := make([dynamic]Old, context.temp_allocator)
	for k, th in app.thumbs { if th.state != .Asked { append(&all, Old{k, th.used}) } }
	// (the oldest quarter)
	limit := app.frame
	for o in all { limit = min(limit, o.used) }
	cut := limit + (app.frame - limit) / 4
	for o in all {
		if o.used > cut { continue }
		key, th := delete_key(&app.thumbs, o.key)
		if th.state == .Ready { render.destroy_texture(&app.shared.r, th.tex) }
		delete(key)
	}
}

thumbs_free :: proc(app: ^App) {
	for k, th in app.thumbs {
		if th.state == .Ready { render.destroy_texture(&app.shared.r, th.tex) }
		delete(k)
	}
	delete(app.thumbs)
}
