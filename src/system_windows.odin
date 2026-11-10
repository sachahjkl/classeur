package classeur

// What differs between the systems in the program itself (the file system's differences are src/fs's, the window's the
// toolkit's): a copy downloaded on Windows offers its Setup at its start.
SETUP_AT_START :: true

// What the inspector calls the file's attributes.
PERMISSIONS_WORD :: "Attributes"

// classeur.com, the console launcher (the toolkit's tools/console_launcher, built by `classeurtool build` before the
// program): `install` writes it beside classeur.exe with the PATH entry, so that `classeur` typed in cmd or PowerShell
// gives its output and exit code (a program with a window gives the prompt back at once and has no console).
CONSOLE_LAUNCHER := #load("../build/classeur.com")
