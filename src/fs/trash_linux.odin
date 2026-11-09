package fs

// The trash of the freedesktop.org specification (Trash 1.0), which every Linux desktop reads: a file goes to the
// home trash ($XDG_DATA_HOME/Trash) when it is on the same volume, else to the trash at the top of its own volume
// (<top>/.Trash-<uid>). Beside it in info/ a <name>.trashinfo says in_trash it was and when it went, so that the desktop's
// trash can put it back. The file is renamed, never copied: a trash is always on the file's volume.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/linux"
import "core:time"
import "core:time/timezone"

// Moves `path` to the trash; `in_trash` is its path in the trash (files/<name>: what untrash puts back).
trash :: proc(path: string, allocator := context.allocator) -> (in_trash: string, e: Error) {
	dev, ok := device_of(path)
	if !ok { return "", .Not_Found }
	dir := home_trash(context.temp_allocator)
	_ = os.make_directory_all(parent(dir))   // (a new account may have no ~/.local/share yet)
	if hdev, hok := device_of(parent(dir)); !hok || hdev != dev {
		top := volume_top(path, dev)
		dir = join(top, fmt.tprintf(".Trash-%d", u32(linux.getuid())), context.temp_allocator)
	}
	files := join(dir, "files", context.temp_allocator)
	info := join(dir, "info", context.temp_allocator)
	for d in ([]string{dir, files, info}) {
		if err := linux.mkdir(cpath_t(d), {.IRUSR, .IWUSR, .IXUSR}); err != .NONE && err != .EEXIST { return "", .Denied }
	}

	// a name of its own in the trash, taken by making its .trashinfo (O_EXCL: two programs never take the same)
	name := base(path)
	info_file: linux.Fd = -1
	for n := 1; n < 10000; n += 1 {
		candidate := n == 1 ? name : numbered_name(name, n, context.temp_allocator)
		fd, err := linux.open(cpath_t(join(info, strings.concatenate({candidate, ".trashinfo"}, context.temp_allocator), context.temp_allocator)), {.WRONLY, .CREAT, .EXCL, .CLOEXEC}, {.IRUSR, .IWUSR})
		if err == .EEXIST { continue }
		if err != .NONE { return "", .Denied }
		info_file, name = fd, candidate
		break
	}
	if info_file < 0 { return "", .Exists }
	info_path := join(info, strings.concatenate({name, ".trashinfo"}, context.temp_allocator), context.temp_allocator)
	text := fmt.tprintf("[Trash Info]\nPath=%s\nDeletionDate=%s\n", url_path(path), local_date_time())
	_, werr := linux.write(info_file, transmute([]u8)text)
	linux.close(info_file)
	if werr != .NONE {
		linux.unlink(cpath_t(info_path))
		return "", .No_Space
	}
	to := join(files, name, allocator)
	if re := rename(path, to); re != .None {
		linux.unlink(cpath_t(info_path))
		delete(to, allocator)
		return "", re
	}
	return to, .None
}

// Puts back what trash moved to `in_trash` (<trash>/files/<name>): to the path its .trashinfo names, which must be free.
untrash :: proc(in_trash: string) -> Error {
	dir := parent(parent(in_trash))
	info_path := join(join(dir, "info", context.temp_allocator), strings.concatenate({base(in_trash), ".trashinfo"}, context.temp_allocator), context.temp_allocator)
	data, err := os.read_entire_file(info_path, context.temp_allocator)
	if err != nil { return .Not_Found }
	text := string(data)
	original := ""
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "Path=") { original = url_decode(strings.trim_space(line[len("Path="):])) }
	}
	if original == "" { return .Other }
	if exists(original) { return .Exists }
	_ = os.make_directory_all(parent(original))
	if e := rename(in_trash, original); e != .None { return e }
	linux.unlink(cpath_t(info_path))
	return .None
}

// The bytes a %XX stands for, back.
@(private = "file")
url_decode :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' && i + 2 < len(s) {
			hi, lo := hex_value(s[i + 1]), hex_value(s[i + 2])
			if hi >= 0 && lo >= 0 {
				strings.write_byte(&b, u8(hi * 16 + lo))
				i += 2
				continue
			}
		}
		strings.write_byte(&b, s[i])
	}
	return strings.to_string(b)
}

@(private = "file")
hex_value :: proc(c: u8) -> int {
	switch c {
	case '0' ..= '9': return int(c - '0')
	case 'a' ..= 'f': return int(c - 'a') + 10
	case 'A' ..= 'F': return int(c - 'A') + 10
	}
	return -1
}

@(private = "file")
cpath_t :: proc(path: string) -> cstring { return strings.clone_to_cstring(path, context.temp_allocator) }

@(private = "file")
home_trash :: proc(allocator := context.allocator) -> string {
	data := os.get_env("XDG_DATA_HOME", context.temp_allocator)
	if data == "" { data = join(home(context.temp_allocator), ".local/share", context.temp_allocator) }
	return join(data, "Trash", allocator)
}

// The folder at the top of the volume that holds `path`: the last folder up the path still on device `dev`.
@(private = "file")
volume_top :: proc(path: string, dev: u64) -> string {
	at := path
	for {
		up := parent(at)
		if up == "" { return at }
		d, ok := device_of(up)
		if !ok || d != dev { return at }
		at = up
	}
}

// The path as the specification writes it: every byte but the unreserved ones and '/' as %XX.
@(private = "file")
url_path :: proc(path: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(path) {
		c := path[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.', '~', '/':
			strings.write_byte(&b, c)
		case:
			fmt.sbprintf(&b, "%%%02X", c)
		}
	}
	return strings.to_string(b)
}

// "2026-11-09T21:40:05", the local time.
@(private = "file")
local_date_time :: proc() -> string {
	dt, _ := time.time_to_datetime(time.now())
	if tz, ok := timezone.region_load("local", context.temp_allocator); ok {
		if local, lok := timezone.datetime_to_tz(dt, tz); lok { dt = local }
	}
	return fmt.tprintf("%04d-%02d-%02dT%02d:%02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)
}
