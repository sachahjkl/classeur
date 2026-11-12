// Locations: the places classeur is given that are not plain paths, made paths the file system reads, on every system. A file manager's address bar, a command line, another program asking to open something give these:
//
//   /home/a/b, C:\a\b, \\server\share\b    a path: as it is
//   file:///home/a%20b, file://server/share   a file's URI: its path (a server's: \\server\share on Windows)
//   trash:///, trash:///folder              the trash (freedesktop.org's on Linux: ~/.local/share/Trash/files)
//   smb://host/share/b, sftp://user@host/b, ftp://host/b, dav://host/b, davs://host/b, nfs://host/export/b, afp://host/v/b
//                                           a share of the network: on Linux the folder gvfs mounts it at (FUSE, under
//                                           $XDG_RUNTIME_DIR/gvfs), or a mount of the kernel's (/proc/self/mountinfo: nfs,
//                                           cifs, sshfs); on Windows an SMB share is its UNC path, read directly
//
//   location_resolve(text)   the path for a text (never blocks); .Not_Mounted: the share is not mounted yet: share_mount(uri)
//                            on a worker (Linux: `gio mount`, which may ask for a password through the session's agent),
//                            then location_resolve again
//   location_display(path)   the URI a path under a share stands for ("smb://host/share/b"), else the path
//   share_root(path)         the folder a share is mounted at and its URI: a breadcrumb's first part
//   network_shares()         the shares mounted now: the sidebar's Network section
//
// The parsing parts are pure (uri_parse, gvfs_name_parse, mount_source_uri): the tests run them on every system. (One
// program reads them: should another, they go to gui_toolkit as they are, needing nothing but core.)
package fs

import "core:strconv"
import "core:strings"

Location_Kind :: enum u8 {
	Path,      // a path of the file system, or a file's URI
	Trash,     // the trash
	Network,   // a share of the network
}

Location_Error :: enum u8 {
	None,
	Not_A_Location,   // neither a path nor a URI of a scheme known here
	Not_Mounted,      // a share not mounted now: share_mount(uri) first
	Unsupported,      // a scheme this system does not reach (sftp:// on Windows, the trash's folder on Windows)
}

Location :: struct {
	path: string,   // the folder or file to read ("" when not reached)
	kind: Location_Kind,
	uri:  string,   // the share's URI, for mount (Network)
}

// The parts of a URI: "smb://user@host:445/share/b" -> {"smb", "user", "host", 445, "/share/b"} (the path percent-decoded).
Uri :: struct {
	scheme: string,
	user:   string,
	host:   string,
	port:   int,
	path:   string,
}

// The schemes of the network's shares known here.
NETWORK_SCHEMES :: [?]string{"smb", "sftp", "ftp", "ftps", "dav", "davs", "nfs", "afp"}

// Whether a text is a URI ("scheme://...") rather than a path ("C:\" is not one: a scheme has more than one letter).
is_uri :: proc(text: string) -> bool {
	i := strings.index(text, "://")
	if i < 2 { return false }
	for c in text[:i] {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '+' || c == '-' || c == '.') { return false }
	}
	return true
}

// A URI's parts (temp memory); ok = false: not a URI.
uri_parse :: proc(text: string, allocator := context.temp_allocator) -> (u: Uri, ok: bool) {
	t := strings.trim_space(text)
	if !is_uri(t) { return }
	i := strings.index(t, "://")
	u.scheme = strings.to_lower(t[:i], allocator)
	rest := t[i + 3:]
	authority := rest
	if j := strings.index_byte(rest, '/'); j >= 0 {
		authority, u.path = rest[:j], percent_decode(rest[j:], allocator)
	} else {
		u.path = "/"
	}
	if at := strings.last_index_byte(authority, '@'); at >= 0 {
		u.user = percent_decode(authority[:at], allocator)
		authority = authority[at + 1:]
	}
	// the port after the host's last ':' (an IPv6 host is in brackets: its colons are not the port's)
	host := authority
	port_from := 0
	if strings.has_prefix(authority, "[") {
		if close := strings.index_byte(authority, ']'); close >= 0 { port_from = close + 1 }
	}
	if colon := strings.last_index_byte(authority[port_from:], ':'); colon >= 0 {
		colon += port_from
		if p, pok := strconv.parse_int(authority[colon + 1:]); pok { u.port = p }
		host = authority[:colon]
	}
	u.host = percent_decode(host, allocator)
	if u.path == "" { u.path = "/" }
	return u, true
}

// "%20" and the like back to their bytes; a '%' not followed by two hex digits stays.
percent_decode :: proc(s: string, allocator := context.temp_allocator) -> string {
	if strings.index_byte(s, '%') < 0 { return strings.clone(s, allocator) }
	b := strings.builder_make(allocator)
	hex :: proc(c: u8) -> (int, bool) {
		switch c {
		case '0' ..= '9': return int(c - '0'), true
		case 'a' ..= 'f': return int(c - 'a' + 10), true
		case 'A' ..= 'F': return int(c - 'A' + 10), true
		}
		return 0, false
	}
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' && i + 2 < len(s) {
			hi, ok1 := hex(s[i + 1])
			lo, ok2 := hex(s[i + 2])
			if ok1 && ok2 {
				strings.write_byte(&b, u8(hi * 16 + lo))
				i += 2
				continue
			}
		}
		strings.write_byte(&b, s[i])
	}
	return strings.to_string(b)
}

// A path's characters a URI cannot hold as they are, escaped ("a b" -> "a%20b"); '/' stays.
percent_encode :: proc(s: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	hex := "0123456789ABCDEF"
	for i in 0 ..< len(s) {
		c := s[i]
		if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~' || c == '/' {
			strings.write_byte(&b, c)
		} else {
			strings.write_byte(&b, '%')
			strings.write_byte(&b, hex[c >> 4])
			strings.write_byte(&b, hex[c & 15])
		}
	}
	return strings.to_string(b)
}

is_network_scheme :: proc(scheme: string) -> bool {
	schemes := NETWORK_SCHEMES
	for s in schemes { if s == scheme { return true } }
	return false
}

// A share's URI, written back: scheme://[user@]host[:port]/path.
uri_text :: proc(u: Uri, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, u.scheme)
	strings.write_string(&b, "://")
	if u.user != "" {
		strings.write_string(&b, percent_encode(u.user))
		strings.write_byte(&b, '@')
	}
	strings.write_string(&b, u.host)
	if u.port > 0 {
		strings.write_byte(&b, ':')
		strings.write_int(&b, u.port)
	}
	p := u.path == "" ? "/" : u.path
	if p[0] != '/' { strings.write_byte(&b, '/') }
	strings.write_string(&b, percent_encode(p))
	return strings.to_string(b)
}

////////////////////////////////
// gvfs (Linux): the name of the folder a share is mounted at, under $XDG_RUNTIME_DIR/gvfs

// A gvfs mount's name, "smb-share:server=host,share=docs,user=a", as its type and its fields (values percent-decoded,
// "prefix=%2Fexport" -> "/export"); ok = false: not one.
Gvfs_Name :: struct {
	type:   string,              // smb-share, sftp, ftp, dav, nfs, afp-volume...
	fields: map[string]string,   // (temp memory)
}

gvfs_name_parse :: proc(name: string, allocator := context.temp_allocator) -> (g: Gvfs_Name, ok: bool) {
	colon := strings.index_byte(name, ':')
	if colon <= 0 { return }
	g.type = name[:colon]
	g.fields = make(map[string]string, allocator = allocator)
	rest := name[colon + 1:]
	for pair in strings.split_iterator(&rest, ",") {
		eq := strings.index_byte(pair, '=')
		if eq <= 0 { continue }
		g.fields[pair[:eq]] = percent_decode(pair[eq + 1:], allocator)
	}
	return g, true
}

// The URI a gvfs mount stands for, and the part of a URI's path its folder holds ("smb-share:server=h,share=s" is
// smb://h/s/: a path under the folder adds to it). "" when the type is not one known here.
gvfs_uri :: proc(g: Gvfs_Name, allocator := context.temp_allocator) -> string {
	u := Uri{host = g.fields["host"], user = g.fields["user"]}
	if p, ok := strconv.parse_int(g.fields["port"]); ok { u.port = p }
	switch g.type {
	case "smb-share":
		u.scheme, u.host, u.path = "smb", g.fields["server"], strings.concatenate({"/", g.fields["share"]}, allocator)
	case "smb-server":
		// (a server's root, smb://host/: its shares, what a device found on the network opens)
		u.scheme, u.host, u.path = "smb", g.fields["server"], "/"
	case "sftp", "ftp", "ftps":
		u.scheme, u.path = g.type, "/"
	case "dav":
		u.scheme = g.fields["ssl"] == "true" ? "davs" : "dav"
		u.path = g.fields["prefix"] != "" ? g.fields["prefix"] : "/"
	case "nfs":
		u.scheme, u.path = "nfs", g.fields["prefix"] != "" ? g.fields["prefix"] : "/"
	case "afp-volume":
		u.scheme, u.path = "afp", strings.concatenate({"/", g.fields["volume"]}, allocator)
	case:
		return ""
	}
	return uri_text(u, allocator)
}

// Whether a gvfs mount holds a URI's share, and the part of the URI's path under its folder ("" its folder itself).
gvfs_holds :: proc(g: Gvfs_Name, u: Uri) -> (rest: string, ok: bool) {
	same :: proc(a, b: string) -> bool { return strings.equal_fold(a, b) }
	// (a user or a port the URI says must be the mount's; one it does not say matches any)
	if u.user != "" && g.fields["user"] != "" && u.user != g.fields["user"] { return }
	if u.port > 0 {
		p, _ := strconv.parse_int(g.fields["port"])
		if p != 0 && p != u.port { return }
	}
	under :: proc(path, prefix: string) -> (rest: string, ok: bool) {
		p := strings.trim_suffix(prefix, "/")
		if p == "" { return strings.trim_prefix(path, "/"), true }
		if path == p { return "", true }
		if strings.has_prefix(path, p) && len(path) > len(p) && path[len(p)] == '/' { return path[len(p) + 1:], true }
		return
	}
	switch u.scheme {
	case "smb":
		// (a server's mount holds its root alone: a share's own mount holds what is in it)
		if g.type == "smb-server" && same(g.fields["server"], u.host) && strings.trim(u.path, "/") == "" { return "", true }
		if g.type != "smb-share" || !same(g.fields["server"], u.host) { return }
		parts := strings.split_n(strings.trim_prefix(u.path, "/"), "/", 2, context.temp_allocator)
		if len(parts) == 0 || !same(parts[0], g.fields["share"]) { return }
		return len(parts) > 1 ? parts[1] : "", true
	case "sftp", "ftp", "ftps":
		if g.type != u.scheme || !same(g.fields["host"], u.host) { return }
		return strings.trim_prefix(u.path, "/"), true
	case "dav", "davs":
		if g.type != "dav" || !same(g.fields["host"], u.host) || (g.fields["ssl"] == "true") != (u.scheme == "davs") { return }
		return under(u.path, g.fields["prefix"])
	case "nfs":
		if g.type != "nfs" || !same(g.fields["host"], u.host) { return }
		return under(u.path, g.fields["prefix"])
	case "afp":
		if g.type != "afp-volume" || !same(g.fields["host"], u.host) { return }
		parts := strings.split_n(strings.trim_prefix(u.path, "/"), "/", 2, context.temp_allocator)
		if len(parts) == 0 || !same(parts[0], g.fields["volume"]) { return }
		return len(parts) > 1 ? parts[1] : "", true
	}
	return
}

////////////////////////////////
// The kernel's mounts of shares (Linux): their source as a URI

// The URI a mount of the kernel stands for, from its type and its source ("nfs4", "host:/export" -> nfs://host/export;
// "cifs", "//host/share" -> smb://host/share; "fuse.sshfs", "user@host:/path" -> sftp://user@host/path); "" for a
// type that is no share.
mount_source_uri :: proc(fstype, source: string, allocator := context.temp_allocator) -> string {
	switch fstype {
	case "nfs", "nfs4":
		colon := strings.index_byte(source, ':')
		if colon <= 0 { return "" }
		return uri_text({scheme = "nfs", host = source[:colon], path = source[colon + 1:]}, allocator)
	case "cifs", "smb3", "smbfs":
		s := strings.trim_prefix(source, "//")
		parts := strings.split_n(s, "/", 2, context.temp_allocator)
		if len(parts) < 2 { return "" }
		return uri_text({scheme = "smb", host = parts[0], path = strings.concatenate({"/", parts[1]}, context.temp_allocator)}, allocator)
	case "fuse.sshfs":
		colon := strings.last_index_byte(source, ':')
		if colon <= 0 { return "" }
		u := Uri{scheme = "sftp", host = source[:colon], path = source[colon + 1:]}
		if at := strings.index_byte(u.host, '@'); at >= 0 { u.user, u.host = u.host[:at], u.host[at + 1:] }
		return uri_text(u, allocator)
	}
	return ""
}

// A share mounted now: the folder it is at, a name for it, its URI.
Share :: struct {
	path:  string,
	label: string,
	uri:   string,
}

shares_destroy :: proc(m: []Share, allocator := context.allocator) {
	for x in m {
		delete(x.path, allocator)
		delete(x.label, allocator)
		delete(x.uri, allocator)
	}
	delete(m, allocator)
}

// A share's name for a list: "docs on host" (smb, afp), "host" (sftp, ftp, dav), "export on host" (nfs).
share_label :: proc(uri: string, allocator := context.allocator) -> string {
	u, ok := uri_parse(uri)
	if !ok { return strings.clone(uri, allocator) }
	name := strings.trim(u.path, "/")
	if i := strings.last_index_byte(name, '/'); i >= 0 { name = name[i + 1:] }
	if name == "" { return strings.clone(u.host, allocator) }
	return strings.concatenate({name, " on ", u.host}, allocator)
}
