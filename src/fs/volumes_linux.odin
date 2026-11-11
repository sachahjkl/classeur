package fs

// The volumes a person opens: the root and what is mounted under /media, /run/media and /mnt (removable drives,
// shares). The bind mounts of a system (NixOS's impermanence, containers) are left out.

import "core:os"
import "core:strings"

volumes :: proc(allocator := context.allocator) -> []Volume {
	out := make([dynamic]Volume, allocator)
	append(&out, Volume{path = strings.clone("/", allocator), label = strings.clone("File system", allocator)})
	data, err := os.read_entire_file("/proc/self/mountinfo", context.temp_allocator)
	if err != nil { return out[:] }
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		// id parent major:minor root mount-point options ... - type source super-options
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 5 { continue }
		at := unescape_octal(fields[4], context.temp_allocator)
		if !is_person_mount(at) { continue }
		append(&out, Volume{path = strings.clone(at, allocator), label = strings.clone(base(at), allocator), removable = true})
	}
	return out[:]
}

@(private = "file")
is_person_mount :: proc(at: string) -> bool {
	for prefix in ([]string{"/media/", "/run/media/", "/mnt/"}) {
		if !strings.has_prefix(at, prefix) { continue }
		rest := at[len(prefix):]
		// /run/media/<user>/<volume>, /media/<user>/<volume> or /media/<volume>, /mnt/<volume>
		depth := strings.count(rest, "/")
		return prefix == "/mnt/" ? depth == 0 : depth <= 1
	}
	return false
}

// mountinfo writes a space as \040, a tab as \011, a backslash as \134.
// (locations_linux.odin reads mountinfo too)
unescape_octal :: proc(s: string, allocator := context.allocator) -> string {
	if strings.index_byte(s, '\\') < 0 { return s }
	b := strings.builder_make(allocator)
	for i := 0; i < len(s); i += 1 {
		if s[i] == '\\' && i + 3 < len(s) && is_octal(s[i + 1]) && is_octal(s[i + 2]) && is_octal(s[i + 3]) {
			strings.write_byte(&b, (s[i + 1] - '0') << 6 | (s[i + 2] - '0') << 3 | (s[i + 3] - '0'))
			i += 3
			continue
		}
		strings.write_byte(&b, s[i])
	}
	return strings.to_string(b)
}

is_octal :: proc(c: u8) -> bool { return c >= '0' && c <= '7' }
