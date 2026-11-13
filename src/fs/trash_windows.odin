package fs

// The Recycle Bin of Windows as a folder of classeur (trash:///). Each drive keeps the person's items in
// <drive>\$Recycle.Bin\<their SID>: an item is a $R<id> file or folder, its $I<id> record says its original path, its
// size and when it was deleted (recycle.odin). These are read directly, as any folder is, on a worker: no COM, which a
// worker would have to start and which hides the files behind the shell's objects. Putting back renames the $R item
// to its original path and removes its record (untrash); emptying deletes both, as Explorer leaves the bin.

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import "gt:i18n"

foreign import kernel32 "system:Kernel32.lib"
foreign import advapi32 "system:Advapi32.lib"

@(default_calling_convention = "system", private = "file")
foreign kernel32 {
	GetLogicalDrives :: proc() -> win.DWORD ---
	GetDriveTypeW :: proc(root: win.LPCWSTR) -> win.UINT ---
}

@(default_calling_convention = "system", private = "file")
foreign advapi32 {
	ConvertSidToStringSidW :: proc(sid: rawptr, text: ^^u16) -> win.BOOL ---
}

@(private = "file") DRIVE_REMOVABLE :: 2
@(private = "file") DRIVE_FIXED :: 3

// The path a tab shows the Recycle Bin at: no folder of the disk (every write in it fails), the same on every drive.
RECYCLE_BIN :: `\\?\Recycle Bin`

// The folders read in place of each drive's $Recycle.Bin\<SID>: a test's own, never the person's. nil: the drives'.
recycle_bins_override: []string

// The Recycle Bin is no folder: its items are read from every drive.
list_trash :: proc(l: ^Listing, path: string) -> (e: Error, done: bool) {
	if path != RECYCLE_BIN { return .None, false }
	recycle_list(l)
	return .None, true
}

// What a tab of the Recycle Bin is called (its path says nothing to a person); "": not the Recycle Bin.
trash_title :: proc(path: string) -> string { return path == RECYCLE_BIN ? i18n.tr("Recycle Bin") : "" }

// Every item of the person's Recycle Bins, named by its original name, dated when it was deleted. A name is made
// unique as a folder's are ("a 2.txt" for a second "a.txt"): the rows, the selection and the cursor go by names.
@(private = "file")
recycle_list :: proc(l: ^Listing) {
	taken := make(map[string]bool, allocator = context.temp_allocator)
	for bin in recycle_bins() {
		items: Listing
		defer listing_destroy(&items)
		if list_native(&items, bin) != .None { continue }
		// (each $R item by its id: the listing already holds its kind, size and flags, no call per item)
		by_id := make(map[string]int, allocator = context.temp_allocator)
		for it, i in items.entries {
			if strings.has_prefix(it.name, "$R") { by_id[name_key(it.name[2:], context.temp_allocator)] = i }
		}
		for it in items.entries {
			if !strings.has_prefix(it.name, "$I") { continue }
			// (a record whose item is gone shows nothing: Explorer shows none either)
			i, found := by_id[name_key(it.name[2:], context.temp_allocator)]
			if !found { continue }
			data, err := os.read_entire_file(join(bin, it.name, context.temp_allocator), context.temp_allocator)
			if err != nil { continue }
			r, ok := recycle_record_parse(data)
			if !ok { continue }
			item := items.entries[i]
			name := base(r.from)
			for n := 2; (name_key(name, context.temp_allocator) in taken); n += 1 { name = numbered_name(base(r.from), n, context.temp_allocator) }
			taken[name_key(name, context.temp_allocator)] = true
			e := item
			e.name = keep_name(l, name)
			e.mtime = r.at
			append(&l.entries, e)
			append(&l.trashed, Trashed{item = keep_name(l, join(bin, item.name, context.temp_allocator)), from = keep_name(l, parent(r.from))})
		}
	}
}

// The person's folder of each drive's Recycle Bin (fixed and removable drives: the network's have none).
@(private = "file")
recycle_bins :: proc() -> []string {
	if recycle_bins_override != nil { return recycle_bins_override }
	out := make([dynamic]string, context.temp_allocator)
	sid := user_sid()
	if sid == "" { return out[:] }
	mask := GetLogicalDrives()
	for i in 0 ..< 26 {
		if mask & (1 << uint(i)) == 0 { continue }
		root := fmt.tprintf("%c:\\", 'A' + i)
		kind := GetDriveTypeW(win.utf8_to_wstring(root, context.temp_allocator))
		if kind != DRIVE_FIXED && kind != DRIVE_REMOVABLE { continue }
		append(&out, strings.concatenate({root, "$Recycle.Bin\\", sid}, context.temp_allocator))
	}
	return out[:]
}

// The person's SID as text ("S-1-5-21-..."): the name of their folder in each Recycle Bin. "": not known.
@(private = "file")
user_sid :: proc() -> string {
	token: win.HANDLE
	if !win.OpenProcessToken(win.GetCurrentProcess(), win.TOKEN_QUERY, &token) { return "" }
	defer win.CloseHandle(token)
	buf: [128]u64   // (a TOKEN_USER and its SID, aligned)
	n: win.DWORD
	if !win.GetTokenInformation(token, .TokenUser, &buf[0], win.DWORD(size_of(buf)), &n) { return "" }
	user := (^win.TOKEN_USER)(&buf[0])
	text: ^u16
	if !ConvertSidToStringSidW(user.User.Sid, &text) { return "" }
	defer win.LocalFree(text)
	s, _ := win.wstring_to_utf8(cstring16(text), -1, context.temp_allocator)
	return s
}
