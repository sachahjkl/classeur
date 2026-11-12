package fs

// The records of the Recycle Bin of Windows. Beside each item ($R<id>) a $I<id> file says where it was, its size and
// when it went. The format is small and stable; it is read here on every system, so that its tests run everywhere.
//
//   0    u64   the version: 1 (up to Windows 8), 2 (since Windows 10)
//   8    i64   the item's size (a folder: all it holds)
//   16   u64   when it was deleted (a FILETIME: 100 ns since 1601-01-01 UTC)
//   24   version 1: the path in 260 UTF-16 units, ended by a zero
//        version 2: the path's length in units (u32, its zero counted), then the path

import "core:strings"
import "core:unicode/utf16"

Recycle_Record :: struct {
	from: string,   // the item's path before
	size: i64,
	at:   i64,      // when it was deleted, ns since 1970 UTC
}

@(private = "file")
FILETIME_1970 :: 116_444_736_000_000_000   // 1970-01-01 in 100 ns since 1601-01-01

// A $I record's content read; ok = false: not one (another version, cut short, no path).
recycle_record_parse :: proc(data: []u8, allocator := context.temp_allocator) -> (r: Recycle_Record, ok: bool) {
	if len(data) < 28 { return }
	r.size = i64(le(data, 8, 8))
	r.at = (i64(le(data, 16, 8)) - FILETIME_1970) * 100
	units: []u8
	switch le(data, 0, 8) {
	case 1:
		if len(data) < 24 + 520 { return }
		units = data[24:24 + 520]
	case 2:
		n := int(le(data, 24, 4))
		if n <= 0 || len(data) < 28 + n * 2 { return }
		units = data[28:28 + n * 2]
	case:
		return
	}
	b := strings.builder_make(allocator)
	for i := 0; i + 1 < len(units); i += 2 {
		c := rune(u16(units[i]) | u16(units[i + 1]) << 8)
		if c == 0 { break }
		if utf16.is_surrogate(c) && i + 3 < len(units) {
			c = utf16.decode_surrogate_pair(c, rune(u16(units[i + 2]) | u16(units[i + 3]) << 8))
			i += 2
		}
		strings.write_rune(&b, c)
	}
	r.from = strings.to_string(b)
	return r, r.from != ""
}

// A $I record (version 2) for an item that was at `from`: what the tests lay in a Recycle Bin of their own.
recycle_record_bytes :: proc(from: string, size, at: i64, allocator := context.temp_allocator) -> []u8 {
	// (a byte of UTF-8 is never less than a unit of UTF-16)
	w := make([]u16, len(from) + 1, context.temp_allocator)
	n := utf16.encode_string(w, from)
	units := n + 1
	out := make([]u8, 28 + units * 2, allocator)
	put_le(out, 0, 8, 2)
	put_le(out, 8, 8, u64(size))
	put_le(out, 16, 8, u64(at / 100 + FILETIME_1970))
	put_le(out, 24, 4, u64(units))
	for k in 0 ..< n {
		out[28 + 2 * k] = u8(w[k])
		out[29 + 2 * k] = u8(w[k] >> 8)
	}
	return out
}

// `n` bytes at `at`, little-endian.
@(private = "file")
le :: proc(b: []u8, at, n: int) -> u64 {
	v: u64
	for k in 0 ..< n { v |= u64(b[at + k]) << (8 * u32(k)) }
	return v
}

@(private = "file")
put_le :: proc(b: []u8, at, n: int, v: u64) {
	for k in 0 ..< n { b[at + k] = u8(v >> (8 * u32(k))) }
}
