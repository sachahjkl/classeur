package classeur

// Depth: a raised surface is a step lighter than what it lies on, in one flat colour, with a border of its own colour.
// The selection, the shown tab, the cards, the boxes of the footer are raised; the lists and the bars lie flat under
// them, each surface a step from the next.

import "gt:draw"
import "gt:ui"

// The surfaces' colours (sRGB) of the theme shown, by its steps as the toolkit lays them out (theme_palette): the window's
// top (its darkest, the well), the lists (its page), the sidebar and the footers (its bars), the headers, the cards and
// the boxes, the lines. Every program of the toolkit shows the same colours for a theme.
Surfaces :: struct { top, side, list, head, raised, edge: u32 }

surfaces :: proc(app: ^App) -> Surfaces {
	c, _ := ui.theme_version(app.theme_shown.def, app.theme_shown.light)
	return Surfaces{top = c.steps[0], list = c.steps[1], side = c.steps[2], head = c.steps[3], raised = c.steps[4], edge = c.steps[5]}
}

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
