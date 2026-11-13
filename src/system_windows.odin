package classeur

// What differs between the systems in the program itself (the file system's differences are src/fs's, the window's the
// toolkit's): a copy downloaded on Windows offers its Setup at its start.
import "gt:i18n"

SETUP_AT_START :: true

// What the inspector calls the file's attributes (i18n.later: tr where it is shown).
PERMISSIONS_WORD := i18n.later("Attributes")

// This system's words for the pieces of an install, in the Setup's "On this system" (i18n.later: tr where they are shown).
SETUP_MENU_WORDS   := i18n.later("Start menu")
SETUP_RECORD_WORDS := i18n.later("Settings > Apps")
