package daemon

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
	"github.com/axiom-shell/axiom/backend/internal/windowrules/engine"
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
	// A built-in switch as a rule, for the draft's own special workspace
	var bi struct {
		Rule struct {
			Icon   string `json:"icon"`
			Window struct {
				Special struct {
					ID string `json:"id"`
				} `json:"special"`
			} `json:"window"`
		} `json:"rule"`
	}
	sw := map[string]any{"key": "gamesSpecial", "section": map[string]any{"switches": map[string]any{"gamesSpecial": map[string]any{"special": map[string]any{"id": "play"}}}}}
	if err := c.Call(context.Background(), "windowRules.builtin", sw, &bi); err != nil || bi.Rule.Window.Special.ID != "play" || bi.Rule.Icon == "" {
		t.Errorf("builtin %+v, %v", bi, err)
	}
	var aw struct {
		Rule struct {
			Shell struct {
				KeepAwake struct {
					Enabled bool   `json:"enabled"`
					When    string `json:"when"`
				} `json:"keepAwake"`
			} `json:"shell"`
		} `json:"rule"`
	}
	if err := c.Call(context.Background(), "windowRules.builtin", map[string]any{"key": "fullscreenAwake", "section": map[string]any{}}, &aw); err != nil || !aw.Rule.Shell.KeepAwake.Enabled || aw.Rule.Shell.KeepAwake.When != "fullscreen" {
		t.Errorf("builtin fullscreenAwake %+v, %v", aw, err)
	}
	if err := c.Call(context.Background(), "windowRules.builtin", map[string]any{"key": "x", "section": map[string]any{}}, nil); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("builtin x: %v", err)
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

// Only the shell overrides (a test daemon can't hand out the shell's connection:
// the engine's Override has its own test for bad effects)
func TestWindowRulesOverrideIsTheShells(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	cli, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := cli.Call(context.Background(), "windowRules.override", map[string]any{"effect": "dnd"}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("from a cli: %v", err)
	}
}

func TestRuleEffects(t *testing.T) {
	t.Parallel()
	rules := []engine.RuleWindows{{Rule: "a", Name: "Games"}, {Rule: "b", Name: "b"}}
	held := func(h windowrules.Holds, o windowrules.Overrides) engine.State {
		return engine.State{Rules: rules, Holds: h, Overrides: o}
	}
	for _, c := range []struct {
		name    string
		st      engine.State
		awake   []string
		profile string
		reason  string
	}{
		{"no holds", held(windowrules.Hold(nil), windowrules.Overrides{}), []string{}, "", ""},
		{"keep awake, two rules", held(windowrules.Holds{KeepAwake: []string{"a", "b"}}, windowrules.Overrides{}), []string{"Games", "b"}, "", ""},
		{"a power profile", held(windowrules.Holds{PowerProfile: windowrules.ProfileHold{Profile: "powerSaver", Rule: "a"}}, windowrules.Overrides{}), []string{}, "power-saver", "Games"},
		{"overridden", held(windowrules.Holds{PowerProfile: windowrules.ProfileHold{Profile: "performance", Rule: "a"}}, windowrules.Overrides{PowerProfile: true}), []string{}, "", ""},
	} {
		awake, profile, reason := ruleEffects(c.st)
		if !reflect.DeepEqual(awake, c.awake) || profile != c.profile || reason != c.reason {
			t.Errorf("%s: %v %q %q", c.name, awake, profile, reason)
		}
	}
}
