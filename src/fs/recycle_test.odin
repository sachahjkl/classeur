package fs

// The $I records of the Recycle Bin of Windows, read from bytes made here: on every system.

import "core:testing"

@(test)
test_recycle_record :: proc(t: ^testing.T) {
	// version 2, as recycle_record_bytes makes it: a path out of the Basic Multilingual Plane too
	at := i64(1_762_000_000) * 1_000_000_000
	data := recycle_record_bytes(`C:\Users\ann\Été 🎵.txt`, 1234, at)
	r, ok := recycle_record_parse(data)
	testing.expect(t, ok, "read")
	testing.expect_value(t, r.from, `C:\Users\ann\Été 🎵.txt`)
	testing.expect_value(t, r.size, 1234)
	testing.expect_value(t, r.at, at)

	// version 1: the path in 260 units, ended by a zero
	v1 := make([]u8, 24 + 520, context.temp_allocator)
	copy(v1, data[:24])
	v1[0] = 1
	path := "D:\\old.doc"
	for c, k in path { v1[24 + 2 * k] = u8(c) }
	r1, ok1 := recycle_record_parse(v1)
	testing.expect(t, ok1 && r1.from == path && r1.at == at && r1.size == 1234, "version 1")

	// what is not a record
	_, short := recycle_record_parse(data[:20])
	testing.expect(t, !short, "cut short")
	v3 := make([]u8, len(data), context.temp_allocator)
	copy(v3, data)
	v3[0] = 3
	_, other := recycle_record_parse(v3)
	testing.expect(t, !other, "another version")
	_, cut := recycle_record_parse(data[:len(data) - 4])
	testing.expect(t, !cut, "its path cut short")
}
