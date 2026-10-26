package steps

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
)

func TestStepsCountOnFromTheConversion(t *testing.T) {
	t.Parallel()
	want := convert.Version + 1
	for _, step := range all {
		if step.Version != want {
			t.Fatalf("step at version %d, want %d: steps count on by one from %d", step.Version, want, convert.Version)
		}
		if step.Run == nil {
			t.Fatalf("step %d has no Run", step.Version)
		}
		want++
	}
}

func TestSchemaVersionIsCurrent(t *testing.T) {
	t.Parallel()
	data, err := assets.Read("config/json/config.schema.json")
	if err != nil {
		t.Skip("no built schema:", err)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	root := parsed.(*jsonx.Object)
	version := root.Value("properties").(*jsonx.Object).Value("version").(*jsonx.Object).Value("default")
	if version != float64(Current()) {
		t.Fatalf("the schema's version default is %v, the steps' %d: set config/schema/index.yaml's to the last step's", version, Current())
	}
}

func TestMigrateRunsNewerStepsOnce(t *testing.T) {
	t.Parallel()
	list := []Step{
		{Version: 77, Run: func(cfg *jsonx.Object) []string { cfg.Set("a", true); return []string{"a"} }},
		{Version: 78, Run: func(cfg *jsonx.Object) []string { cfg.Set("b", true); return []string{"b"} }},
	}
	cfg := jsonx.Obj("format", float64(2), "version", float64(77))
	changes, migrated := migrate(list, cfg)
	if !migrated || len(changes) != 1 || changes[0] != "b" {
		t.Fatalf("changes %v, migrated %v; want [b], true", changes, migrated)
	}
	if _, ran := cfg.Get("a"); ran {
		t.Fatal("ran a step the file was already past")
	}
	if cfg.Value("version") != float64(78) {
		t.Fatalf("version %v, want 78", cfg.Value("version"))
	}
	if changes, migrated := migrate(list, cfg); migrated || len(changes) != 0 {
		t.Fatalf("second run: %v, %v; want nothing", changes, migrated)
	}
}

func TestV78DropsTheHypridleAutostart(t *testing.T) {
	t.Parallel()
	step := all[1]
	if step.Version != 78 {
		t.Fatalf("step %d", step.Version)
	}
	parse := func(s string) *jsonx.Object {
		v, err := jsonx.Unmarshal([]byte(s))
		if err != nil {
			t.Fatal(err)
		}
		return v.(*jsonx.Object)
	}
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"the default's", `{"Session":{"autostart":[{"id":"a","command":"a"},{"id":"hypridle","command":"hypridle","enabled":true}]}}`,
			`{"Session":{"autostart":[{"id":"a","command":"a"}]}}`, true},
		{"turned off", `{"Session":{"autostart":[{"id":"hypridle","command":"hypridle","enabled":false}]}}`,
			`{"Session":{"autostart":[]}}`, true},
		{"the user's own", `{"Session":{"autostart":[{"id":"idle","command":"hypridle"},{"id":"hypridle","command":"hypridle -c x"}]}}`,
			`{"Session":{"autostart":[{"id":"idle","command":"hypridle"},{"id":"hypridle","command":"hypridle -c x"}]}}`, false},
		{"no autostart", `{"Session":{}}`, `{"Session":{}}`, false},
		{"no session", `{"Bars":[]}`, `{"Bars":[]}`, false},
		{"another shape", `{"Session":{"autostart":["hypridle"]}}`, `{"Session":{"autostart":["hypridle"]}}`, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			cfg := parse(c.in)
			changes := step.Run(cfg)
			if got := string(jsonx.MarshalCompact(cfg)); got != c.out {
				t.Errorf("got %s, want %s", got, c.out)
			}
			if (len(changes) > 0) != c.changed {
				t.Errorf("changes %v", changes)
			}
			if again := step.Run(cfg); len(again) > 0 {
				t.Errorf("a second run: %v", again)
			}
		})
	}
}

func TestV77DropsTheClipboardSource(t *testing.T) {
	t.Parallel()
	step := all[0]
	if step.Version != 77 {
		t.Fatalf("step %d", step.Version)
	}
	parse := func(s string) *jsonx.Object {
		v, err := jsonx.Unmarshal([]byte(s))
		if err != nil {
			t.Fatal(err)
		}
		return v.(*jsonx.Object)
	}
	cases := []struct {
		name, in, out string
		changed       bool
	}{
		{"cliphist", `{"Launcher":{"providers":{"clipboard":{"enabled":true,"source":"cliphist","maxEntries":50}}}}`,
			`{"Launcher":{"providers":{"clipboard":{"enabled":true,"maxEntries":50}}}}`, true},
		{"axiom", `{"Launcher":{"providers":{"clipboard":{"source":"axiom"}}}}`,
			`{"Launcher":{"providers":{"clipboard":{}}}}`, true},
		{"already without it", `{"Launcher":{"providers":{"clipboard":{"enabled":false}}}}`,
			`{"Launcher":{"providers":{"clipboard":{"enabled":false}}}}`, false},
		{"no launcher", `{"Bars":[]}`, `{"Bars":[]}`, false},
		{"another shape", `{"Launcher":{"providers":{"clipboard":true}}}`, `{"Launcher":{"providers":{"clipboard":true}}}`, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			cfg := parse(c.in)
			changes := step.Run(cfg)
			if got := string(jsonx.MarshalCompact(cfg)); got != c.out {
				t.Errorf("got %s, want %s", got, c.out)
			}
			if (len(changes) > 0) != c.changed {
				t.Errorf("changes %v", changes)
			}
			// Twice changes nothing more
			if again := step.Run(cfg); len(again) > 0 {
				t.Errorf("a second run: %v", again)
			}
		})
	}
}
