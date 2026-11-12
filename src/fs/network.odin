// The file servers of the local network, found by asking: one query of multicast DNS (DNS-SD, RFC 6762 and 6763) for
// the services that share files, the answers taken for a moment. A device is a host with its services, each with the
// URI that opens it (location_resolve reads them).
//
//   network_devices()        asks the network (blocks NETWORK_ASK_FOR: call it on a worker); Windows adds the
//                            computers its network neighbourhood knows (network_windows.odin)
//   dns_parse(packet)        a DNS message's records (pure: the tests give it packets they build)
//   devices_from_records     the devices the records describe
//   device_add               one service of a host, added to a list where each host is once
//
// No group is joined: a query from a port of its own is answered to that port (RFC 6762 §6.7), and on Linux a socket
// bound to 5353 beside the system's responder gets the answers sent to the group, which that responder joined
// (ASK_WAYS).
package fs

import "core:net"
import "core:strings"
import "core:time"

NETWORK_ASK_FOR  :: 1500 * time.Millisecond   // how long the answers are taken
NETWORK_ASK_AGAIN :: 500 * time.Millisecond   // the query sent once more (a lost packet; the names of instances the first answers gave without their host)

DNS_A    :: 1
DNS_PTR  :: 12
DNS_TXT  :: 16
DNS_AAAA :: 28
DNS_SRV  :: 33

// A service type that shares files: the scheme of its URIs and its usual port (not written in the URI).
Service_Type :: struct {
	name:   string,
	scheme: string,
	port:   int,
}

// In the order a device's services are offered: its first opens on a click.
@(rodata)
SERVICE_TYPES := [?]Service_Type{
	{"_smb._tcp.local", "smb", 445},
	{"_afpovertcp._tcp.local", "afp", 548},
	{"_nfs._tcp.local", "nfs", 2049},
	{"_webdavs._tcp.local", "davs", 443},
	{"_webdav._tcp.local", "dav", 80},
	{"_sftp-ssh._tcp.local", "sftp", 22},
	{"_ssh._tcp.local", "sftp", 22},
	{"_ftp._tcp.local", "ftp", 21},
}

Network_Service :: struct {
	scheme: string,
	uri:    string,
}

Network_Device :: struct {
	name:     string,   // the name it announces ("NAS"), else its host's
	host:     string,   // "nas.local"
	address:  string,   // "192.168.1.10" ("": not given)
	services: [dynamic]Network_Service,   // in the order of SERVICE_TYPES
}

// What a device is, for its icon: a file server (SMB, AFP, NFS), a computer reached by SSH, a web or FTP server.
Device_Kind :: enum u8 { File_Server, Computer, Web }

device_kind :: proc(d: Network_Device) -> Device_Kind {
	if len(d.services) == 0 { return .File_Server }
	switch d.services[0].scheme {
	case "sftp": return .Computer
	case "dav", "davs", "ftp": return .Web
	}
	return .File_Server
}

devices_destroy :: proc(list: []Network_Device, allocator := context.allocator) {
	for d in list {
		delete(d.name, allocator)
		delete(d.host, allocator)
		delete(d.address, allocator)
		for s in d.services {
			delete(s.scheme, allocator)
			delete(s.uri, allocator)
		}
		delete(d.services)
	}
	delete(list, allocator)
}

////////////////////////////////
// The records of a DNS message

Dns_Record :: struct {
	name:     string,     // its owner, lowercase
	type:     u16,
	target:   string,     // PTR, SRV: the name it points to, lowercase
	instance: string,     // PTR: the target's first label as it is (the name a device announces)
	port:     int,        // SRV
	address:  string,     // A, AAAA
	txt:      []string,   // TXT: "key=value"...
}

// A DNS message's records (answers, authority, additional; a goodbye, TTL 0, left out), in `allocator`. ok = false:
// not an answer, or cut short or malformed somewhere (then none of it is taken).
dns_parse :: proc(data: []u8, allocator := context.temp_allocator) -> (records: [dynamic]Dns_Record, ok: bool) {
	records = make([dynamic]Dns_Record, allocator)
	if len(data) < 12 { return }
	if u16_at(data, 2) & 0x8000 == 0 { return }   // (a query, not an answer)
	questions := int(u16_at(data, 4))
	count := int(u16_at(data, 6)) + int(u16_at(data, 8)) + int(u16_at(data, 10))
	at := 12
	for _ in 0 ..< questions {
		_, _, next := dns_name(data, at, context.temp_allocator) or_return
		at = next + 4
		if at > len(data) { return }
	}
	for _ in 0 ..< count {
		name, _, next := dns_name(data, at, allocator) or_return
		at = next
		if at + 10 > len(data) { return }
		r := Dns_Record{name = name, type = u16_at(data, at)}
		ttl := u32(u16_at(data, at + 4)) << 16 | u32(u16_at(data, at + 6))
		size := int(u16_at(data, at + 8))
		at += 10
		if at + size > len(data) { return }
		rdata := data[at:at + size]
		switch r.type {
		case DNS_PTR:
			target, instance, _ := dns_name(data, at, allocator) or_return
			r.target, r.instance = target, instance
		case DNS_SRV:
			if size < 7 { return }
			r.port = int(u16_at(data, at + 4))
			target, _, _ := dns_name(data, at + 6, allocator) or_return
			r.target = target
		case DNS_A:
			if size != 4 { return }
			r.address = net.address_to_string(net.IP4_Address{rdata[0], rdata[1], rdata[2], rdata[3]}, allocator)
		case DNS_AAAA:
			if size != 16 { return }
			raw: [16]u8
			copy(raw[:], rdata)
			r.address = net.address_to_string(net.IP6_Address(transmute([8]u16be)raw), allocator)
		case DNS_TXT:
			list := make([dynamic]string, allocator)
			for i := 0; i < size; {
				n := int(rdata[i])
				if i + 1 + n > size { return }
				if n > 0 { append(&list, strings.clone(string(rdata[i + 1:i + 1 + n]), allocator)) }
				i += 1 + n
			}
			r.txt = list[:]
		}
		at += size
		if ttl > 0 { append(&records, r) }
	}
	return records, true
}

@(private = "file")
u16_at :: proc(data: []u8, at: int) -> u16 { return u16(data[at]) << 8 | u16(data[at + 1]) }

// A name at `at` (its labels joined by '.', lowercase), its first label as it is, and where what follows it starts.
// Its pointers are followed, a loop of them refused.
@(private = "file")
dns_name :: proc(data: []u8, at: int, allocator := context.temp_allocator) -> (name, first: string, next: int, ok: bool) {
	b := strings.builder_make(allocator)
	pos := at
	next = -1
	jumps := 0
	labels := 0
	walk: for {
		if pos >= len(data) { return }
		n := int(data[pos])
		switch n & 0xC0 {
		case 0xC0:
			if pos + 1 >= len(data) { return }
			if next < 0 { next = pos + 2 }
			jumps += 1
			if jumps > 32 { return }
			pos = (n & 0x3F) << 8 | int(data[pos + 1])
			continue walk
		case 0x00:
		case:
			return   // (the label types of RFC 6891: not in a name)
		}
		if n == 0 {
			if next < 0 { next = pos + 1 }
			break walk
		}
		if pos + 1 + n > len(data) { return }
		label := data[pos + 1:pos + 1 + n]
		if labels == 0 { first = strings.clone(string(label), allocator) }
		if labels > 0 { strings.write_byte(&b, '.') }
		for c in label { strings.write_byte(&b, c >= 'A' && c <= 'Z' ? c + 32 : c) }
		labels += 1
		if strings.builder_len(b) > 255 { return }
		pos += 1 + n
	}
	return strings.to_string(b), first, next, true
}

////////////////////////////////
// The query

// A query for `names` of type `type` (class IN), id 0 (what a responder echoes for a query from another port).
dns_query :: proc(names: []string, type: u16, allocator := context.temp_allocator) -> []u8 {
	out := make([dynamic]u8, allocator)
	put16 :: proc(out: ^[dynamic]u8, v: u16) { append(out, u8(v >> 8), u8(v)) }
	put16(&out, 0)
	put16(&out, 0)
	put16(&out, u16(len(names)))
	put16(&out, 0)
	put16(&out, 0)
	put16(&out, 0)
	for name in names {
		rest := name
		for label in strings.split_iterator(&rest, ".") {
			if label == "" || len(label) > 63 { continue }
			append(&out, u8(len(label)))
			append(&out, ..transmute([]u8)label)
		}
		append(&out, 0)
		put16(&out, type)
		put16(&out, 1)
	}
	return out[:]
}

////////////////////////////////
// From the records to the devices

// The devices the records describe: an instance of a service type of SERVICE_TYPES (PTR) whose host is known (SRV),
// with its address (A, else AAAA) and its folder (TXT path=, WebDAV's and NFS's).
devices_from_records :: proc(list: ^[dynamic]Network_Device, records: []Dns_Record, allocator := context.allocator) {
	for r in records {
		if r.type != DNS_PTR { continue }
		st := service_type(r.name) or_continue
		srv := record_find(records, r.target, DNS_SRV) or_continue
		host := srv.target
		if host == "" { continue }
		path := "/"
		if txt, found := record_find(records, r.target, DNS_TXT); found {
			for kv in txt.txt { if strings.has_prefix(kv, "path=") && len(kv) > 5 { path = kv[5:] } }
		}
		address := ""
		if a, found := record_find(records, host, DNS_A); found {
			address = a.address
		} else if a6, found6 := record_find(records, host, DNS_AAAA); found6 {
			address = a6.address
		}
		port := srv.port == st.port ? 0 : srv.port
		uri := uri_text({scheme = st.scheme, host = host, port = port, path = path}, context.temp_allocator)
		device_add(list, r.instance, host, address, st.scheme, uri, allocator)
	}
}

@(private = "file")
service_type :: proc(name: string) -> (Service_Type, bool) {
	for st in SERVICE_TYPES { if st.name == name { return st, true } }
	return {}, false
}

@(private = "file")
record_find :: proc(records: []Dns_Record, name: string, type: u16) -> (Dns_Record, bool) {
	for r in records { if r.type == type && r.name == name { return r, true } }
	return {}, false
}

// Whether two names are one host's: "NAS" (a Windows name) is "nas.local" (its multicast DNS name).
host_same :: proc(a, b: string) -> bool {
	short :: proc(s: string) -> string { return strings.trim_suffix(strings.trim_suffix(s, "."), ".local") }
	return strings.equal_fold(short(a), short(b))
}

// One service of a host, added to `list`: to its device when the host is there (the same URI once), else as a new
// device. The strings are copied in `allocator`.
device_add :: proc(list: ^[dynamic]Network_Device, name, host, address, scheme, uri: string, allocator := context.allocator) {
	d: ^Network_Device
	for &x in list^ { if host_same(x.host, host) { d = &x; break } }
	if d == nil {
		append(list, Network_Device{
			name = strings.clone(name != "" ? name : strings.trim_suffix(host, ".local"), allocator),
			host = strings.clone(host, allocator),
			address = strings.clone(address, allocator),
			services = make([dynamic]Network_Service, allocator),
		})
		d = &list^[len(list^) - 1]
	}
	if d.address == "" && address != "" {
		delete(d.address, allocator)
		d.address = strings.clone(address, allocator)
	}
	for s in d.services { if same_service(s.uri, uri) { return } }
	at := len(d.services)
	for s, i in d.services {
		if scheme_rank(scheme) < scheme_rank(s.scheme) { at = i; break }
	}
	inject_at(&d.services, at, Network_Service{scheme = strings.clone(scheme, allocator), uri = strings.clone(uri, allocator)})
}

// Whether two URIs are one service: the same but for the host's spelling ("smb://NAS/", "smb://nas.local/").
@(private = "file")
same_service :: proc(a, b: string) -> bool {
	if a == b { return true }
	ua, a_ok := uri_parse(a)
	ub, b_ok := uri_parse(b)
	return a_ok && b_ok && ua.scheme == ub.scheme && ua.port == ub.port && ua.path == ub.path && ua.user == ub.user && host_same(ua.host, ub.host)
}

@(private = "file")
scheme_rank :: proc(scheme: string) -> int {
	for st, i in SERVICE_TYPES { if st.scheme == scheme { return i } }
	return len(SERVICE_TYPES)
}

////////////////////////////////
// Asking the network

// The ways the query goes out: from a port of its own over IPv4 and IPv6 (the answers come back to it), and from port
// 5353, shared with the system's responder (Avahi), where the answers sent to the group arrive too: a firewall that
// lets mDNS in opens that port, not the other.
@(private = "file")
Ask_Way :: struct {
	family: net.Address_Family,
	target: net.Endpoint,
	shared: bool,   // bound to 5353, shared
}

@(private = "file")
ASK_WAYS := [?]Ask_Way{
	{.IP4, net.IP4_mDNS_Broadcast, false},
	{.IP6, net.IP6_mDNS_Broadcast, false},
	{.IP4, net.IP4_mDNS_Broadcast, true},
}

// A socket for one way, the query sent; ok = false: this way is not there (no IPv6, the port not shared...).
@(private = "file")
ask_open :: proc(way: Ask_Way, query: []u8) -> (s: net.UDP_Socket, ok: bool) {
	err: net.Create_Socket_Error
	s, err = net.make_unbound_udp_socket(way.family)
	if err != .None { return }
	if way.shared {
		if net.set_option(s, .Reuse_Address, true) != .None || net.bind(s, {net.IP4_Any, 5353}) != .None { net.close(s); return }
	}
	// (a short wait for each: the sockets are read in turn)
	wait: time.Duration = 100 * time.Millisecond
	if net.set_option(s, .Receive_Timeout, wait) != .None { net.close(s); return }
	if _, send_err := net.send_udp(s, query, way.target); send_err != .None { net.close(s); return }
	return s, true
}

// The file servers of the network: multicast DNS for NETWORK_ASK_FOR, then what the system knows of its own
// (system_devices_add). Blocks: call it on a worker.
network_devices :: proc(allocator := context.allocator) -> []Network_Device {
	list := make([dynamic]Network_Device, allocator)
	records := make([dynamic]Dns_Record, context.temp_allocator)
	types: [len(SERVICE_TYPES)]string
	for st, i in SERVICE_TYPES { types[i] = st.name }
	query := dns_query(types[:], DNS_PTR)

	WAYS :: len(ASK_WAYS)
	sockets: [WAYS]net.UDP_Socket
	open: [WAYS]bool
	for way, i in ASK_WAYS { sockets[i], open[i] = ask_open(way, query) }
	defer {
		for i in 0 ..< WAYS { if open[i] { net.close(sockets[i]) } }
	}

	start := time.tick_now()
	again := false
	buf: [9000]u8
	for (open != [WAYS]bool{}) && time.tick_since(start) < NETWORK_ASK_FOR {
		if !again && time.tick_since(start) >= NETWORK_ASK_AGAIN {
			again = true
			// (the instances named without their host: asked for it, with the services once more)
			ask := query
			if missing := instances_unresolved(records[:]); len(missing) > 0 { ask = dns_query_more(query, missing) }
			for i in 0 ..< WAYS { if open[i] { _, _ = net.send_udp(sockets[i], ask, ASK_WAYS[i].target) } }
		}
		for i in 0 ..< WAYS {
			if !open[i] { continue }
			n, _, err := net.recv_udp(sockets[i], buf[:])
			#partial switch err {
			case .None:
				if n <= 0 { continue }
				got, ok := dns_parse(buf[:n], context.temp_allocator)
				if ok { append(&records, ..got[:]) }
			case .Timeout, .Would_Block, .Interrupted, .Excess_Truncated, .Connection_Refused:
			case:
				// (a socket that fails at once would turn this loop into a spin: it is left)
				net.close(sockets[i])
				open[i] = false
			}
		}
	}
	devices_from_records(&list, records[:], allocator)
	system_devices_add(&list, allocator)
	return list[:]
}

// The instances of a service type known here that no SRV record placed yet.
@(private = "file")
instances_unresolved :: proc(records: []Dns_Record) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for r in records {
		if r.type != DNS_PTR { continue }
		if _, known := service_type(r.name); !known { continue }
		if _, found := record_find(records, r.target, DNS_SRV); found { continue }
		dup := false
		for x in out { if x == r.target { dup = true; break } }
		if !dup && len(out) < 16 { append(&out, r.target) }
	}
	return out[:]
}

// The query for the service types, with questions for the SRV and TXT of `instances` after them.
@(private = "file")
dns_query_more :: proc(query: []u8, instances: []string) -> []u8 {
	srv := dns_query(instances, DNS_SRV)
	txt := dns_query(instances, DNS_TXT)
	out := make([dynamic]u8, context.temp_allocator)
	append(&out, ..query)
	append(&out, ..srv[12:])
	append(&out, ..txt[12:])
	total := int(u16_at(query, 4)) + 2 * len(instances)
	out[4], out[5] = u8(total >> 8), u8(total)
	return out[:]
}

// A device's address for a person: its host, and its address when known ("nas.local, 192.168.1.10").
device_where :: proc(d: Network_Device, allocator := context.temp_allocator) -> string {
	if d.address == "" { return strings.clone(d.host, allocator) }
	return strings.concatenate({d.host, ", ", d.address}, allocator)
}
