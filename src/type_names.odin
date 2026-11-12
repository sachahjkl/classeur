package classeur

// The names the system gives the files' types ("Plain text document", "PNG image"), kept by extension: the rows ask
// for them each frame (type_text). The toolkit's desktop.type_name reads the system's files the first time a type is
// asked, so a name not kept yet is asked of a worker; the extension's own name stands in until it comes.

import "core:strings"
import "gt:desktop"
import "gt:ui"

TYPE_NAMES_KEPT :: 4000

Type_Name :: struct {
	name:  string,   // owned; "": the system has none
	known: bool,     // false: asked of a worker, not come yet
}

@(private = "file")
Type_Name_Job :: struct {
	app:  ^App,
	ext:  string,   // owned: the cache's key
	name: string,   // owned: the system's answer
}

// The system's name of the type of the extension `ext` (without its dot); "" while it is asked, or when the system has
// none.
type_name :: proc(app: ^App, ext: string) -> string {
	if t, ok := app.type_names[ext]; ok { return t.name }
	if len(app.type_names) > TYPE_NAMES_KEPT { type_names_free(app) }
	app.type_names[strings.clone(ext)] = {}
	job := new(Type_Name_Job)
	job^ = {app = app, ext = strings.clone(ext)}
	pool_submit(&app.thumb_pool, type_name_run, job, urgent = true)   // (a tiny read: not after the pictures' decodes)
	return ""
}

@(private = "file")
type_name_run :: proc(data: rawptr) {
	job := (^Type_Name_Job)(data)
	job.name = desktop.type_name(strings.concatenate({"a.", job.ext}, context.temp_allocator))
	if !ui.post(&job.app.main.state, type_name_done, job) { type_name_job_free(job) }
}

@(private = "file")
type_name_job_free :: proc(job: ^Type_Name_Job) {
	delete(job.ext)
	delete(job.name)
	free(job)
}

@(private = "file")
type_name_done :: proc(data: rawptr, word: u64) {
	job := (^Type_Name_Job)(data)
	defer type_name_job_free(job)
	app := job.app
	t, ok := &app.type_names[job.ext]
	if !ok { return }   // (the names were let go meanwhile)
	delete(t.name)
	t^ = {name = job.name, known = true}
	job.name = ""
	app_frames(app)
}

type_names_free :: proc(app: ^App) {
	for k, t in app.type_names {
		delete(k)
		delete(t.name)
	}
	clear(&app.type_names)
}
