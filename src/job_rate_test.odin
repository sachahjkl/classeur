package classeur

// The jobs' speed and time left: the smoothing, the texts, and the footer's line of a job that runs.

import "base:runtime"
import "core:strings"
import "core:testing"
import "gt:testkit/unwatched"

@(private = "file")
MB :: 1024 * 1024

@(test)
test_rate_step :: proc(t: ^testing.T) {
	// the first step is what it measured; then it follows, slowly
	testing.expect_value(t, rate_step(0, 10 * MB, 1), f64(10 * MB))
	r := rate_step(10 * MB, 20 * MB, 1)
	testing.expect(t, r > 10 * MB && r < 20 * MB, "between the old speed and the new")
	// a step of no time changes nothing; nothing done slows it down
	testing.expect_value(t, rate_step(10 * MB, 5 * MB, 0), f64(10 * MB))
	testing.expect(t, rate_step(10 * MB, 0, 1) < 10 * MB, "nothing done: slower")
	// the same time in small steps or one big one: about the same speed
	a := f64(10 * MB)
	for _ in 0 ..< 4 { a = rate_step(a, 5 * MB, 0.5) }
	b := rate_step(10 * MB, 20 * MB, 2)
	testing.expect(t, abs(a - b) < 0.01 * MB, "the pace of the steps does not matter")
}

@(test)
test_rate_and_eta_text :: proc(t: ^testing.T) {
	testing.expect_value(t, rate_text(42 * MB), "42 MB/s")
	testing.expect_value(t, rate_text(512), "512 B/s")
	testing.expect_value(t, eta_text(12), "12 s left")
	testing.expect_value(t, eta_text(11.2), "12 s left")
	testing.expect_value(t, eta_text(120), "2 min left")
	testing.expect_value(t, eta_text(61), "2 min left")
	testing.expect_value(t, eta_text(3900), "1 h 5 min left")
	testing.expect_value(t, eta_text(7200), "2 h left")
	testing.expect_value(t, eta_text(-3), "0 s left")
}

// A job that runs: its line says the speed and the time left once a second has gone, not before, and no time left
// without a total.
@(test)
test_job_status_rate :: proc(t: ^testing.T) {
	unwatched.run(t, proc(t: ^testing.T) {
		files := FIXTURE
		dir := make_fixture(t, files[:])
		_, app := start(t, {dir})
		context.allocator = runtime.heap_allocator()
		job := new(Job)
		defer job_free(job)
		job.kind, job.state, job.current = .Copy, .Running, strings.clone("big.iso")
		job.files_total, job.files_done = 40, 2
		job.bytes_total, job.bytes_done = 100 * MB + 120 * 42 * MB, 100 * MB

		// sampled from the counters, as each frame does
		job_rate_update(app, job, 1000)
		testing.expect_value(t, job.rate, 0)
		job.bytes_done += 21 * MB
		job_rate_update(app, job, 1500)
		testing.expect_value(t, job.rate, f64(42 * MB))
		testing.expect_value(t, job_status_text(job, 1500), "Copying 3 of 40 · big.iso")   // (the first second)

		job.bytes_done = 100 * MB
		testing.expect_value(t, job_status_text(job, 2000), "Copying 3 of 40 · big.iso · 42 MB/s · 2 min left")
		job.bytes_total = 0
		testing.expect_value(t, job_status_text(job, 2000), "Copying 3 of 40 · big.iso · 42 MB/s")

		// waiting for an answer: the sampling stops, the time waited is not slowness
		job.state = .Asking
		job_rate_update(app, job, 2400)
		testing.expect_value(t, job.rate_ms, 0)
		testing.expect_value(t, job.rate, f64(42 * MB))
	})
}
