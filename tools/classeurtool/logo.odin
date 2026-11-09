package classeurtool

// logo: classeur's mark, drawn by the toolkit's paint package (the same bytes on every system). A folder seen from the
// front: its back with the tab, two sheets standing in it, and the front panel, lower, parted from them by a gap; each
// part a soft vertical gradient with a darker edge. Small sizes drop the second sheet (detail_for).
// assets/logo.png (1024 px) and the sizes the program and the site embed.

import "core:fmt"
import "core:os"
import paint "gt:paint"

LOGO_DIR    :: "assets"
LOGO_MASTER :: 1024
LOGO_SIZES  :: [?]int{16, 32, 64, 128, 256}
// The drawing's own units: a square of LOGO_UNITS, scaled to the canvas.
LOGO_UNITS  :: 512.0
// The transparent space around the front panel, and the width of an edge, in units.
LOGO_GAP    :: 18.0
LOGO_EDGE   :: 12.0
// Small sizes are drawn from a master this many times larger, in one step of the cubic filter at most this factor.
LOGO_SHRINK_STEP :: 4

// The colours: top and bottom of each gradient, and the edges.
BACK_TOP     :: 0x2F6FB8
BACK_BOTTOM  :: 0x1F4F8A
BACK_EDGE    :: 0x163A66
SHEET_TOP    :: 0xFFFFFF
SHEET_BOTTOM :: 0xE4E9F0
SHEET_EDGE   :: 0x8A97A8
FRONT_TOP    :: 0x6FB0F2
FRONT_BOTTOM :: 0x3F86D6
FRONT_EDGE   :: 0x245C9C

// A rectangle with rounded corners as a path of its own.
@(private = "file")
rounded :: proc(p: ^paint.Path, x0, y0, x1, y1, r: f32) {
	paint.move_to(p, x0 + r, y0)
	paint.line_to(p, x1 - r, y0)
	paint.quad_to(p, x1, y0, x1, y0 + r)
	paint.line_to(p, x1, y1 - r)
	paint.quad_to(p, x1, y1, x1 - r, y1)
	paint.line_to(p, x0 + r, y1)
	paint.quad_to(p, x0, y1, x0, y1 - r)
	paint.line_to(p, x0, y0 + r)
	paint.quad_to(p, x0, y0, x0 + r, y0)
	paint.close(p)
}

// Clears (to transparent) what `p` covers, widened by `width` when it is not 0.
@(private = "file")
cut :: proc(c: ^paint.Canvas, p: paint.Path, width: f32 = 0) {
	if width > 0 {
		ring := paint.widen(p, {width = width, join = .Round})
		defer paint.path_destroy(&ring)
		paint.set_clip(c, ring)
	} else {
		paint.set_clip(c, p)
	}
	paint.clear(c)
	paint.reset_clip(c)
}

// A shape with its gradient from `y0` to `y1` and an edge inside its outline.
@(private = "file")
shape :: proc(c: ^paint.Canvas, p: paint.Path, y0, y1: f32, top, bottom, edge: u32) {
	paint.fill(c, p, paint.linear({0, y0}, {0, y1}, paint.hex(top), paint.hex(bottom)))
	paint.set_clip(c, p)   // (the edge inside the outline only: the silhouette keeps its size)
	paint.stroke(c, p, {width = LOGO_EDGE * 2, join = .Round}, paint.solid(paint.hex(edge, 200)))
	paint.reset_clip(c)
}

// 1: both sheets (32 px and up); 0: one (16 to 24).
detail_for :: proc(size: int) -> int { return size <= 24 ? 0 : 1 }

logo_draw :: proc(size: int, detail: int) -> paint.Canvas {
	c := paint.canvas_make(size, size)
	k := f32(size) / LOGO_UNITS
	c.transform = paint.scale(paint.IDENTITY, k, k)

	// the back of the folder, its tab at the top left
	back: paint.Path
	defer paint.path_destroy(&back)
	paint.move_to(&back, 64, 120)
	paint.quad_to(&back, 64, 88, 96, 88)
	paint.line_to(&back, 196, 88)
	paint.quad_to(&back, 214, 88, 226, 102)
	paint.line_to(&back, 250, 128)
	paint.line_to(&back, 416, 128)
	paint.quad_to(&back, 448, 128, 448, 160)
	paint.line_to(&back, 448, 400)
	paint.quad_to(&back, 448, 432, 416, 432)
	paint.line_to(&back, 96, 432)
	paint.quad_to(&back, 64, 432, 64, 400)
	paint.close(&back)
	shape(&c, back, 88, 432, BACK_TOP, BACK_BOTTOM, BACK_EDGE)

	// the sheets standing in it, the second turned a little
	if detail > 0 {
		second: paint.Path
		defer paint.path_destroy(&second)
		rounded(&second, 150, 150, 380, 360, 16)
		paint.path_transform(&second, paint.rotate_at(paint.IDENTITY, 7, 265, 255))
		cut(&c, second, LOGO_GAP)
		shape(&c, second, 150, 360, SHEET_TOP, SHEET_BOTTOM, SHEET_EDGE)
	}
	first: paint.Path
	defer paint.path_destroy(&first)
	rounded(&first, 120, 166, 350, 380, 16)
	cut(&c, first, LOGO_GAP)
	shape(&c, first, 166, 380, SHEET_TOP, SHEET_BOTTOM, SHEET_EDGE)

	// the front panel, lower, a gap around it
	front: paint.Path
	defer paint.path_destroy(&front)
	rounded(&front, 64, 226, 448, 432, 32)
	cut(&c, front, LOGO_GAP * 2)
	shape(&c, front, 226, 432, FRONT_TOP, FRONT_BOTTOM, FRONT_EDGE)
	return c
}

// The picture at `size`: drawn large, then shrunk in steps the cubic filter keeps clean.
logo_render :: proc(size: int) -> paint.Canvas {
	n := size
	for n < LOGO_MASTER { n *= LOGO_SHRINK_STEP }
	c := logo_draw(n, detail_for(size))
	for n > size {
		next := max(n / LOGO_SHRINK_STEP, size)
		small := paint.resize(c, next, next)
		paint.canvas_destroy(&c)
		c, n = small, next
	}
	return c
}

run_logo :: proc(args: []string) -> int {
	_ = os.make_directory_all(LOGO_DIR)
	master := logo_render(LOGO_MASTER)
	defer paint.canvas_destroy(&master)
	path := fmt.tprintf("%s/logo.png", LOGO_DIR)
	if !paint.write_png(master, path) { fmt.eprintfln("classeurtool: %s cannot be written", path); return 1 }
	fmt.printfln("wrote %s", path)
	for size in LOGO_SIZES {
		c := logo_render(size)
		defer paint.canvas_destroy(&c)
		p := fmt.tprintf("%s/logo_%d.png", LOGO_DIR, size)
		if !paint.write_png(c, p) { fmt.eprintfln("classeurtool: %s cannot be written", p); return 1 }
		fmt.printfln("wrote %s", p)
	}
	// the project's picture (.project/image.png, 512 px): what the repository and opencode's sessions of it show
	project := logo_render(PROJECT_IMAGE_SIZE)
	defer paint.canvas_destroy(&project)
	_ = os.make_directory_all(".project")
	if !paint.write_png(project, PROJECT_IMAGE) { fmt.eprintfln("classeurtool: %s cannot be written", PROJECT_IMAGE); return 1 }
	fmt.printfln("wrote %s", PROJECT_IMAGE)
	return 0
}

PROJECT_IMAGE      :: ".project/image.png"
PROJECT_IMAGE_SIZE :: 512
