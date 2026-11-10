package classeurtool

import "core:fmt"
import win "core:sys/windows"

// Windows: the release build carries its icon (res/classeur.rc's group 1, what Explorer and the window show): the
// executable is opened as data and the group looked for.
check_exe_icon :: proc() -> bool {
	module := win.LoadLibraryExW(win.utf8_to_wstring(PROGRAM), nil, {.LOAD_LIBRARY_AS_DATAFILE, .LOAD_LIBRARY_AS_IMAGE_RESOURCE})
	if module == nil {
		fmt.eprintfln("classeurtool: %s cannot be opened to read its resources", PROGRAM)
		return false
	}
	defer win.FreeLibrary(module)
	if win.FindResourceW(module, transmute(win.LPCWSTR)uintptr(1), transmute(win.LPCWSTR)win.RT_GROUP_ICON) == nil {
		fmt.eprintfln("classeurtool: %s has no icon (resource 1 of %s)", PROGRAM, RESOURCE)
		return false
	}
	fmt.printfln("%s: its icon", PROGRAM)
	return true
}
