package classeurtool

import "core:testing"

// Each command of the tool has a name of its own and says what it does.
@(test)
the_commands_have_names_of_their_own :: proc(t: ^testing.T) {
	seen := make(map[string]bool, context.temp_allocator)
	for c in commands() {
		testing.expectf(t, c.name not_in seen, "%s twice", c.name)
		testing.expectf(t, c.usage != "" && (c.run != nil || c.run_with != nil), "%s says what it does", c.name)
		seen[c.name] = true
	}
}
