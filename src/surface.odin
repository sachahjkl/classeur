package classeur

// Depth: a raised surface is a step lighter than what it lies on, in one flat colour, with a border of its own colour.
// The selection, the shown tab, the cards, the boxes of the footer are raised; the lists and the bars lie flat under
// them, each surface a step from the next.

import "gt:draw"
import "gt:ui"

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
}

// Paints `r` raised: its colour, its border.
paint_raised :: proc(dc: ^draw.Context, r: ui.Rect, d: Raised) {
	draw.rect_corners(dc, r, {d.base, d.base, d.base, d.base}, d.radii)
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
