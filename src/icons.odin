package classeur

// The icons of the entries, as File Pilot shows them: filled, in colour. A folder is drawn (a yellow folder: its back
// with the tab, its front a lighter yellow); a file of a known kind is its Lucide icon in the colour of its kind; any
// other file a white page with its corner folded.

import "gt:draw"
import lucide "gt:lucide"
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

// The colour of a kind of file, by its Lucide icon.
@(private = "file")
glyph_color :: proc(g: string) -> u32 {
	switch g {
	case lucide.FILE_IMAGE:       return 0x3fb8c9ff
	case lucide.FILE_MUSIC:       return 0xf07a3aff
	case lucide.FILE_VIDEO_2:     return 0xa66cf0ff
	case lucide.FILE_ARCHIVE:     return 0xe0a530ff
	case lucide.FILE_SPREADSHEET: return 0x3fb26bff
	case lucide.PACKAGE:          return 0xe9605fff
	case lucide.FILE_CODE:        return 0x5aa2ecff
	case lucide.FILE_SYMLINK:     return 0x4f9de8ff
	}
	return 0xcfd3d8ff
}

// The icon of an entry, `size` wide and high (a square in the row).
entry_glyph :: proc(app: ^App, e: fs.Entry, size: f32) {
	switch {
	case e.kind == .Directory:
		drawn_icon(.Link in e.flags ? .Folder_Link : .Folder, size)
	case:
		g := entry_icon(e)
		if g == lucide.FILE {
			drawn_icon(.Page, size)
		} else {
			glyph(app, g, size, draw.hex(glyph_color(g)))
		}
	}
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
