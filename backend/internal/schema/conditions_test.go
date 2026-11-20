package schema

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// NamesKey reads a condition as Holds does: operator keys are not setting
// keys, an anyOf's items are conditions.
func TestNamesKey(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		condition string
		want      bool
	}{
		{`{"a": 1}`, false},
		{`{"b": 1}`, true},
		{`{"a": {"not": "b"}}`, false},
		{`{"a": {"includes": "b"}}`, false},
		{`{"anyOf": [{"b": 1}]}`, true},
		{`{"anyOf": [{"a": 1}]}`, false},
	} {
		v, err := jsonx.Unmarshal([]byte(c.condition))
		if err != nil {
			t.Fatal(err)
		}
		if got := NamesKey(v, "b"); got != c.want {
			t.Errorf("NamesKey(%s, b) = %v, want %v", c.condition, got, c.want)
		}
	}
}
