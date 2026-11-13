package classeur

// What differs between the systems in the program itself (the file system's differences are src/fs's, the window's the
// toolkit's): a copy downloaded on Windows offers its Setup at its start.
import "gt:i18n"

SETUP_AT_START :: true

// What the inspector calls the file's attributes (i18n.later: tr where it is shown).
PERMISSIONS_WORD := i18n.later("Attributes")

// classeur.com, the console launcher (the toolkit's tools/console_launcher, built by `classeurtool build` before the
// program): `install` writes it beside classeur.exe with the PATH entry, so that `classeur` typed in cmd or PowerShell
// gives its output and exit code (a program with a window gives the prompt back at once and has no console).
CONSOLE_LAUNCHER := #load("../build/classeur.com")

// This system's words for the pieces of an install, in the Setup's "On this system" (i18n.later: tr where they are shown).
SETUP_MENU_WORDS   := i18n.later("Start menu")
SETUP_RECORD_WORDS := i18n.later("Settings > Apps")
