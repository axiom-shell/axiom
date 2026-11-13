package specialid

import (
	"strings"
	"testing"
)

// The same rows as tests/tst_SpecialWorkspaces.qml's validId.
func TestValid(t *testing.T) {
	t.Parallel()
	for id, want := range map[string]bool{
		"magic":                 true,
		"my-pad_2":              true,
		"a.b":                   true,
		strings.Repeat("a", 32): true,
		"":                      false,
		"special":               false,
		"-x":                    false,
		"my pad":                false,
		"a;b":                   false,
		"a,b":                   false,
		strings.Repeat("a", 33): false,
		"Ä":                     false,
	} {
		if got := Valid(id); got != want {
			t.Errorf("Valid(%q) = %v, want %v", id, got, want)
		}
	}
}
