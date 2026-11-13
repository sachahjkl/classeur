package classeurtool

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import toolbox "gt:toolbox"

// Windows: the release build carries its icon (res/classeur.rc's group 1, what Explorer and the window show).
check_exe_icon :: proc() -> bool {
	// (a full path with backslashes, as LoadLibraryEx asks)
	full, _ := filepath.abs(PROGRAM, context.temp_allocator)
	full, _ = strings.replace_all(full, "/", "\\", context.temp_allocator)
	if !toolbox.exe_has_icon(full) {
		fmt.eprintfln("classeurtool: %s has no icon (resource 1 of %s)", PROGRAM, RESOURCE)
		return false
	}
	fmt.printfln("%s: its icon", PROGRAM)
	return true
}
