package classeur

// How an entry reads in a row: its size, its date, its type, its icon.

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "gt:i18n"
import "gt:ui"
import "fs"

// "512 B", "12.4 KB", "3.1 MB", "1.2 GB" (powers of 1024, as the systems' file managers count).
size_text :: proc(n: i64, allocator := context.temp_allocator) -> string {
	units := [?]string{i18n.tr("KB"), i18n.tr("MB"), i18n.tr("GB"), i18n.tr("TB"), i18n.tr("PB")}
	if n < 1024 { return fmt.aprintf(i18n.tr("%d B"), n, allocator = allocator) }
	v := f64(n) / 1024
	u := 0
	for v >= 1024 && u < len(units) - 1 {
		v /= 1024
		u += 1
	}
	return v < 10 ? fmt.aprintf("%.1f %s", v, units[u], allocator = allocator) : fmt.aprintf("%.0f %s", v, units[u], allocator = allocator)
}

// How the dates read (files.date_format).
Date_Format :: enum u8 {
	ISO,              // "2026-11-09 21:40"
	Relative,         // "Today 21:40", "Yesterday 21:40", "Monday 21:40", else "9 Nov 2026"
	Day_Month_Year,   // "9 Nov 2026 21:40"
}

// (not rodata: i18n.later marks the names for the catalogue; tr where a date is written)
@(private = "file")
MONTH_NAMES := [12]string{i18n.later("Jan"), i18n.later("Feb"), i18n.later("Mar"), i18n.later("Apr"), i18n.later("May"), i18n.later("Jun"), i18n.later("Jul"), i18n.later("Aug"), i18n.later("Sep"), i18n.later("Oct"), i18n.later("Nov"), i18n.later("Dec")}

@(private = "file")
WEEKDAY_NAMES := [datetime.Weekday]string{
	.Sunday = i18n.later("Sunday"), .Monday = i18n.later("Monday"), .Tuesday = i18n.later("Tuesday"), .Wednesday = i18n.later("Wednesday"), .Thursday = i18n.later("Thursday"),
	.Friday = i18n.later("Friday"), .Saturday = i18n.later("Saturday"),
}

// A time in the local time (UTC when the time zone is not known).
local_datetime :: proc(tz: ^datetime.TZ_Region, ns: i64) -> (dt: datetime.DateTime, ok: bool) {
	dt = time.time_to_datetime(time.Time{_nsec = ns}) or_return
	if tz != nil {
		if local, lok := timezone.datetime_to_tz(dt, tz); lok { dt = local }
	}
	return dt, true
}

// A date in the local time, in the person's format.
date_text :: proc(app: ^App, ns: i64, allocator := context.temp_allocator) -> string {
	if ns == 0 { return "" }
	dt, ok := local_datetime(app.tz, ns)
	if !ok { return "" }
	today: datetime.Date
	if app.settings.date_format == .Relative {
		// (today read once a frame, not for each row shown)
		if app.today_frame != app.frame || app.today.year == 0 {
			app.today_frame = app.frame
			if now, nok := local_datetime(app.tz, time.now()._nsec); nok {
				app.today = now.date
				// (an idle window draws no frame: woken just past midnight, its "Today" becomes "Yesterday")
				ui.wake_within(&app.main.state, int(ms_to_midnight(now.time)) + MIDNIGHT_MARGIN_MS)
			}
		}
		today = app.today
	}
	return date_format_text(dt, today, app.settings.date_format, allocator)
}

// How long past midnight the window wakes (the clock read then is surely on the new day).
MIDNIGHT_MARGIN_MS :: 50

// The milliseconds from a local time of day to the next local midnight (a day of 24 hours: a change of the clock
// between them is not counted).
ms_to_midnight :: proc(at: datetime.Time) -> i64 {
	past := (i64(at.hour) * 3600 + i64(at.minute) * 60 + i64(at.second)) * 1000 + i64(at.nano) / 1_000_000
	return max(24 * 3600 * 1000 - past, 1)
}

// `dt` in `format`; `today` is what Relative counts from.
date_format_text :: proc(dt: datetime.DateTime, today: datetime.Date, format: Date_Format, allocator := context.temp_allocator) -> string {
	month := i18n.tr(MONTH_NAMES[clamp(int(dt.month), 1, 12) - 1])
	switch format {
	case .ISO:
	case .Day_Month_Year:
		return fmt.aprintf("%d %s %d %02d:%02d", dt.day, month, dt.year, dt.hour, dt.minute, allocator = allocator)
	case .Relative:
		day, _ := datetime.date_to_ordinal(dt.date)
		now, _ := datetime.date_to_ordinal(today)
		switch {
		case day == now:     return fmt.aprintf(i18n.tr("Today %02d:%02d"), dt.hour, dt.minute, allocator = allocator)
		case day == now - 1: return fmt.aprintf(i18n.tr("Yesterday %02d:%02d"), dt.hour, dt.minute, allocator = allocator)
		// (a week back the weekday is today's again: from there, the date)
		case day < now && day > now - 7:
			return fmt.aprintf("%s %02d:%02d", i18n.tr(WEEKDAY_NAMES[datetime.day_of_week(day)]), dt.hour, dt.minute, allocator = allocator)
		}
		return fmt.aprintf("%d %s %d", dt.day, month, dt.year, allocator = allocator)
	}
	return fmt.aprintf("%04d-%02d-%02d %02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.minute, allocator = allocator)
}

// What an entry is: the system's name of its type when it is known (type_names.odin), else its extension's.
type_text :: proc(app: ^App, e: fs.Entry, allocator := context.temp_allocator) -> string {
	switch e.kind {
	case .Directory:   return .Link in e.flags ? i18n.tr("Folder link") : i18n.tr("Folder")
	case .Broken_Link: return i18n.tr("Broken link")
	case .Other:       return i18n.tr("Special")
	case .File:
	}
	ext := fs.extension(fs.base(e.name))   // (a search's rows are named by their path below the folder)
	if ext == "" { return .Executable in e.flags ? i18n.tr("Program") : i18n.tr("File") }
	if name := type_name(app, ext); name != "" { return strings.clone(name, allocator) }
	return fmt.aprintf(i18n.tr("%s File"), strings.to_upper(ext, context.temp_allocator), allocator = allocator)
}


// "984", "7.3K", "12K", "1.2M": a count in a narrow column.
count_text :: proc(n: i64, allocator := context.temp_allocator) -> string {
	switch {
	case n < 1000:      return fmt.aprintf("%d", n, allocator = allocator)
	case n < 10_000:    return fmt.aprintf("%.1fK", f64(n) / 1000, allocator = allocator)
	case n < 1_000_000: return fmt.aprintf("%dK", n / 1000, allocator = allocator)
	}
	return fmt.aprintf("%.1fM", f64(n) / 1_000_000, allocator = allocator)
}
