package classeur

// The person's own keys (File Pilot's): any command bound to a key or to a sequence of two (Ctrl+M, then T), in place of
// its own keys; aliases, short names typed in the palette that find a command. Both are preferences (keys.custom,
// keys.aliases), set from the palette: Ctrl+Enter (or a row's +) records the keys of the chosen command, Alt+Enter makes
// the letters typed an alias of it.
//
//   keys.custom   "tab_new=Ctrl+M,T;terminal=F7"   a command's id, its chords (a comma between two of a sequence)
//   keys.aliases  "nf=new_folder;go=goto_popup"

import "core:fmt"
import "core:strings"
import config "gt:config"
import "gt:platform"
import "gt:ui"

// A command's keys: one chord, or two in a row (the second within SEQUENCE_MS of the first).
Binding :: struct {
	chords: [2]Shortcut,
}

SEQUENCE_MS :: 1500

Keymap :: struct {
	custom:  map[string]Binding,   // keys owned: by command id
	aliases: map[string]string,    // alias -> command id, both owned
	pending: Shortcut,             // the first chord of a sequence, pressed (.None: none)
	pending_until: f64,
	version: u64,                  // counts the changes of custom and aliases (the palette and the sheet list again)
}

keymap_free :: proc(k: ^Keymap) {
	for id in k.custom { delete(id) }
	delete(k.custom)
	for a, id in k.aliases { delete(a); delete(id) }
	delete(k.aliases)
	k^ = {}
}

// A command's bindings: the person's, else its own.
command_bindings :: proc(app: ^App, c: ^Command, allocator := context.temp_allocator) -> []Binding {
	if b, ok := app.keymap.custom[c.id]; ok {
		out := make([]Binding, 1, allocator)
		out[0] = b
		return out
	}
	out := make([dynamic]Binding, allocator)
	for k in c.keys { if k.key != .None { append(&out, Binding{{k, {}}}) } }
	return out[:]
}

// "Ctrl+M, T".
binding_text :: proc(b: Binding, allocator := context.temp_allocator) -> string {
	if b.chords[1].key == .None { return ui.chord_text(b.chords[0], allocator) }
	return fmt.aprintf("%s, %s", ui.chord_text(b.chords[0], context.temp_allocator), ui.chord_text(b.chords[1], context.temp_allocator), allocator = allocator)
}

// "Ctrl+Shift+P" back to a chord (the toolkit's names, ui.key_name; the modifiers in any order); ok = false for a key it
// does not know.
shortcut_parse :: proc(text: string) -> (s: Shortcut, ok: bool) {
	t := strings.trim_space(text)
	// (the key's name at the end, the longest that fits: "Num +" holds a '+', as "Ctrl++" would)
	best := ""
	for k in platform.Key {
		name := ui.key_name(k)
		if name == "" || !strings.has_suffix(t, name) || len(name) <= len(best) { continue }
		rest := t[:len(t) - len(name)]
		if rest != "" && !strings.has_suffix(rest, "+") { continue }
		best, s.key = name, k
	}
	if s.key == .None { return {}, false }
	rest := strings.trim_suffix(t[:len(t) - len(best)], "+")
	if rest == "" { return s, true }
	for p in strings.split(rest, "+", context.temp_allocator) {
		switch p {
		case "Ctrl":  s.mods += {.Ctrl}
		case "Alt":   s.mods += {.Alt}
		case "Shift": s.mods += {.Shift}
		case:         return {}, false
		}
	}
	return s, true
}

binding_parse :: proc(text: string) -> (b: Binding, ok: bool) {
	// (the chords are joined by ", " as binding_text writes them: a lone ',' is the key, "Ctrl+,")
	chords := strings.split(strings.trim_space(text), ", ", context.temp_allocator)
	if len(chords) == 0 || len(chords) > 2 { return }
	for c, i in chords { b.chords[i] = shortcut_parse(c) or_return }
	return b, true
}

// The preferences' values read into the keymap (prefs.odin's settings_apply).
keymap_read :: proc(app: ^App, custom, aliases: string) {
	k := &app.keymap
	k.version += 1
	for id in k.custom { delete(id) }
	clear(&k.custom)
	for a, id in k.aliases { delete(a); delete(id) }
	clear(&k.aliases)
	for item in strings.split(custom, ";", context.temp_allocator) {
		id, _, keys := strings.partition(item, "=")
		if command_find(strings.trim_space(id)) == nil { continue }
		if b, ok := binding_parse(keys); ok { k.custom[strings.clone(strings.trim_space(id))] = b }
	}
	for item in strings.split(aliases, ";", context.temp_allocator) {
		alias, _, id := strings.partition(item, "=")
		alias, id = strings.trim_space(alias), strings.trim_space(id)
		if alias == "" || command_find(id) == nil { continue }
		k.aliases[strings.clone(alias)] = strings.clone(id)
	}
}

@(private = "file")
keymap_save :: proc(app: ^App) {
	b := strings.builder_make(context.temp_allocator)
	n := 0
	for id, bind in app.keymap.custom {
		if n > 0 { strings.write_byte(&b, ';') }
		fmt.sbprintf(&b, "%s=%s", id, strings.trim_space(binding_text(bind)))
		n += 1
	}
	config.set_string(&app.prefs, "keys.custom", strings.to_string(b))
	a := strings.builder_make(context.temp_allocator)
	n = 0
	for alias, id in app.keymap.aliases {
		if n > 0 { strings.write_byte(&a, ';') }
		fmt.sbprintf(&a, "%s=%s", alias, id)
		n += 1
	}
	config.set_string(&app.prefs, "keys.aliases", strings.to_string(a))
	app.keymap.version += 1
}

// The command `id` bound to `b` in place of its own keys (another command that had `b` loses it: one key, one command).
keymap_bind :: proc(app: ^App, id: string, b: Binding) {
	for other, ob in app.keymap.custom {
		if ob == b && other != id {
			key, _ := delete_key(&app.keymap.custom, other)
			delete(key)
			break
		}
	}
	if id not_in app.keymap.custom { app.keymap.custom[strings.clone(id)] = b } else { app.keymap.custom[id] = b }
	keymap_save(app)
}

// The command `id` back to its own keys.
keymap_unbind :: proc(app: ^App, id: string) {
	if id in app.keymap.custom {
		key, _ := delete_key(&app.keymap.custom, id)
		delete(key)
		keymap_save(app)
	}
}

keymap_alias :: proc(app: ^App, alias, id: string) {
	a := strings.trim_space(strings.to_lower(alias, context.temp_allocator))
	if a == "" { return }
	if old, ok := app.keymap.aliases[a]; ok {
		delete(old)
		app.keymap.aliases[a] = strings.clone(id)
	} else {
		app.keymap.aliases[strings.clone(a)] = strings.clone(id)
	}
	keymap_save(app)
}

// The command an alias names, nil: none.
alias_command :: proc(app: ^App, text: string) -> ^Command {
	if id, ok := app.keymap.aliases[strings.to_lower(strings.trim_space(text), context.temp_allocator)]; ok { return command_find(id) }
	return nil
}

// Whether a command's key was pressed: one chord, or a sequence's second after its first (kept between frames).
bindings_pressed :: proc(app: ^App, c: ^Command) -> bool {
	k := &app.keymap
	for b in command_bindings(app, c) {
		first, second := b.chords[0], b.chords[1]
		if second.key == .None {
			if k.pending.key == .None && ui.key_press(first.key, first.mods) { return true }
			continue
		}
		if k.pending == first && ui.key_press(second.key, second.mods) {
			k.pending = {}
			return true
		}
		if k.pending.key == .None && ui.key_press(first.key, first.mods) {
			k.pending, k.pending_until = first, ui.now_ms() + SEQUENCE_MS
			app_frames(app)
		}
	}
	return false
}
