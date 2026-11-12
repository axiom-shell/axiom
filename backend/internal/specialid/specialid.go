// Package specialid is the rule for a special workspace's id, shared by the
// bind merge and the config migrations (SpecialWorkspaces.validId in QML
// holds the same rule). Pure: no I/O.
package specialid

import "regexp"

// MaxLen is the longest id.
const MaxLen = 32

var pattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

// Valid reports whether id is a special workspace id: ItemId's pattern, at
// most MaxLen chars, and not the reserved "special" (Hyprland's bare
// special workspace).
func Valid(id string) bool {
	return len(id) <= MaxLen && id != "special" && pattern.MatchString(id)
}
