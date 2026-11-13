package daemon

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// The engine's reads: no compositor in the test daemon, so it isn't running.
// (A malformed draft can't be sent through Call; fillWindowRules' own test
// checks it is a bad request.)
func TestWindowRulesMethods(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	c, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	var st struct {
		Running bool              `json:"running"`
		Rules   []json.RawMessage `json:"rules"`
	}
	if err := c.Call(context.Background(), "windowRules.get", struct{}{}, &st); err != nil {
		t.Fatal(err)
	}
	if st.Running || st.Rules == nil {
		t.Errorf("state %+v", st)
	}
	var ws struct {
		Windows []json.RawMessage `json:"windows"`
	}
	if err := c.Call(context.Background(), "windowRules.windows", struct{}{}, &ws); err != nil || ws.Windows == nil {
		t.Errorf("windows %+v, %v", ws, err)
	}
	var m struct {
		Rules []json.RawMessage `json:"rules"`
	}
	draft := map[string]any{"section": map[string]any{"rules": []any{map[string]any{"id": "a"}}}}
	if err := c.Call(context.Background(), "windowRules.match", draft, &m); err != nil || len(m.Rules) != 1 {
		t.Errorf("match %+v, %v", m, err)
	}
	// A rule from a window: no compositor, no window
	for _, id := range []string{"", "7"} {
		if err := c.Call(context.Background(), "windowRules.fromWindow", map[string]any{"id": id}, nil); axerr.KindOf(err) != axerr.NotFound {
			t.Errorf("fromWindow %q: %v", id, err)
		}
	}
	// Apply to open windows without a compositor places nothing
	var ap struct {
		Windows *int `json:"windows"`
	}
	if err := c.Call(context.Background(), "windowRules.applyNow", struct{}{}, &ap); err != nil || ap.Windows == nil || *ap.Windows != 0 {
		t.Errorf("applyNow %+v, %v", ap, err)
	}
}
