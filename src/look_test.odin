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
		if !testing.expect(t, focused.ring_at != nil && other.ring_at != nil, "both use ui.tab_face") { return }
		fr, _ := focused.ring_at(focused)
		or, _ := other.ring_at(other)

		// the accent band along the top of the focused panel's Folder tab (ui.tab_face's mark): inside its silhouette
		// top rows differ from the unfocused panel's tab, while deeper inside both show the list's ground
		img := session.capture(s)
		fx, ox := int((fr.min.x + fr.max.x) * 0.5), int((or.min.x + or.max.x) * 0.5)
		fy, oy := int(fr.min.y), int(or.min.y)
		diff_top := 0
		for dy in 0 ..< 5 {
			if !session.near(session.pixel(img, fx, fy + dy), session.pixel(img, ox, oy + dy), 16) { diff_top += 1 }
		}
		testing.expectf(t, diff_top >= 1, "the focused tab's top has the accent mark (%d differing rows)", diff_top)
		testing.expect(t, session.near(session.pixel(img, fx, fy + 6), session.pixel(img, ox, oy + 6), 8), "below the accent both tabs share the panel surface")

		// the contents of the panel without the keyboard are dimmed, its column titles with its rows
		dimmed, lit := session.find(s, "content", 0), session.find(s, "content", 1)
		if testing.expect(t, dimmed != nil && lit != nil, "the two panels' contents") {
			testing.expect(t, dimmed.transparency > 0, "the other panel's contents dimmed")
			testing.expect_value(t, lit.transparency, 0)
		}
		testing.expect_value(t, panel_dim(app, 1), 0)
	})
}
