package classeur

// Depth: a raised surface is lighter at its top than at its bottom, has a line of light along its top edge and a border
// of its own colour. The selection, the shown tab, the cards, the boxes of the footer are raised; the lists and the bars
// lie flat under them, each surface a step from the next.

import "gt:draw"
import "gt:ui"

// How much lighter the top and darker the bottom of a raised surface are, and the light along its top.
RAISE_LIGHT :: 0.10
RAISE_DARK  :: 0.12
RAISE_LINE  :: 0.14

// The surfaces' colours (sRGB), dark and light: the window's top, the sidebar and the footers, the lists, the headers,
// the cards and the boxes.
Surfaces :: struct { top, side, list, head, raised, edge: u32 }
SURFACES_DARK  :: Surfaces{top = 0x141517ff, side = 0x18191cff, list = 0x1e1f22ff, head = 0x232427ff, raised = 0x2a2b2fff, edge = 0x34363bff}
SURFACES_LIGHT :: Surfaces{top = 0xe4e6e9ff, side = 0xeef0f2ff, list = 0xfbfbfcff, head = 0xf1f2f4ff, raised = 0xffffffff, edge = 0xd2d5daff}

surfaces :: proc(app: ^App) -> Surfaces { return app.theme_shown.light ? SURFACES_LIGHT : SURFACES_DARK }

Raised :: struct {
	base:   ui.Color,
	edge:   ui.Color,
	radii:  [4]f32,   // top-left, bottom-left, top-right, bottom-right
	inset:  [2]f32,   // from the box's sides and its top and bottom
	no_top: bool,     // no line of light (a surface that is not raised, only bordered)
}

// Paints `r` raised: the gradient, the line of light, the border.
paint_raised :: proc(dc: ^draw.Context, r: ui.Rect, d: Raised) {
	top := draw.mix(d.base, {1, 1, 1, d.base.a}, RAISE_LIGHT)
	bottom := draw.mix(d.base, {0, 0, 0, d.base.a}, RAISE_DARK)
	draw.rect_corners(dc, r, {top, bottom, top, bottom}, d.radii)
	if !d.no_top {
		w := r.max.x - r.min.x
		k := min(d.radii[0], w * 0.5)
		draw.rect(dc, {{r.min.x + k, r.min.y}, {r.max.x - min(d.radii[2], w * 0.5), r.min.y + 1}}, {1, 1, 1, RAISE_LINE * d.base.a})
	}
	if d.edge.a > 0 { draw.rect_corners(dc, r, {d.edge, d.edge, d.edge, d.edge}, d.radii, 1) }
}

@(private = "file")
raised_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Raised)(user)
	r := b.rect
	paint_raised(dc, {{r.min.x + d.inset.x, r.min.y + d.inset.y}, {r.max.x - d.inset.x, r.max.y - d.inset.y}}, d^)
}

// The box `b` draws itself raised (under what it holds).
raise :: proc(b: ^ui.Box, d: Raised) {
	p := ui.frame_new(Raised)
	p^ = d
	b.custom, b.custom_user = raised_draw, p
}

// A radius on every corner.
radii_all :: proc(r: f32) -> [4]f32 { return {r, r, r, r} }
