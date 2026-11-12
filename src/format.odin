package classeur

// How an entry reads in a row: its size, its date, its type, its icon.

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/timezone"
import "fs"

// "512 B", "12.4 KB", "3.1 MB", "1.2 GB" (powers of 1024, as the systems' file managers count).
size_text :: proc(n: i64, allocator := context.temp_allocator) -> string {
	units := [?]string{"KB", "MB", "GB", "TB", "PB"}
	if n < 1024 { return fmt.aprintf("%d B", n, allocator = allocator) }
	v := f64(n) / 1024
	u := 0
	for v >= 1024 && u < len(units) - 1 {
		v /= 1024
		u += 1
	}
	return v < 10 ? fmt.aprintf("%.1f %s", v, units[u], allocator = allocator) : fmt.aprintf("%.0f %s", v, units[u], allocator = allocator)
}

// "2026-11-09 21:40" in the local time (UTC when the time zone is not known).
date_text :: proc(app: ^App, ns: i64, allocator := context.temp_allocator) -> string {
	if ns == 0 { return "" }
	dt, ok := time.time_to_datetime(time.Time{_nsec = ns})
	if !ok { return "" }
	if app.tz != nil {
		if local, lok := timezone.datetime_to_tz(dt, app.tz); lok { dt = local }
	}
	return fmt.aprintf("%04d-%02d-%02d %02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.minute, allocator = allocator)
}


type_text :: proc(e: fs.Entry, allocator := context.temp_allocator) -> string {
	switch e.kind {
	case .Directory:   return .Link in e.flags ? "Folder link" : "File folder"
	case .Broken_Link: return "Broken link"
	case .Other:       return "Special"
	case .File:
	}
	ext := fs.extension(e.name)
	if ext == "" { return .Executable in e.flags ? "Program" : "File" }
	return strings.concatenate({strings.to_upper(ext, context.temp_allocator), " File"}, allocator)
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
