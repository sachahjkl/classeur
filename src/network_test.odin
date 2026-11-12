package classeur

// The devices of the network: the DNS messages read (packets built here: no network is asked), the devices made of
// them and merged by host, the sidebar's Network section with no share mounted, a device's row opening its service.

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "gt:testkit"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

// A DNS answer as a responder sends it: a header, then records, a name written out or pointing back to one before it.
@(private = "file")
Packet :: struct {
	b:       [dynamic]u8,
	records: int,
}

@(private = "file")
packet_new :: proc() -> Packet {
	p := Packet{b = make([dynamic]u8, context.temp_allocator)}
	resize(&p.b, 12)
	return p
}

@(private = "file")
put16 :: proc(p: ^Packet, v: int) { append(&p.b, u8(v >> 8), u8(v)) }

// A name written out; where it starts (what a pointer to it says).
@(private = "file")
put_name :: proc(p: ^Packet, name: string) -> int {
	at := len(p.b)
	rest := name
	for label in strings.split_iterator(&rest, ".") {
		append(&p.b, u8(len(label)))
		append(&p.b, ..transmute([]u8)label)
	}
	append(&p.b, 0)
	return at
}

// A record's start: its owner (written out, or a pointer to `pointer`), its type, class IN, a TTL; where its size goes.
@(private = "file")
record_begin :: proc(p: ^Packet, owner: string, type: int, pointer := -1) -> int {
	if pointer >= 0 { append(&p.b, u8(0xC0 | pointer >> 8), u8(pointer)) } else { put_name(p, owner) }
	put16(p, type)
	put16(p, 1)
	put16(p, 0)
	put16(p, 120)
	at := len(p.b)
	put16(p, 0)
	p.records += 1
	return at
}

@(private = "file")
record_end :: proc(p: ^Packet, size_at: int) {
	n := len(p.b) - size_at - 2
	p.b[size_at], p.b[size_at + 1] = u8(n >> 8), u8(n)
}

// The header: an answer (QR, AA), the records counted as answers.
@(private = "file")
packet_done :: proc(p: ^Packet) -> []u8 {
	p.b[2], p.b[3] = 0x84, 0
	p.b[6], p.b[7] = u8(p.records >> 8), u8(p.records)
	return p.b[:]
}

// A NAS that shares by SMB and WebDAV (its folder in TXT), its address, and a printer's service that shares no file.
@(private = "file")
nas_answer :: proc() -> []u8 {
	p := packet_new()
	at := record_begin(&p, "_smb._tcp.local", fs.DNS_PTR)
	smb_instance := put_name(&p, "NAS._smb._tcp.local")
	record_end(&p, at)
	at = record_begin(&p, "", fs.DNS_SRV, pointer = smb_instance)
	put16(&p, 0)
	put16(&p, 0)
	put16(&p, 445)
	put_name(&p, "nas.local")
	record_end(&p, at)
	at = record_begin(&p, "nas.local", fs.DNS_A)
	append(&p.b, 192, 168, 1, 10)
	record_end(&p, at)
	at = record_begin(&p, "_webdav._tcp.local", fs.DNS_PTR)
	put_name(&p, "NAS._webdav._tcp.local")
	record_end(&p, at)
	at = record_begin(&p, "NAS._webdav._tcp.local", fs.DNS_SRV)
	put16(&p, 0)
	put16(&p, 0)
	put16(&p, 8080)
	put_name(&p, "nas.local")
	record_end(&p, at)
	at = record_begin(&p, "NAS._webdav._tcp.local", fs.DNS_TXT)
	txt := "path=/dav"
	append(&p.b, u8(len(txt)))
	append(&p.b, ..transmute([]u8)txt)
	record_end(&p, at)
	at = record_begin(&p, "_ipp._tcp.local", fs.DNS_PTR)
	put_name(&p, "Printer._ipp._tcp.local")
	record_end(&p, at)
	return packet_done(&p)
}

@(test)
test_network_answer_read :: proc(t: ^testing.T) {
	data := nas_answer()
	records, ok := fs.dns_parse(data)
	testing.expect(t, ok, "the answer is read")
	testing.expect_value(t, len(records), 7)
	list := make([dynamic]fs.Network_Device)
	defer fs.devices_destroy(list[:])
	fs.devices_from_records(&list, records[:])
	// (one device: the two services of one host; the printer's is no file service)
	if !testing.expect_value(t, len(list), 1) { return }
	d := list[0]
	testing.expect_value(t, d.name, "NAS")
	testing.expect_value(t, d.host, "nas.local")
	testing.expect_value(t, d.address, "192.168.1.10")
	if !testing.expect_value(t, len(d.services), 2) { return }
	testing.expect_value(t, d.services[0].uri, "smb://nas.local/")
	testing.expect_value(t, d.services[1].uri, "dav://nas.local:8080/dav")
	testing.expect_value(t, fs.device_kind(d), fs.Device_Kind.File_Server)
}

@(test)
test_network_malformed_refused :: proc(t: ^testing.T) {
	data := nas_answer()
	// (every packet cut short: refused, nothing read past its end)
	for n in 0 ..< len(data) {
		_, ok := fs.dns_parse(data[:n])
		testing.expectf(t, !ok, "cut at %d: refused", n)
	}
	// a name whose pointer points to itself
	loop := []u8{0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 120, 0, 4, 1, 2, 3, 4}
	_, loop_ok := fs.dns_parse(loop)
	testing.expect(t, !loop_ok, "a loop of pointers: refused")
	// a label longer than the packet
	long := []u8{0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0x3F, 'a', 'b'}
	_, long_ok := fs.dns_parse(long)
	testing.expect(t, !long_ok, "a label past the end: refused")
	// a query, not an answer (another program's, or ours)
	query := fs.dns_query({"_smb._tcp.local"}, fs.DNS_PTR)
	_, query_ok := fs.dns_parse(query)
	testing.expect(t, !query_ok, "a query: not read as an answer")
	// an A record of the wrong size
	bad_a := []u8{0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 'h', 0, 0, 1, 0, 1, 0, 0, 0, 120, 0, 3, 1, 2, 3}
	_, bad_ok := fs.dns_parse(bad_a)
	testing.expect(t, !bad_ok, "an address of 3 bytes: refused")
}

@(test)
test_network_devices_merged :: proc(t: ^testing.T) {
	list := make([dynamic]fs.Network_Device)
	defer fs.devices_destroy(list[:])
	fs.device_add(&list, "Shelf", "shelf.local", "", "sftp", "sftp://shelf.local/")
	// (its Windows name: the same host; SMB comes before SFTP)
	fs.device_add(&list, "SHELF", "SHELF", "", "smb", "smb://SHELF/")
	// (_ssh and _sftp-ssh: one URI, once)
	fs.device_add(&list, "Shelf", "Shelf.local", "10.0.0.2", "sftp", "sftp://shelf.local/")
	// (its SMB announced by multicast DNS too: one service, two spellings of its host)
	fs.device_add(&list, "Shelf", "shelf.local", "", "smb", "smb://shelf.local/")
	fs.device_add(&list, "", "pc.local", "", "smb", "smb://pc.local/")
	if !testing.expect_value(t, len(list), 2) { return }
	d := list[0]
	testing.expect_value(t, d.name, "Shelf")
	testing.expect_value(t, d.address, "10.0.0.2")
	if !testing.expect_value(t, len(d.services), 2) { return }
	testing.expect_value(t, d.services[0].uri, "smb://SHELF/")
	testing.expect_value(t, d.services[1].uri, "sftp://shelf.local/")
	// (no name announced: the host's, without .local)
	testing.expect_value(t, list[1].name, "pc")
}

// The Network section shows with no share mounted: the search's answer said (none found), then the devices given to
// it; the command searches again.
@(test)
test_network_section :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 900})
		context.allocator = runtime.heap_allocator()
		// (the sections above it closed: its rows on the screen)
		app.side_open[.Bookmarks], app.side_open[.Storage], app.side_open[.Places] = false, false, false
		if app.shares != nil { fs.shares_destroy(app.shares) }
		app.shares = nil
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Network") != nil, "the section, with no share mounted")
		testing.expect(t, app.devices_asked > 0, "a search when it first showed")
		testing.expect(t, session.find_text(s, "No device found") != nil, "the search's answer said")
		asked := app.devices_asked
		session.key(s, .F5, {.Ctrl, .Shift})
		testing.expect_value(t, app.devices_asked, asked + 1)
		wait_read(s)
		testing.expect(t, !app.devices_searching, "the search answered")
		list := make([dynamic]fs.Network_Device)
		fs.device_add(&list, "Shelf", "shelf.local", "", "sftp", "sftp://shelf.local/")
		if app.devices != nil { fs.devices_destroy(app.devices) }
		app.devices = list[:]
		session.frames(s, 3)
		testing.expect(t, session.find_text(s, "Shelf") != nil, "the device listed")
		testing.expect(t, session.find_text(s, "No device found") == nil, "no line of none")
	})
}

// A click on a device opens its first service in the tab (Linux: a share gvfs mounted, in a runtime folder made for the
// test); its menu lists each service.
@(test)
test_network_device_opens :: proc(t: ^testing.T) {
	when ODIN_OS != .Linux { return }
	unwatched.run(t, proc(t: ^testing.T) {
		context.allocator = runtime.heap_allocator()
		run := strings.clone(testkit.temp_folder(t, "classeur_run"))
		defer delete(run)
		share := fs.join(run, "gvfs/sftp:host=shelf.local")
		defer delete(share)
		_ = os.make_directory_all(fs.join(share, "Backups", context.temp_allocator))
		before := strings.clone(os.get_env("XDG_RUNTIME_DIR", context.temp_allocator))
		defer { os.set_env("XDG_RUNTIME_DIR", before); delete(before) }
		os.set_env("XDG_RUNTIME_DIR", run)
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir}, size = {1200, 900})
		context.allocator = runtime.heap_allocator()
		app.side_open[.Bookmarks], app.side_open[.Storage], app.side_open[.Places] = false, false, false
		list := make([dynamic]fs.Network_Device)
		fs.device_add(&list, "Shelf", "shelf.local", "", "sftp", "sftp://shelf.local/")
		fs.device_add(&list, "Shelf", "shelf.local", "", "ftp", "ftp://shelf.local/")
		if app.devices != nil { fs.devices_destroy(app.devices) }
		app.devices = list[:]
		session.frames(s, 3)
		session.click(s, "device0")
		wait_read(s)
		tab := current_tab(app)
		testing.expect_value(t, tab.path, share)
		testing.expect(t, session.find_text(s, "Backups") != nil, "the share's folders")
		session.click(s, "device0", .Right)
		testing.expect(t, session.find_text(s, "Open sftp://shelf.local/") != nil && session.find_text(s, "Open ftp://shelf.local/") != nil, "its menu: each service")
	})
}
