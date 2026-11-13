package classeur

// The caches of pictures: what is on screen is never let go, a thumbnail scrolled past is not decoded. (A pool whose
// threads are all held by a hung read starts another: gt:tasks' own test.)

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:testing"
import "gt:testkit/session"
import "gt:testkit/unwatched"
import "fs"

@(test)
test_tidy_keeps_shown :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		_, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		// more pictures used in this frame than are kept: none goes
		for _, &ic in app.icons_cache { ic.used = app.frame }
		for i in 0 ..< ICONS_KEPT + 20 {
			app.icons_cache[strings.clone(fmt.tprintf("test:%d@16", i))] = {state = .Failed, used = app.frame}
		}
		for i in 0 ..< THUMBS_KEPT + 20 {
			app.thumbs[strings.clone(fmt.tprintf("/test/%d|1|1", i))] = {state = .Failed, used = app.frame}
		}
		icons := len(app.icons_cache)
		thumbs := len(app.thumbs)
		icons_tidy(app)
		thumbs_tidy(app)
		testing.expect_value(t, len(app.icons_cache), icons)
		testing.expect_value(t, len(app.thumbs), thumbs)
		// one not used for long goes; those of this frame stay
		app.frame += 100
		for _, &ic in app.icons_cache { ic.used = app.frame }
		old := strings.clone("test:old@16")
		app.icons_cache[old] = {state = .Failed, used = app.frame - 100}
		icons_tidy(app)
		testing.expect(t, "test:old@16" not_in app.icons_cache, "the picture not used for long goes")
		testing.expect_value(t, len(app.icons_cache), icons)
	})
}

@(test)
test_thumb_stale :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		write_pictures(dir, {"a.png"})
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		path := fs.join(dir, "a.png", context.temp_allocator)
		testing.expect(t, thumb_key(path, 10, 1) != thumb_key(path, 11, 1), "a file changed has a new thumbnail")
		testing.expect(t, thumb_key(path, 10, 1) != thumb_key(path, 10, 2), "a file changed has a new thumbnail")
		session.frames(s, THUMB_STALE_FRAMES + 2)
		testing.expect(t, sync.atomic_load(&app.shown_frame) > THUMB_STALE_FRAMES, "frames built")

		// a card not built for a few frames: its picture is not read, and its entry goes (asked again when it comes back)
		key := thumb_key(path, 1, 1)
		stale := new(Thumb_Job)
		stale^ = {app = app, key = strings.clone(key), path = strings.clone(path), wanted = 0}
		app.thumbs[strings.clone(key)] = {state = .Asked, used = 0, job = stale}
		thumb_run(stale)
		testing.expect(t, stale.skipped, "the stale job is skipped")
		testing.expect(t, !stale.ok && stale.rgba == nil, "the stale job decoded nothing")
		session.frames(s, 1)
		testing.expect(t, key not_in app.thumbs, "the stale request is put back as not asked")

		// a card built in this frame: its picture is made
		key = thumb_key(path, 2, 2)
		fresh := new(Thumb_Job)
		fresh^ = {app = app, key = strings.clone(key), path = strings.clone(path), wanted = sync.atomic_load(&app.shown_frame)}
		app.thumbs[strings.clone(key)] = {state = .Asked, used = app.frame, job = fresh}
		thumb_run(fresh)
		testing.expect(t, fresh.ok, "the wanted job decodes")
		session.frames(s, 1)
		th, ok := app.thumbs[key]
		testing.expect(t, ok && th.state == .Ready && th.job == nil, "the wanted thumbnail is ready")
	})
}

// A file's icon key is asked on a worker (the toolkit's may read the system's type database): at first none, then the
// worker's answer, kept by the name.
@(test)
test_icon_key_on_a_worker :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		s, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		name := "a never seen name.qzx"
		ic, ready, failed := sys_icon(app, fs.join(dir, name, context.temp_allocator), false, 16)
		testing.expect(t, ic == nil && !ready && !failed, "no picture while its key is asked")
		testing.expect(t, name in app.icon_keys && app.icon_keys[name] == "", "asked")
		session.wait_until(s, proc(s: ^session.Session) -> bool {
			k, ok := (^App)(s.user).icon_keys["a never seen name.qzx"]
			return ok && k != ""
		}, "the worker's key")
	})
}
