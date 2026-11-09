package classeur

// The sidebar, File Pilot's: a filter at the top, then sections that open and close: the recent folders, the
// bookmarks, the storage (each volume with a bar of how full it is), the places. A click goes there in the tab that has
// the keyboard; a middle click opens a new tab.

import "core:fmt"
import "core:strings"
import "gt:draw"
import lucide "gt:lucide"
import "gt:ui"
import "fs"

Side_Section :: enum u8 { Recents, Bookmarks, Storage, Places }

@(private = "file", rodata)
SECTION_TITLES := [Side_Section]string{.Recents = "Recents", .Bookmarks = "Bookmarks", .Storage = "Storage", .Places = "Places"}
@(private = "file", rodata)
SECTION_ICONS := [Side_Section]string{.Recents = lucide.HISTORY, .Bookmarks = lucide.BOOKMARK, .Storage = lucide.HARD_DRIVE, .Places = lucide.FOLDER}


// How full a volume is: its bar under its name.
VOLUME_BAR      :: 0x2f7fd0ff
VOLUME_BAR_FULL :: 0xe9605fff
VOLUME_FULL_AT  :: 0.9

sidebar_build :: proc(app: ^App, em: f32) {
	t := current_tab(app)
	here := t != nil ? t.path : ""
	ui.next_merge({axis = .Y, bg = draw.hex(surfaces(app).side)})
	box := ui.build_box({.Clip, .Draw_Side_Right, .Draw_Background}, "###sidebar")
	if ui.parent(box) {
		side_filter(app, em)
		query := strings.to_lower(ui.field_string(&app.side_filter), context.temp_allocator)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.scroll_y("###side_scroll") {
			ui.spacer(ui.px(em * 0.3))
			if section(app, .Recents, em) {
				for p, i in app.recents {
					if !keeps(query, fs.base(p)) { continue }
					side_folder(app, t, fmt.tprintf("###recent%d", i), p, cut_text(home_path(app, p), 40), here, em)
				}
			}
			if section(app, .Bookmarks, em) {
				for p, i in app.bookmarks {
					if !keeps(query, fs.base(p)) { continue }
					side_folder(app, t, fmt.tprintf("###bookmark%d", i), p, fs.base(p), here, em)
				}
				if len(app.bookmarks) == 0 && query == "" {
					if ui.tags("weak") {
						ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 1.8)), font_size = em * 0.85})
						if ui.row(.Center) {
							ui.spacer(ui.px(em * 2.6))
							ui.label(fmt.tprintf("%s: bookmark a folder###bm_hint", shortcut_text(command_find("bookmark").keys[0])))
						}
					}
				}
			}
			if section(app, .Storage, em) {
				for v, i in app.volumes {
					if !keeps(query, v.label) { continue }
					sp := i < len(app.volume_space) ? app.volume_space[i] : fs.Space{}
					if side_volume(app, i, v, sp, v.path == here, em) && t != nil { tab_go(app, t, v.path) }
				}
			}
			if section(app, .Places, em) {
				for p, i in app.places {
					if !keeps(query, p.name) { continue }
					sig := side_row(app, fmt.tprintf("###place%d", i), p.path, p.name, p.path == here, em)
					go_from(app, t, sig, p.path)
				}
			}
			ui.spacer(ui.px(em * 0.6))
		}
	}
}

@(private = "file")
keeps :: proc(query, name: string) -> bool {
	return query == "" || strings.contains(strings.to_lower(name, context.temp_allocator), query)
}

@(private = "file")
go_from :: proc(app: ^App, t: ^Tab, sig: ui.Signal, path: string) {
	if sig.clicked && t != nil { tab_go(app, t, path) }
	if sig.middle_clicked { tab_open(app, current_panel(app), path, current_panel(app).active + 1) }
}

@(private = "file")
side_filter :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.4))})
	if ui.row(.Center, {.Draw_Side_Bottom}, "###side_filter") {
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { glyph(app, lucide.SEARCH, em * 1.6) }
		key := ui.key_from_string(ui.parent_box().key, "###sfilter")
		ui.next({width = ui.fill(), height = ui.pct(1)})
		res: ui.Edit_Result
		if ui.tags("bare") { res = ui.line_edit("###sfilter", &app.side_filter, "Filter...") }
		note_text_field(app, key)
		if res.cancelled { ui.field_clear(&app.side_filter) }
		ui.spacer(ui.px(em * 0.4))
	}
}

// A section's heading: its icon, its title, a chevron; a click opens or closes it. True: it is open.
@(private = "file")
section :: proc(app: ^App, s: Side_Section, em: f32) -> bool {
	open := app.side_open[s]
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	sig: ui.Signal
	if ui.row(.Center, {.Clickable, .Draw_Hot_Effects, .Hot_Within}, fmt.tprintf("###sec_%s", SECTION_TITLES[s])) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 0.6))
		if ui.tags("weak") { glyph(app, SECTION_ICONS[s], em * 1.6) }
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###t", SECTION_TITLES[s]))
		if ui.tags("weak") { glyph(app, open ? lucide.CHEVRON_DOWN : lucide.CHEVRON_RIGHT, em * 1.6) }
		ui.spacer(ui.px(em * 0.5))
	}
	if sig.clicked { app.side_open[s] = !open }
	return app.side_open[s]
}

@(private = "file")
side_folder :: proc(app: ^App, t: ^Tab, id, path, name: string, here: string, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	on := path == here
	if on { flags += {.Draw_Background} }
	ui.next_merge({bg = on ? ui.color("border") : nil})
	sig: ui.Signal
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", shown_text(name)))
	}
	go_from(app, t, sig, path)
}

@(private = "file")
side_row :: proc(app: ^App, id, path: string, name: string, here: bool, em: f32) -> (sig: ui.Signal) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.2)), radius = 0, bg = here ? ui.color("border") : nil})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within, .Middle_Click}
	if here { flags += {.Draw_Background} }
	if ui.row(.Center, flags, id) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###n", shown_text(name)))
	}
	return
}

@(private = "file")
Bar_Draw :: struct { used: f32, bar, track: ui.Color }

@(private = "file")
bar_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Bar_Draw)(user)
	r := b.rect
	draw.rect(dc, r, d.track)
	draw.rect(dc, {r.min, {r.min.x + (r.max.x - r.min.x) * d.used, r.max.y}}, d.bar)
}

// A volume: its icon, its name, and under the name a bar of how full it is.
@(private = "file")
side_volume :: proc(app: ^App, i: int, v: fs.Volume, sp: fs.Space, here: bool, em: f32) -> bool {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * 2.5)), radius = 0})
	flags := ui.Box_Flags{.Clickable, .Draw_Hot_Effects, .Hot_Within}
	if here { flags += {.Draw_Background} }
	ui.next_merge({bg = here ? ui.color("border") : nil})
	sig: ui.Signal
	if ui.row(.Center, flags, fmt.tprintf("###vol%d", i)) {
		sig = ui.signal(ui.parent_box())
		ui.spacer(ui.px(em * 2.4))
		path_icon(app, v.path, true, em * 1.7)
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.pct(1), axis = .Y})
		if ui.column() {
			ui.spacer(ui.fill())
			ui.next({width = ui.fill(), height = ui.px(em * 1.45)})
			ui.label(fmt.tprintf("%s###n", shown_text(v.label)))
			ui.spacer(ui.px(em * 0.1))
			if sp.total > 0 {
				used := 1 - f32(f64(sp.free) / f64(sp.total))
				d := ui.frame_new(Bar_Draw)
				d^ = {used, draw.hex(used > VOLUME_FULL_AT ? VOLUME_BAR_FULL : VOLUME_BAR), ui.color("border")}
				ui.next({width = ui.fill(), height = ui.px(max(3, em * 0.25))})
				ui.custom("###bar", bar_draw, d)
			}
			ui.spacer(ui.fill())
		}
		ui.spacer(ui.px(em * 0.8))
	}
	if ui.hovered_for(sig, 0.5) && sp.total > 0 {
		if ui.tooltip() {
			ui.next({width = ui.text_size(em * 0.6), height = ui.px(ui.dense(em * 1.8))})
			ui.label(fmt.tprintf("%s free of %s###tip", size_text(sp.free), size_text(sp.total)))
		}
	}
	return sig.clicked
}
