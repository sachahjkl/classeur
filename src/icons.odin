package classeur

// The icons of the entries, as File Pilot shows them: filled, in colour. A folder is drawn (a yellow folder: its back
// with the tab, its front a lighter yellow); a file of a known kind is its Lucide icon in the colour of its kind; any
// other file a white page with its corner folded.

import "gt:draw"
import "core:fmt"
import "gt:ui"
import "fs"

Icon_Kind :: enum u8 {
	Folder,
	Folder_Link,
	Page,      // a file of no known kind
	Glyph,     // a Lucide icon in a colour
}

// The colours of the drawn icons (sRGB 0xRRGGBBAA).
FOLDER_BACK  :: 0xd9a514ff
FOLDER_FRONT :: 0xf4c542ff
PAGE_FACE    :: 0xe8eaedff
PAGE_FOLD    :: 0xa9adb3ff
LINK_MARK    :: 0x4f9de8ff

@(private = "file")
Icon_Draw :: struct {
	kind:  Icon_Kind,
	color: ui.Color,
}

// A kind of file: its filled icon and its colour (sRGB).
@(private = "file")
File_Look :: struct { exts: []string, glyph: string, color: u32 }

@(private = "file", rodata)
FILE_LOOKS := [?]File_Look{
	{{"png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "avif", "heic", "tif", "tiff", "jxl", "psd", "xcf", "kra"}, PH_FILE_IMAGE, 0x35b1e0ff},
	{{"mp3", "flac", "wav", "ogg", "m4a", "opus", "aac", "wma", "aiff", "mid"}, PH_FILE_AUDIO, 0xf2853cff},
	{{"mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg"}, PH_FILE_VIDEO, 0xa774f2ff},
	{{"zip", "tar", "gz", "xz", "bz2", "7z", "rar", "zst", "tgz", "lz4", "cab", "iso", "dmg", "deb", "rpm"}, PH_FILE_ZIP, 0xe6ae3aff},
	{{"xls", "xlsx", "ods", "numbers"}, PH_FILE_XLS, 0x3fb26bff},
	{{"csv", "tsv"}, PH_FILE_CSV, 0x3fb26bff},
	{{"pdf"}, PH_FILE_PDF, 0xe9605fff},
	{{"doc", "docx", "odt", "rtf", "pages"}, PH_FILE_DOC, 0x4f8fe8ff},
	{{"exe", "msi", "appimage", "bat", "cmd", "com", "ps1", "sh", "fish"}, PH_TERMINAL_WINDOW, 0x8fd16aff},
	{{"js", "mjs", "jsx"}, PH_FILE_JS, 0xe8c547ff},
	{{"ts", "tsx"}, PH_FILE_TS, 0x4f8fe8ff},
	{{"py"}, PH_FILE_PY, 0x5aa2ecff},
	{{"rs"}, PH_FILE_RS, 0xe08a5aff},
	{{"html", "htm"}, PH_FILE_HTML, 0xec7a4fff},
	{{"css", "scss"}, PH_FILE_CSS, 0x5aa2ecff},
	{{"sql"}, PH_FILE_SQL, 0xd9a3f0ff},
	{{"odin", "c", "h", "cc", "cpp", "hpp", "go", "java", "kt", "swift", "rb", "nix", "lua", "zig", "json", "toml", "yaml", "yml",
	  "xml", "cs", "php", "wgsl", "glsl", "hlsl"}, PH_FILE_CODE, 0x5aa2ecff},
	{{"md", "markdown"}, PH_FILE_MD, 0xc9cdd3ff},
	{{"txt", "log", "ini", "cfg", "conf", "rst", "tex", "org", "epub"}, PH_FILE_TXT, 0xc9cdd3ff},
}

// The filled icon of a file's kind, from its extension; ok false: none (a page is drawn).
file_look :: proc(name: string) -> (glyph: string, color: u32, ok: bool) {
	ext := fs.extension(name)
	if ext == "" || len(ext) > 16 { return }
	buf: [16]u8
	for i in 0 ..< len(ext) { c := ext[i]; buf[i] = c >= 'A' && c <= 'Z' ? c + 32 : c }
	lower := string(buf[:len(ext)])
	for look in FILE_LOOKS { for x in look.exts { if x == lower { return look.glyph, look.color, true } } }
	return
}

// The icon of an entry, `size` wide and high (a square in the row).
entry_glyph :: proc(app: ^App, e: fs.Entry, size: f32) {
	switch {
	case e.kind == .Directory:
		drawn_icon(.Link in e.flags ? .Folder_Link : .Folder, size)
	case e.kind == .File && .Link not_in e.flags:
		if g, color, ok := file_look(e.name); ok {
			filled(app, g, size, draw.hex(color))
			return
		}
		drawn_icon(.Page, size)
	case:
		drawn_icon(.Page, size)
	}
}

// A filled icon of Phosphor, `width` wide, in `color`.
filled :: proc(app: ^App, g: string, width: f32, color: Maybe(ui.Color) = nil) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = app.filled, font_size = width * 0.62, text_align = .Center, fg = color})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###f%d", g, ui.parent_box().child_count))
}

// A drawn icon, `size` wide.
drawn_icon :: proc(kind: Icon_Kind, size: f32, color := ui.Color{}) {
	d := ui.frame_new(Icon_Draw)
	d^ = {kind, color}
	ui.next({width = ui.px(size), height = ui.pct(1)})
	ui.custom("###icon", icon_draw, d)
}

@(private = "file")
icon_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Icon_Draw)(user)
	r := b.rect
	w := r.max.x - r.min.x
	s := min(w, r.max.y - r.min.y) * 0.72   // (the icon in its box, a margin around it)
	c := (r.min + r.max) * 0.5
	o := c - s * 0.5
	switch d.kind {
	case .Folder, .Folder_Link:
		// the back with its tab, then the front, lower
		back := d.color != {} ? d.color * 0.75 : draw.hex(FOLDER_BACK)
		front := d.color != {} ? d.color : draw.hex(FOLDER_FRONT)
		rad := max(1, s * 0.07)
		draw.rect(dc, {{o.x, o.y + s * 0.10}, {o.x + s * 0.45, o.y + s * 0.30}}, back, radius = rad)
		draw.rect(dc, {{o.x, o.y + s * 0.20}, {o.x + s, o.y + s * 0.90}}, back, radius = rad)
		draw.rect(dc, {{o.x, o.y + s * 0.34}, {o.x + s, o.y + s * 0.90}}, front, radius = rad)
		if d.kind == .Folder_Link {
			m := s * 0.34
			draw.rect(dc, {{o.x + s - m, o.y + s * 0.90 - m}, {o.x + s, o.y + s * 0.90}}, draw.hex(LINK_MARK), radius = m * 0.25)
		}
	case .Page:
		x0, x1 := o.x + s * 0.16, o.x + s * 0.84
		fold := s * 0.24
		draw.rect(dc, {{x0, o.y + fold}, {x1, o.y + s}}, draw.hex(PAGE_FACE), radius = max(1, s * 0.05))
		draw.rect(dc, {{x0, o.y}, {x1 - fold, o.y + fold + 1}}, draw.hex(PAGE_FACE), radius = max(1, s * 0.05))
		draw.triangle(dc, {x1 - fold, o.y}, {x1, o.y + fold}, {x1 - fold, o.y + fold}, draw.hex(PAGE_FOLD))
	case .Glyph:
	}
}
