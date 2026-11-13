#+build !windows
package classeur

import "gt:i18n"

// (Linux: `classeur install` integrates the copy where it is, and Nix installs it: no Setup at the start)
SETUP_AT_START :: false

// What the inspector calls the file's mode (i18n.later: tr where it is shown).
PERMISSIONS_WORD := i18n.later("Permissions")

// (no console launcher: a terminal waits for a program and has its output as it is)
CONSOLE_LAUNCHER: []u8

// This system's words for the pieces of an install, in the Setup's "On this system" (i18n.later: tr where they are shown).
SETUP_MENU_WORDS   := i18n.later("applications menu")
SETUP_RECORD_WORDS := i18n.later("icons")
