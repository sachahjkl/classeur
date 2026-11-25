package classeur

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "gt:ui"

// A full list, at its top and scrolled: a drag from after a row's name is a rectangle under the pointer, a click there
// picks the row, a drag from the name drags the file.
@(test)
test_band_from_a_row :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		list := make([dynamic]string, context.temp_allocator)
		for i in 0 ..< 200 { append(&list, fmt.tprintf("file %03d.txt", i)) }
		dir := make_fixture(t, list[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		for zoom in 0 ..= 1 {
			tab.zoom = zoom
			wait_read(s)
			session.frames(s, 6)
			for scroll in ([3]f32{0, 50, 1500}) {
				lb := band_box(tab)
				lb.view_target.y, lb.view_off.y = scroll, scroll
				session.frames(s, 4)
				lb = band_box(tab)
				first := session.get(s, "n", within = session.get(s, fmt.tprintf("lrow_%d", tab.vl.first)))
				// (just after the name's text, over the rows under it)
				from := ui.Vec2{math.round(first.rect.min.x + first.text_pad + first.text_dim.x + 12), lb.rect.min.y + 100}
				to := ui.Vec2{from.x - 60, lb.rect.min.y + 240}
				session.press(s, from)
				testing.expect(t, app.band.pending, "waits")
				session.move(s, to)
				session.frames(s, 2)
				testing.expectf(t, app.band.active && len(tab.folder.selected) > 2, "zoom %d, %v: a rectangle", zoom, scroll)
				testing.expect(t, !app.file_drag && len(app.drag_paths) == 0, "no file dragged")
				if b := session.find(s, fmt.tprintf("band%d", tab.id)); testing.expect(t, b != nil, "its box") {
					testing.expectf(t, b.rect == {{to.x, from.y}, {from.x, to.y}}, "zoom %d, %v: %v", zoom, scroll, b.rect)
				}
				session.release(s, to)
				session.advance(s, session.SEPARATE_CLICK_MS)
				session.click_at(s, from)
				session.frames(s, 2)
				testing.expectf(t, len(tab.folder.selected) == 1, "zoom %d, %v: a click picks one", zoom, scroll)
				session.advance(s, session.SEPARATE_CLICK_MS)
			}
			row := session.get(s, fmt.tprintf("lrow_%d", tab.vl.first + (tab.vl.last - tab.vl.first) / 2))
			name := session.get(s, "n", within = row).rect
			at := ui.Vec2{name.min.x + 12, (name.min.y + name.max.y) * 0.5}
			session.press(s, at)
			session.move(s, at + {0, 40})
			session.frames(s, 2)
			testing.expectf(t, app.file_drag && !app.band.active && !app.band.pending, "zoom %d: the name drags the file", zoom)
			session.key(s, .Escape)
			session.release(s, at + {0, 40})
			session.frames(s, 2)
		}
	})
}

// Ctrl and a drag in the columns scrolled: the view stays where it is, at the press and at the release.
@(test)
test_columns_stay_under_a_band :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		list := make([dynamic]string, context.temp_allocator)
		for i in 0 ..< 400 { append(&list, fmt.tprintf("file %03d.txt", i)) }
		dir := make_fixture(t, list[:])
		s, app := start(t, {dir}, size = {1000, 700})
		context.allocator = runtime.heap_allocator()
		tab := current_tab(app)
		for z, i in ZOOMS { if z.mode == .Columns { tab.zoom = i } }
		wait_read(s)
		session.frames(s, 6)
		lb := band_box(tab)
		lb.view_target.x, lb.view_off.x = 1500, 1500
		session.frames(s, 4)
		at := band_box(tab).rect.min + {60, 60}
		for p, i in ([3]ui.Vec2{at, at + {40, 20}, at + {300, 180}}) {
			s.pointer = p
			if i == 0 { s.buttons += {.Left} }
			session.event(s, {kind = i == 0 ? .Mouse_Press : .Mouse_Move, button = .Left, pos = p, mods = {.Ctrl}})
			session.frames(s, 3)
			testing.expectf(t, band_box(tab).view_target.x == 1500, "step %d: %v", i, band_box(tab).view_target.x)
		}
		testing.expect(t, app.band.active, "a rectangle")
		s.buttons -= {.Left}
		session.event(s, {kind = .Mouse_Release, button = .Left, pos = at + {300, 180}, mods = {.Ctrl}})
		session.frames(s, 4)
		testing.expectf(t, band_box(tab).view_target.x == 1500, "let go: %v", band_box(tab).view_target.x)
	})
}
