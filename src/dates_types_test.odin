package classeur

// How the dates read in each format of files.date_format, and the types' names the system gives, kept by extension.

import "base:runtime"
import "core:fmt"
import "core:testing"
import "core:time"
import "core:time/datetime"
import config "gt:config"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

// Each format, counted from Thursday 12 Nov 2026.
@(test)
test_date_formats :: proc(t: ^testing.T) {
	today := datetime.Date{2026, 11, 12}
	at :: proc(year: i64, month, day, hour, minute: i8) -> datetime.DateTime {
		return {date = {year, month, day}, time = {hour, minute, 0, 0}}
	}
	now := at(2026, 11, 12, 21, 16)
	testing.expect_value(t, date_format_text(now, today, .ISO), "2026-11-12 21:16")
	testing.expect_value(t, date_format_text(now, today, .Day_Month_Year), "12 Nov 2026 21:16")
	testing.expect_value(t, date_format_text(at(2026, 1, 3, 8, 5), today, .Day_Month_Year), "3 Jan 2026 08:05")
	testing.expect_value(t, date_format_text(now, today, .Relative), "Today 21:16")
	testing.expect_value(t, date_format_text(at(2026, 11, 11, 9, 2), today, .Relative), "Yesterday 09:02")
	testing.expect_value(t, date_format_text(at(2026, 11, 9, 8, 5), today, .Relative), "Monday 08:05")
	testing.expect_value(t, date_format_text(at(2026, 11, 6, 8, 5), today, .Relative), "Friday 08:05")
	// (a week back: Thursday again, the date said)
	testing.expect_value(t, date_format_text(at(2026, 11, 5, 8, 5), today, .Relative), "5 Nov 2026")
	testing.expect_value(t, date_format_text(at(2025, 12, 31, 23, 59), today, .Relative), "31 Dec 2025")
	testing.expect_value(t, date_format_text(at(2026, 11, 14, 8, 5), today, .Relative), "14 Nov 2026")   // (to come)
}

// date_text follows the setting: ISO by default, the others once chosen.
@(test)
test_date_setting :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt"})
		_, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		ns := time.now()._nsec
		dt, ok := local_datetime(app.tz, ns)
		testing.expect(t, ok)
		testing.expect_value(t, app.settings.date_format, Date_Format.ISO)
		testing.expect_value(t, date_text(app, ns), fmt.tprintf("%04d-%02d-%02d %02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.minute))
		_ = config.set_from_string(&app.prefs, "files.date_format", "day month year", .User)
		settings_apply(app)
		testing.expect_value(t, date_text(app, ns), date_format_text(dt, dt.date, .Day_Month_Year))
		_ = config.set_from_string(&app.prefs, "files.date_format", "relative", .User)
		settings_apply(app)
		testing.expect_value(t, date_text(app, ns), fmt.tprintf("Today %02d:%02d", dt.hour, dt.minute))
	})
}

// A type asked: its extension's name at once, the system's once a worker has read it (when the system has one);
// folders are "Folder".
@(test)
test_type_names :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		dir := make_fixture(t, {"a.txt"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		testing.expect_value(t, type_text(app, fs.Entry{name = "Photos", kind = .Directory}), "Folder")
		testing.expect_value(t, type_text(app, fs.Entry{name = "Photos", kind = .Directory, flags = {.Link}}), "Folder link")
		file := fs.Entry{name = "notes.zzqtype", kind = .File}
		first := type_text(app, file)
		_, asked := app.type_names["zzqtype"]
		testing.expect(t, asked, "the type asked")
		if !asked { return }
		testing.expect_value(t, first, "ZZQTYPE File")
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.type_names["zzqtype"].known }, "the type's name")
		name := app.type_names["zzqtype"].name
		testing.expect_value(t, type_text(app, file), name != "" ? name : "ZZQTYPE File")
		// (a file in a search's rows: its extension, not its folder's)
		_ = type_text(app, fs.Entry{name = "sub.dir/readme", kind = .File})
		_, wrong := app.type_names["dir/readme"]
		testing.expect(t, !wrong, "the folder's dot is no extension")
	})
}
