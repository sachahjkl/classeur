package classeur

// The devices of the network that share files (fs/network.odin), found on a worker: when the sidebar's Network section
// shows or opens, and by the command Find network devices. The sidebar keeps the list it has until the new one comes;
// an answer older than the last search asked is dropped.

import "gt:ui"
import "fs"

@(private = "file")
Devices_Found :: struct {
	app:     ^App,
	serial:  u64,
	offline: bool,   // the tests: the network is not asked
	devices: []fs.Network_Device,
}

// Asks a worker to search the network again.
network_find :: proc(app: ^App) {
	app.devices_asked += 1
	app.devices_searching = true
	app.answers_due += 1
	r := new(Devices_Found)
	r^ = {app = app, serial = app.devices_asked, offline = app.headless}
	pool_submit(&app.pool, proc(data: rawptr) {
		r := (^Devices_Found)(data)
		if !r.offline { r.devices = fs.network_devices() }
		if !ui.post(&r.app.main.state, devices_found, r) { devices_found_free(r) }
	}, r)
	app_frames(app)
}

@(private = "file")
devices_found :: proc(data: rawptr, word: u64) {
	r := (^Devices_Found)(data)
	app := r.app
	defer devices_found_free(r)
	app.answers_due -= 1
	if r.serial != app.devices_asked { return }
	app.devices_searching = false
	app.devices, r.devices = r.devices, app.devices
	app_frames(app)
}

@(private = "file")
devices_found_free :: proc(r: ^Devices_Found) {
	if r.devices != nil { fs.devices_destroy(r.devices) }
	free(r)
}

devices_free :: proc(app: ^App) {
	if app.devices != nil { fs.devices_destroy(app.devices) }
	app.devices = nil
	for u in app.side_device_uris { delete(u) }
	delete(app.side_device_uris)
}
