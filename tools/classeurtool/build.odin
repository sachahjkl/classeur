package classeurtool

// build, test, check: the program and its tests, the same steps on a laptop and in the CI.

import "core:fmt"
import "core:os"
import "core:strings"
import changelog "gt:changelog"
import toolbox "gt:toolbox"

// The packages that have tests, and this tool.
TEST_PACKAGES :: [?]string{"src", "src/fs", "tools/classeurtool"}

// The icon of classeur.exe (resource 1: Explorer's, and the window's: platform.open_window loads it); `logo` writes
// the .ico it names.
RESOURCE :: "res/classeur.rc"

run_build :: proc(args: []string) -> int {
	p := project()
	release := len(args) > 0 && args[0] == "release"
	if !toolbox.build_native(p) || !toolbox.build_launcher(p) { return 1 }
	_ = os.make_directory("build")
	mode := release ? []string{"-o:speed"} : []string{"-debug"}
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("-out:%s", PROGRAM))
	append(&extra, ..mode)
	when ODIN_OS == .Windows {
		if release { append(&extra, "-subsystem:windows") }
		append(&extra, fmt.tprintf("-resource:%s", RESOURCE))
	}
	if !toolbox.run(toolbox.odin_command(p, "build", "", extra[:]), {echo = true}) { return 1 }
	fmt.printfln("built %s", PROGRAM)
	return 0
}

run_test :: proc(args: []string) -> int {
	p := project()
	if !toolbox.build_native(p) || !toolbox.build_launcher(p) { return 1 }
	_ = os.make_directory("build")
	// (names given, `classeur.test_watch,classeur.test_zoom_icons_stay`: those tests of the program alone, in that order)
	if len(args) > 0 {
		out := fmt.tprintf("-out:build/test_some%s", ODIN_OS == .Windows ? ".exe" : "")
		names := fmt.tprintf("-define:ODIN_TEST_NAMES=%s", args[0])
		return toolbox.run(toolbox.odin_command(p, "test", "src", {out, names, "-define:ODIN_TEST_THREADS=1", "-define:ODIN_TEST_LOG_STATE_CHANGES=true"}), {echo = true}) ? 0 : 1
	}
	for pkg in TEST_PACKAGES {
		name, _ := strings.replace_all(pkg, "/", "_", context.temp_allocator)
		out := fmt.tprintf("-out:build/test_%s%s", name, ODIN_OS == .Windows ? ".exe" : "")
		// (each test said as it starts: a test that hangs is the last one said; the CI's log shows it)
		extra := pkg == "src" ? []string{out, "-define:ODIN_TEST_THREADS=1", "-define:ODIN_TEST_LOG_STATE_CHANGES=true"} : []string{out}
		// (the tool links no native library: no Linux link flag)
		cmd := pkg == "tools/classeurtool" ? []string{"odin", "test", pkg, fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet", out} : toolbox.odin_command(p, "test", pkg, extra)
		if !toolbox.run(cmd, {echo = true}) { return 1 }
	}
	return 0
}

run_check :: proc(args: []string) -> int {
	p := project()
	if !changelog_check(p) { return 1 }
	if !toolbox.check_scopes("src") { return 1 }
	if !check_systems() { return 1 }
	if !toolbox.build_launcher(p) { return 1 }   // (classeur embeds it: odin check reads it)
	if !toolbox.run(toolbox.odin_command(p, "check"), {echo = true}) { return 1 }
	// (the whole program for Windows too, from any system: Windows code that does not compile fails the Linux job)
	when ODIN_OS != .Windows {
		// (classeur embeds its console launcher, which only a Windows build makes: an empty one stands for it in a check,
		// which links nothing)
		if !os.exists(p.launcher.out) {
			_ = os.make_directory_all("build")
			if os.write_entire_file(p.launcher.out, []u8{}) != nil { fmt.eprintfln("classeurtool: %s cannot be written", p.launcher.out); return 1 }
		}
		if !toolbox.check_windows(p) { return 1 }
	} else {
		// (the file system's code of the other system: the program is written for both)
		if !toolbox.run({"odin", "check", "src/fs", fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet", "-no-entry-point", "-target:linux_amd64"}, {echo = true}) { return 1 }
	}
	if !toolbox.run({"odin", "check", "tools/classeurtool", fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet"}, {echo = true}) { return 1 }
	if run_test(nil) != 0 { return 1 }
	if run_build({"release"}) != 0 { return 1 }
	return toolbox.check_launcher(p) && check_exe_icon() ? 0 : 1
}

// The fragments of changelog.d/, as `changelog check` says them.
@(private = "file")
changelog_check :: proc(p: toolbox.Project) -> bool {
	q := p
	errors, n := changelog.check(changelog.project_options(&q))
	for e in errors { fmt.eprintln("changelog:", e) }
	if len(errors) == 0 { fmt.printfln("changelog: %d fragments, all well formed", n) }
	return len(errors) == 0
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
