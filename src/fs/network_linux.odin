#+build linux
package fs

// Linux: multicast DNS finds the devices by itself (gvfs's network:/// browses through Avahi, often not running).
system_devices_add :: proc(list: ^[dynamic]Network_Device, allocator := context.allocator) {}
