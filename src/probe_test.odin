package classeur

// A probe for the CI (CLASSEUR_PROBE=1): the program opened and closed a hundred times, a few frames each, the
// process's handles said every ten (Windows): a resource that leaks at each opening shows, and where a run of the
// tests would fail.

import "base:runtime"
@(require) import "core:debug/trace"
@(require) import "core:fmt"
import "core:log"
import "core:os"
import "core:testing"
import "gt:testkit"
@(require) import win "core:sys/windows"

when ODIN_OS == .Windows {
	// (a fault's stack, written before the test runner's handler stops the run: where the opening that fails breaks)
	@(private = "file")
	fault_handler :: proc "system" (info: ^win.EXCEPTION_POINTERS) -> win.LONG {
		code := info.ExceptionRecord.ExceptionCode
		if code < 0x8000_0000 { return 0 }   // (what the test runner takes as a fault: a C++ exception too)
		context = runtime.default_context()
		fmt.eprintfln("probe: fault %x at %p, thread %d", code, info.ExceptionRecord.ExceptionAddress, win.GetCurrentThreadId())
		bt := trace.capture()
		locations, _ := trace.resolve(bt)
		for l in locations { fmt.eprintfln("probe:   %s %s:%d", l.procedure, l.file_path, l.line) }
		return 0
	}
	@(private = "file")
	fault_trace :: proc() { win.AddVectoredExceptionHandler(1, fault_handler) }
	// (said once: a C++ exception may be thrown and caught many times)
	foreign import kernel32 "system:Kernel32.lib"
	foreign import user32 "system:User32.lib"
	@(default_calling_convention = "system")
	foreign kernel32 {
		GetCurrentProcess :: proc() -> rawptr ---
		GetProcessHandleCount :: proc(process: rawptr, count: ^u32) -> i32 ---
	}
	@(default_calling_convention = "system")
	foreign user32 {
		GetGuiResources :: proc(process: rawptr, flags: u32) -> u32 ---
	}
	@(private = "file")
	handles :: proc() -> (kernel, gdi, user: u32) {
		p := GetCurrentProcess()
		_ = GetProcessHandleCount(p, &kernel)
		return kernel, GetGuiResources(p, 0), GetGuiResources(p, 1)
	}
} else {
	@(private = "file")
	handles :: proc() -> (kernel, gdi, user: u32) { return }
	@(private = "file")
	fault_trace :: proc() {}
}

@(test)
test_probe_open_close :: proc(t: ^testing.T) {
	if os.get_env("CLASSEUR_PROBE", context.temp_allocator) == "" { return }
	context.allocator = runtime.heap_allocator()
	fault_trace()
	dir := testkit.temp_folder(t, "classeur_probe")
	for i in 0 ..< 100 {
		app := app_open({folders = {dir}, headless = true, size = {1100, 700}})
		if app == nil {
			log.errorf("probe: opening %d failed", i)
			return
		}
		for _ in 0 ..< 6 { app_frame(app) }
		app_close(app)
		if i % 10 == 0 {
			k, g, u := handles()
			log.infof("probe: %d openings, handles %d, GDI %d, USER %d", i + 1, k, g, u)
		}
	}
	log.info("probe: done")
}
