package fs

// Paths as the system writes them: '/' on POSIX, '\' on Windows (a '/' typed by the person is turned into '\').
// A root keeps its separator ("/", "C:\"); no other path ends with one.

import "core:os"
import "core:strings"

when ODIN_OS == .Windows {
	SEPARATOR :: '\\'
	SEPARATOR_STRING :: "\\"
} else {
	SEPARATOR :: '/'
	SEPARATOR_STRING :: "/"
}

is_separator :: proc(c: u8) -> bool {
	when ODIN_OS == .Windows { return c == '\\' || c == '/' } else { return c == '/' }
}

// The length of the root at the start of `path`: "/" (1), "C:\" (3), "\\server\share\" (to the share's end), 0: none.
root_length :: proc(path: string) -> int {
	when ODIN_OS == .Windows {
		if len(path) >= 2 && path[1] == ':' {
			return len(path) >= 3 && is_separator(path[2]) ? 3 : 2
		}
		if len(path) >= 2 && is_separator(path[0]) && is_separator(path[1]) {
			// \\server\share\
			n := 0
			for i in 2 ..< len(path) {
				if is_separator(path[i]) {
					n += 1
					if n == 2 { return i + 1 }
				}
			}
			return len(path)
		}
		return 0
	} else {
		return len(path) > 0 && path[0] == '/' ? 1 : 0
	}
}

is_root :: proc(path: string) -> bool { return len(path) > 0 && root_length(path) == len(path) }

// The path with the system's separators, "~" expanded, no "." or ".." part, no doubled or trailing separator.
clean :: proc(path: string, allocator := context.allocator) -> string {
	p := strings.trim_space(path)
	if p == "~" || strings.has_prefix(p, "~/") || strings.has_prefix(p, "~\\") {
		p = strings.concatenate({home(context.temp_allocator), p[1:]}, context.temp_allocator)
	}
	when ODIN_OS == .Windows {
		p, _ = strings.replace_all(p, "/", "\\", context.temp_allocator)
		if len(p) == 2 && p[1] == ':' { p = strings.concatenate({p, "\\"}, context.temp_allocator) }
	}
	root := root_length(p)
	parts := make([dynamic]string, context.temp_allocator)
	rest := p[root:]
	for part in strings.split_iterator(&rest, SEPARATOR_STRING) {
		switch part {
		case "", ".":
		case "..":
			if len(parts) > 0 { pop(&parts) }
		case:
			append(&parts, part)
		}
	}
	b := strings.builder_make(allocator)
	strings.write_string(&b, p[:root])
	for part, i in parts {
		if i > 0 { strings.write_byte(&b, SEPARATOR) }
		strings.write_string(&b, part)
	}
	return strings.to_string(b)
}

join :: proc(dir, name: string, allocator := context.allocator) -> string {
	if dir == "" { return strings.clone(name, allocator) }
	if is_separator(dir[len(dir) - 1]) { return strings.concatenate({dir, name}, allocator) }
	return strings.concatenate({dir, SEPARATOR_STRING, name}, allocator)
}

// The folder that holds `path` (a slice of it), "" for a root.
parent :: proc(path: string) -> string {
	root := root_length(path)
	if len(path) <= root { return "" }
	i := len(path) - 1
	for i >= root && !is_separator(path[i]) { i -= 1 }
	if i < root { return path[:root] }
	return path[:max(i, root)]
}

// The last part of `path` (a slice of it); a root is its own name.
base :: proc(path: string) -> string {
	root := root_length(path)
	if len(path) <= root { return path }
	i := len(path) - 1
	for i >= root && !is_separator(path[i]) { i -= 1 }
	return path[i + 1:]
}

// The extension of a name without its dot, "" when it has none (".bashrc" has none).
extension :: proc(name: string) -> string {
	i := strings.last_index_byte(name, '.')
	if i <= 0 || i == len(name) - 1 { return "" }
	return name[i + 1:]
}

// The parts of a path from its root: for "/home/me" the crumbs "/", "home", "me" with the paths "/", "/home", "/home/me"
// (slices of `path`).
Crumb :: struct {
	name, path: string,
}

crumbs :: proc(path: string, allocator := context.temp_allocator) -> []Crumb {
	out := make([dynamic]Crumb, allocator)
	root := root_length(path)
	if root > 0 { append(&out, Crumb{name = path[:root], path = path[:root]}) }
	start := root
	for i in root ..= len(path) {
		if i == len(path) || is_separator(path[i]) {
			if i > start { append(&out, Crumb{name = path[start:i], path = path[:i]}) }
			start = i + 1
		}
	}
	return out[:]
}

home :: proc(allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		if v := os.get_env("USERPROFILE", allocator); v != "" { return v }
		return strings.clone("C:\\", allocator)
	} else {
		if v := os.get_env("HOME", allocator); v != "" { return v }
		return strings.clone("/", allocator)
	}
}
