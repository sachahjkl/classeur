#+build !windows
package classeur

// (Linux: `classeur install` integrates the copy where it is, and Nix installs it: no Setup at the start)
SETUP_AT_START :: false

// What the inspector calls the file's mode.
PERMISSIONS_WORD :: "Permissions"

// (no console launcher: a terminal waits for a program and has its output as it is)
CONSOLE_LAUNCHER: []u8
