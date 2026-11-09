package classeur

// How an entry reads in a row: its size, its date, its type, its icon.

import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/timezone"
import lucide "gt:lucide"
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
	case .Directory:   return .Link in e.flags ? "Folder link" : "Folder"
	case .Broken_Link: return "Broken link"
	case .Other:       return "Special"
	case .File:
	}
	ext := fs.extension(e.name)
	if ext == "" { return .Executable in e.flags ? "Program" : "File" }
	return strings.to_lower(ext, allocator)
}

@(private = "file")
Ext_Icon :: struct { exts: []string, icon: string }

@(private = "file", rodata)
EXT_ICONS := [?]Ext_Icon{
	{{"png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "avif", "heic", "tif", "tiff", "jxl", "psd", "xcf", "kra"}, lucide.FILE_IMAGE},
	{{"mp3", "flac", "wav", "ogg", "m4a", "opus", "aac", "wma", "aiff", "mid"}, lucide.FILE_MUSIC},
	{{"mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg"}, lucide.FILE_VIDEO_2},
	{{"zip", "tar", "gz", "xz", "bz2", "7z", "rar", "zst", "tgz", "lz4", "cab", "iso", "dmg", "deb", "rpm"}, lucide.FILE_ARCHIVE},
	{{"csv", "tsv", "xls", "xlsx", "ods", "numbers"}, lucide.FILE_SPREADSHEET},
	{{"exe", "msi", "appimage", "bat", "cmd", "com", "ps1"}, lucide.PACKAGE},
	{{"odin", "c", "h", "cc", "cpp", "hpp", "rs", "go", "py", "js", "mjs", "ts", "tsx", "jsx", "java", "kt", "swift", "rb", "sh", "fish",
	  "nix", "lua", "zig", "json", "toml", "yaml", "yml", "xml", "html", "htm", "css", "scss", "sql", "cs", "php", "wgsl", "glsl", "hlsl"}, lucide.FILE_CODE},
	{{"txt", "md", "rst", "log", "pdf", "doc", "docx", "odt", "rtf", "tex", "epub", "org", "ini", "cfg", "conf"}, lucide.FILE_TEXT},
}

entry_icon :: proc(e: fs.Entry) -> string {
	switch e.kind {
	case .Directory:   return .Link in e.flags ? lucide.FOLDER_SYMLINK : lucide.FOLDER
	case .Broken_Link: return lucide.FILE_SYMLINK
	case .Other:       return lucide.FILE
	case .File:
	}
	if .Link in e.flags { return lucide.FILE_SYMLINK }
	ext := fs.extension(e.name)
	if ext == "" { return lucide.FILE }
	buf: [16]u8
	if len(ext) > len(buf) { return lucide.FILE }
	for i in 0 ..< len(ext) { c := ext[i]; buf[i] = c >= 'A' && c <= 'Z' ? c + 32 : c }
	lower := string(buf[:len(ext)])
	for group in EXT_ICONS { for x in group.exts { if x == lower { return group.icon } } }
	return lucide.FILE
}

// The text cut after `max_runes` characters, with an ellipsis.
cut_text :: proc(text: string, max_runes: int, allocator := context.temp_allocator) -> string {
	n := 0
	for _, i in text {
		if n == max_runes { return strings.concatenate({text[:i], "…"}, allocator) }
		n += 1
	}
	return text
}
