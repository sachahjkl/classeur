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

run_build :: proc(args: []string) -> int {
	release := len(args) > 0 && args[0] == "release"
	if !build_text() { return 1 }
	_ = os.make_directory("build")
	mode := release ? []string{"-o:speed"} : []string{"-debug"}
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("-out:%s", PROGRAM))
	append(&extra, ..mode)
	when ODIN_OS == .Windows { if release { append(&extra, "-subsystem:windows") } }
	if !toolbox.run(odin_cmd("build", "src", extra[:]), {echo = true}) { return 1 }
	fmt.printfln("built %s", PROGRAM)
	return 0
}

run_test :: proc(args: []string) -> int {
	if !build_text() { return 1 }
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
	if !toolbox.run(odin_cmd("check", "src", nil), {echo = true}) { return 1 }
	// (the file system's code of the other system is checked too: the program is written for both; the whole program
	// cannot be, the renderer of the other system needs its libraries)
	other := ODIN_OS == .Windows ? "-target:linux_amd64" : "-target:windows_amd64"
	if !toolbox.run({"odin", "check", "src/fs", "-vet", "-no-entry-point", other}, {echo = true}) { return 1 }
	if !toolbox.run({"odin", "check", "tools/classeurtool", collection(), "-vet"}, {echo = true}) { return 1 }
	if run_test(nil) != 0 { return 1 }
	return run_build({"release"})
}

// The scopes of gui_toolkit (ui.row, ui.parent...) end with the statement they open: `if !ui.row(...) { return }` closes
// the row at once and its children go to the parent's parent. The compiler accepts it; this check does not.
SCOPES :: [?]string{"parent", "row", "column", "field_frame", "scroll_y", "style", "tags", "title_bar", "modal", "ctx_menu", "menu_submenu", "tooltip"}

check_scopes :: proc() -> bool {
	files, err := os.read_all_directory_by_path("src", context.temp_allocator)
	if err != nil { return false }
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
