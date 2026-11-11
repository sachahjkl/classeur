#+build linux
package fs

// Linux: the trash of freedesktop.org ($XDG_DATA_HOME/Trash/files), the shares gvfs mounts as folders (FUSE, under
// $XDG_RUNTIME_DIR/gvfs: `gio mount <uri>` mounts one) and the kernel's mounts of shares (/proc/self/mountinfo).

import "core:os"
import "core:strings"
import "core:sys/linux"

// The folder gvfs mounts its shares under ("" when there is no runtime folder).
gvfs_dir :: proc(allocator := context.temp_allocator) -> string {
	run := os.get_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if run == "" { run = strings.concatenate({"/run/user/", uid_text()}, context.temp_allocator) }
	return strings.concatenate({run, "/gvfs"}, allocator)
}

@(private = "file")
uid_text :: proc() -> string {
	buf: [16]u8
	n := linux.getuid()
	i := len(buf)
	for {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
		if n == 0 { break }
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}

// The trash's folder of the files in it (trash_linux.odin's home trash).
trash_files_dir :: proc(allocator := context.temp_allocator) -> string {
	return join(home_trash(context.temp_allocator), "files", allocator)
}

location_resolve :: proc(text: string, allocator := context.allocator) -> (r: Location, e: Location_Error) {
	t := strings.trim_space(text)
	if !is_uri(t) {
		if t == "" { return {}, .Not_A_Location }
		return {path = strings.clone(t, allocator), kind = .Path}, .None
	}
	u, _ := uri_parse(t)
	switch {
	case u.scheme == "file":
		return {path = strings.clone(u.path, allocator), kind = .Path}, .None
	case u.scheme == "trash":
		return {path = join_rest(trash_files_dir(), u.path, allocator), kind = .Trash}, .None
	case is_network_scheme(u.scheme):
		uri := uri_text({scheme = u.scheme, user = u.user, host = u.host, port = u.port, path = u.path})
		if p, ok := find_mounted(u, allocator); ok { return {path = p, kind = .Network, uri = strings.clone(uri, allocator)}, .None }
		return {kind = .Network, uri = strings.clone(uri, allocator)}, .Not_Mounted
	}
	return {}, .Not_A_Location
}

// `rest` (a URI's path) under `dir`.
@(private = "file")
join_rest :: proc(dir, rest: string, allocator := context.allocator) -> string {
	r := strings.trim(rest, "/")
	if r == "" { return strings.clone(dir, allocator) }
	return strings.concatenate({dir, "/", r}, allocator)
}

// The folder a mounted share holds the URI's path at: gvfs's mounts, then the kernel's.
@(private = "file")
find_mounted :: proc(u: Uri, allocator := context.allocator) -> (path: string, ok: bool) {
	dir := gvfs_dir()
	entries, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
	for e in entries {
		g := gvfs_name_parse(e.name) or_continue
		if rest, holds := gvfs_holds(g, u); holds { return join_rest(e.fullpath, rest, allocator), true }
	}
	for m in kernel_mounts(context.temp_allocator) {
		mu, _ := uri_parse(m.uri)
		if mu.scheme != u.scheme || !strings.equal_fold(mu.host, u.host) { continue }
		prefix := strings.trim_suffix(mu.path, "/")
		p := u.path
		if p == prefix || strings.has_prefix(p, strings.concatenate({prefix, "/"}, context.temp_allocator)) {
			return join_rest(m.path, p[len(prefix):], allocator), true
		}
	}
	return
}

// Mounts a share (blocks: call it on a worker): `gio mount <uri>`, which asks for a password through the session's
// agent when the share wants one. ok = false: `why` says what gio said.
share_mount :: proc(uri: string, allocator := context.temp_allocator) -> (ok: bool, why: string) {
	state, stdout, stderr, err := os.process_exec({command = {"gio", "mount", uri}}, context.temp_allocator)
	if err != nil { return false, strings.clone("gio is not there: gvfs mounts the shares", allocator) }
	if state.exited && state.exit_code == 0 { return true, "" }
	msg := strings.trim_space(string(stderr))
	if msg == "" { msg = strings.trim_space(string(stdout)) }
	if msg == "" { msg = "gio mount failed" }
	return false, strings.clone(msg, allocator)
}

location_display :: proc(path: string, allocator := context.allocator) -> string {
	if root, uri, ok := share_root(path, context.temp_allocator); ok {
		rest := strings.trim_prefix(path[len(root):], "/")
		if rest == "" { return strings.clone(uri, allocator) }
		return strings.concatenate({strings.trim_suffix(uri, "/"), "/", percent_encode(rest)}, allocator)
	}
	return strings.clone(path, allocator)
}

share_root :: proc(path: string, allocator := context.allocator) -> (root, uri: string, ok: bool) {
	dir := gvfs_dir()
	if strings.has_prefix(path, strings.concatenate({dir, "/"}, context.temp_allocator)) {
		name := path[len(dir) + 1:]
		if i := strings.index_byte(name, '/'); i >= 0 { name = name[:i] }
		g := gvfs_name_parse(name) or_return
		u := gvfs_uri(g)
		if u == "" { return }
		return strings.concatenate({dir, "/", name}, allocator), strings.clone(u, allocator), true
	}
	for m in kernel_mounts(context.temp_allocator) {
		if path == m.path || strings.has_prefix(path, strings.concatenate({m.path, "/"}, context.temp_allocator)) {
			return strings.clone(m.path, allocator), strings.clone(m.uri, allocator), true
		}
	}
	return
}

network_shares :: proc(allocator := context.allocator) -> []Share {
	out := make([dynamic]Share, allocator)
	dir := gvfs_dir()
	entries, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
	for e in entries {
		g := gvfs_name_parse(e.name) or_continue
		uri := gvfs_uri(g)
		if uri == "" { continue }
		append(&out, Share{path = strings.clone(e.fullpath, allocator), label = share_label(uri, allocator), uri = strings.clone(uri, allocator)})
	}
	for m in kernel_mounts(context.temp_allocator) {
		append(&out, Share{path = strings.clone(m.path, allocator), label = share_label(m.uri, allocator), uri = strings.clone(m.uri, allocator)})
	}
	return out[:]
}

// The kernel's mounts of shares: where, and the URI their source stands for.
@(private = "file")
kernel_mounts :: proc(allocator := context.temp_allocator) -> []Share {
	out := make([dynamic]Share, allocator)
	data, err := os.read_entire_file("/proc/self/mountinfo", context.temp_allocator)
	if err != nil { return out[:] }
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		// id parent major:minor root mount-point options [optional...] - type source super-options
		fields := strings.fields(line, context.temp_allocator)
		dash := -1
		for f, i in fields { if f == "-" { dash = i; break } }
		if dash < 5 || dash + 2 >= len(fields) { continue }
		uri := mount_source_uri(fields[dash + 1], unescape_octal(fields[dash + 2], context.temp_allocator))
		if uri == "" { continue }
		append(&out, Share{path = unescape_octal(fields[4], context.temp_allocator), uri = uri})
	}
	return out[:]
}
