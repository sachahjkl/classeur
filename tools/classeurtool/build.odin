package classeurtool

// build, test, check: the program and its tests, the same steps on a laptop and in the CI.

import "core:fmt"
import "core:os"
import "core:strings"
import toolbox "gt:toolbox"

// What a build on Linux needs: the toolkit's native text backend, and the Rust standard library that both it and
// wgpu-native carry linked once (the same code: the toolkit's own CI does the same).
LINUX_DEFINES :: "-define:FONT_BACKEND=native"
LINUX_LINK    :: "-extra-linker-flags:-Wl,--allow-multiple-definition"
// The packages that have tests, and this tool.
TEST_PACKAGES :: [?]string{"src", "src/fs", "tools/classeurtool"}
when ODIN_OS == .Windows {
	PROGRAM :: "build/classeur.exe"
} else {
	PROGRAM :: "build/classeur"
}

toolkit :: proc() -> string {
	if v := os.get_env("GT", context.temp_allocator); v != "" { return v }
	return "ext/gui_toolkit"
}

collection :: proc() -> string { return fmt.tprintf("-collection:gt=%s/src", toolkit()) }

// An odin command on a package of the program: the toolkit's collection, -vet, and on Linux the text backend.
odin_cmd :: proc(verb, pkg: string, extra: []string) -> []string {
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "odin", verb, pkg, collection(), "-vet")
	when ODIN_OS == .Linux {
		append(&cmd, LINUX_DEFINES)
		if verb != "check" { append(&cmd, LINUX_LINK) }   // (check links nothing)
	}
	append(&cmd, ..extra)
	return cmd[:]
}

// The toolkit's text library, built by its own tool (it skips what is up to date).
build_text :: proc() -> bool {
	when ODIN_OS == .Linux {
		_ = os.make_directory_all(fmt.tprintf("%s/build", toolkit()))   // (a fresh checkout has none: the linker writes tk there)
		return toolbox.run({"odin", "run", "tools/tk", "-out:build/tk", "--", "build_text"}, {dir = toolkit(), echo = true})
	} else {
		return true
	}
}

// classeur.com, the console launcher (the toolkit's tools/console_launcher) that classeur embeds (src/system_windows.odin):
// its mark, and its rules: a folder (or none) opens a window and gives the prompt back; a command waits and gives its
// output and exit code through.
LAUNCHER_OUT :: "build/classeur.com"
LAUNCHER_DEFINES :: [?]string{
	"-define:LAUNCHER_MARK=(classeur console launcher)",
	"-define:LAUNCHER_DEFAULT=detach",
	"-define:LAUNCHER_OTHERS=install,uninstall,status,version,--version,help,-h,--help",
}

build_launcher :: proc() -> bool {
	when ODIN_OS == .Windows {
		_ = os.make_directory_all("build")
		cmd := make([dynamic]string, context.temp_allocator)
		append(&cmd, "odin", "build", fmt.tprintf("%s/tools/console_launcher", toolkit()), "-vet", "-subsystem:console", "-o:size", fmt.tprintf("-out:%s", LAUNCHER_OUT))
		defines := LAUNCHER_DEFINES
		append(&cmd, ..defines[:])
		return toolbox.run(cmd[:], {echo = true})
	} else {
		return true
	}
}

// Windows: classeur.com, beside the release build, gives classeur's output and exit code through.
check_launcher :: proc() -> bool {
	when ODIN_OS == .Windows {
		out, code := toolbox.capture({LAUNCHER_OUT, "version"})
		want := fmt.tprintf("classeur %s", app_version())
		if code != 0 || strings.trim_space(out) != want {
			fmt.eprintfln("classeurtool: classeur.com version gave %q (exit code %d), not %q", strings.trim_space(out), code, want)
			return false
		}
		fmt.println("classeur.com: classeur's output and exit code")
	}
	return true
}

// The icon of classeur.exe (resource 1: Explorer's, and the window's: platform.open_window loads it); `logo` writes
// the .ico it names.
RESOURCE :: "res/classeur.rc"

run_build :: proc(args: []string) -> int {
	release := len(args) > 0 && args[0] == "release"
	if !build_text() || !build_launcher() { return 1 }
	_ = os.make_directory("build")
	mode := release ? []string{"-o:speed"} : []string{"-debug"}
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("-out:%s", PROGRAM))
	append(&extra, ..mode)
	when ODIN_OS == .Windows {
		if release { append(&extra, "-subsystem:windows") }
		append(&extra, fmt.tprintf("-resource:%s", RESOURCE))
	}
	if !toolbox.run(odin_cmd("build", "src", extra[:]), {echo = true}) { return 1 }
	fmt.printfln("built %s", PROGRAM)
	return 0
}

run_test :: proc(args: []string) -> int {
	if !build_text() || !build_launcher() { return 1 }
	_ = os.make_directory("build")
	for pkg in TEST_PACKAGES {
		name, _ := strings.replace_all(pkg, "/", "_", context.temp_allocator)
		out := fmt.tprintf("-out:build/test_%s%s", name, ODIN_OS == .Windows ? ".exe" : "")
		extra := pkg == "src" ? []string{out, "-define:ODIN_TEST_THREADS=1"} : []string{out}
		cmd := pkg == "tools/classeurtool" ? []string{"odin", "test", pkg, collection(), "-vet", out} : odin_cmd("test", pkg, extra)
		if !toolbox.run(cmd, {echo = true}) { return 1 }
	}
	return 0
}

run_check :: proc(args: []string) -> int {
	if !check_scopes() { return 1 }
	if !check_systems() { return 1 }
	if !build_launcher() { return 1 }   // (classeur embeds it: odin check reads it)
	if !toolbox.run(odin_cmd("check", "src", nil), {echo = true}) { return 1 }
	// (the file system's code of the other system is checked too: the program is written for both; the whole program
	// cannot be, the renderer of the other system needs its libraries)
	other := ODIN_OS == .Windows ? "-target:linux_amd64" : "-target:windows_amd64"
	if !toolbox.run({"odin", "check", "src/fs", collection(), "-vet", "-no-entry-point", other}, {echo = true}) { return 1 }
	if !toolbox.run({"odin", "check", "tools/classeurtool", collection(), "-vet"}, {echo = true}) { return 1 }
	if run_test(nil) != 0 { return 1 }
	if run_build({"release"}) != 0 { return 1 }
	return check_launcher() && check_exe_icon() ? 0 : 1
}

// The scopes of gui_toolkit (ui.row, ui.parent...) end with the statement they open: `if !ui.row(...) { return }` closes
// the row at once and its children go to the parent's parent. The compiler accepts it; this check does not.
SCOPES :: [?]string{"parent", "row", "column", "field_frame", "scroll_y", "style", "tags", "title_bar", "modal", "ctx_menu", "menu_submenu", "tooltip"}

check_scopes :: proc() -> bool {
	files, ok_files := source_files("src")
	if !ok_files { return false }
	ok := true
	scopes := SCOPES
	for f in files {
		if !strings.has_suffix(f.name, ".odin") { continue }
		data, rerr := os.read_entire_file(f.fullpath, context.temp_allocator)
		if rerr != nil { continue }
		text := string(data)
		n := 0
		for line in strings.split_lines_iterator(&text) {
			n += 1
			for sc in scopes {
				if strings.contains(line, fmt.tprintf("if !ui.%s(", sc)) {
					fmt.eprintfln("%s:%d: `if !ui.%s(...)` ends the scope at once: build inside `if ui.%s(...)` and its block", f.fullpath, n, sc, sc)
					ok = false
				}
			}
		}
	}
	return ok
}

// The system and the interface apart: the interface (src/*.odin) asks src/fs and the toolkit (platform, desktop) what
// differs between the systems, and says nothing of them itself. A difference of the program's own is a constant in a
// file of the system's name (system_windows.odin, system_other.odin), never a `when ODIN_OS` in the interface.
check_systems :: proc() -> bool {
	files, ok_files := source_files("src")
	if !ok_files { return false }
	ok := true
	for f in files {
		if !strings.has_suffix(f.name, ".odin") || strings.has_suffix(f.name, "_test.odin") || strings.has_prefix(f.name, "system_") { continue }
		data, rerr := os.read_entire_file(f.fullpath, context.temp_allocator)
		if rerr != nil { continue }
		text := string(data)
		n := 0
		for line in strings.split_lines_iterator(&text) {
			n += 1
			if strings.contains(line, "ODIN_OS") {
				fmt.eprintfln("%s:%d: the interface knows the system: ask src/fs or the toolkit, or put a constant in a system_<os>.odin", f.fullpath, n)
				ok = false
			}
		}
	}
	return ok
}

// The program's sources: src/*.odin and those of its packages below (src/update...), src/fs aside (the system's own,
// where ODIN_OS belongs; it builds no interface).
@(private = "file")
source_files :: proc(dir: string) -> (files: [dynamic]os.File_Info, ok: bool) {
	files.allocator = context.temp_allocator
	list, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil { return files, false }
	for f in list {
		if f.type == .Directory {
			if f.name == "fs" { continue }
			sub, sub_ok := source_files(f.fullpath)
			if !sub_ok { return files, false }
			append(&files, ..sub[:])
			continue
		}
		append(&files, f)
	}
	return files, true
}
