package classeur

// How the window reads: the small controls' corners follow the rounding setting, and with two panels the one that has
// the keyboard stands out (the accent along its shown tab's top, the other one's contents dimmed).

import "base:runtime"
import "core:fmt"
import "core:testing"
import "gt:testkit/unwatched"
import "gt:testkit/session"
import "gt:ui"

@(test)
test_controls_follow_the_rounding :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		st := &app.main.state

		// at the default rounding: the corners of the rows' pill, CONTROL_RADIUS_EM (the toolkit's own scaling squared them)
		// (the first crumb shown: a long path, as Windows' temporary folder, leaves out the first ones)
		first_crumb :: proc(s: ^session.Session) -> ^ui.Box {
			for i in 0 ..< 64 { if b := session.find(s, fmt.tprintf("crumb%d", i)); b != nil { return b } }
			return nil
		}
		crumb := first_crumb(s)
		back := session.find(s, "back")
		if !testing.expect(t, crumb != nil && back != nil, "a crumb and the back button") { return }
		testing.expectf(t, ui.box_drawn_radius(st, crumb) > 0, "a crumb is rounded at the default: %v", ui.box_drawn_radius(st, crumb))
		testing.expect_value(t, ui.box_drawn_radius(st, back), ui.box_drawn_radius(st, crumb))

		// at 0: square
		ui.set_rounding(st, 0)
		session.frames(s, 2)
		crumb = first_crumb(s)
		back = session.find(s, "back")
		if !testing.expect(t, crumb != nil && back != nil) { return }
		testing.expect_value(t, ui.box_drawn_radius(st, crumb), 0)
		testing.expect_value(t, ui.box_drawn_radius(st, back), 0)

		// the address field too
		session.key(s, .L, {.Ctrl})
		session.frames(s, 2)
		if address := session.find(s, "address"); testing.expect(t, address != nil, "the address field") {
			testing.expect_value(t, ui.box_drawn_radius(st, address), 0)
		}
	})
}

@(test)
test_focused_panel_stands_out :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 700})
		context.allocator = runtime.heap_allocator()
		session.key(s, .D, {.Ctrl, .Shift})
		wait_read(s)
		if !testing.expect_value(t, len(app.panels), 2) { return }
		testing.expect_value(t, app.focus, 1)

		// the shown tab of each: the focused panel's has the accent, the other's none
		focused := session.find(s, fmt.tprintf("tab%d", panel_tab(app.panels[1]).id))
		other := session.find(s, fmt.tprintf("tab%d", panel_tab(app.panels[0]).id))
		if !testing.expect(t, focused != nil && other != nil, "the two shown tabs") { return }
		fp, op := (^Tab_Paint)(focused.custom_user), (^Tab_Paint)(other.custom_user)
		if !testing.expect(t, fp != nil && op != nil, "both painted") { return }
		testing.expect(t, fp.line.a > 0, "the focused panel's tab has the accent")
		testing.expect(t, op.line.a == 0, "the other's has none")

		// the accent is the tab's top edge, tab_line_px() thick: its first row and its second are the accent, not the
		// edge's colour that the other tab's top is
		img := session.capture(s)
		lw := int(tab_line_px())
		fx, ox := int((focused.rect.min.x + focused.rect.max.x) * 0.5), int((other.rect.min.x + other.rect.max.x) * 0.5)
		fy, oy := int(focused.rect.min.y), int(other.rect.min.y)
		top := session.pixel(img, fx, fy)
		testing.expect(t, !session.near(top, session.pixel(img, ox, oy), 8), "the focused tab's top is not the edge's colour")
		testing.expect(t, session.near(top, session.pixel(img, fx, fy + lw - 1), 8), "the accent is as thick as tab_line_px")
		testing.expect(t, !session.near(top, session.pixel(img, fx, fy + lw + 1), 8), "and no thicker")

		// the contents of the panel without the keyboard are dimmed, its column titles with its rows
		dimmed, lit := session.find(s, "content", 0), session.find(s, "content", 1)
		if testing.expect(t, dimmed != nil && lit != nil, "the two panels' contents") {
			testing.expect(t, dimmed.transparency > 0, "the other panel's contents dimmed")
			testing.expect_value(t, lit.transparency, 0)
		}
		testing.expect_value(t, panel_dim(app, 1), 0)
	})
}
