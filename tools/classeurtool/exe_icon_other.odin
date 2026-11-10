#+build !windows
package classeurtool

// (an executable's icon is a Windows resource: elsewhere the desktop entry names the icon)
check_exe_icon :: proc() -> bool { return true }
