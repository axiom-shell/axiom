package greeter

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

func pipeline(t *testing.T) config.Pipeline {
	t.Helper()
	data, err := assets.Read("config/json/config.schema.json")
	if err != nil {
		t.Skip("no built schema:", err)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return config.Pipeline{S: schema.New(parsed)}
}

func write(t *testing.T, dir, name, text string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadFallsThrough(t *testing.T) {
	t.Parallel()
	p := pipeline(t)
	dir := t.TempDir()
	broken := write(t, dir, "broken.json", "{")
	invalid := write(t, dir, "invalid.json", `{"format": 2, "version": 76, "Greeter": {"enabled": "yes"}}`)
	good := write(t, dir, "good.json", `{"format": 2, "version": 76, "General": {"displayName": "Ada"}}`)
	r := Load(p, []Candidate{
		{"missing", filepath.Join(dir, "none.json")},
		{"broken", broken},
		{"invalid", invalid},
		{"good", good},
	})
	if r.Source != "good" {
		t.Fatalf("source %q, want good (problems %v)", r.Source, r.Problems)
	}
	if got := r.Config.Value("General").(*jsonx.Object).Value("displayName"); got != "Ada" {
		t.Fatalf("displayName %v, want Ada", got)
	}
	want := map[string]string{"missing": "missing", "broken": "not JSON", "invalid": "Greeter.enabled"}
	if len(r.Problems) != len(want) {
		t.Fatalf("problems %v, want one each for %v", r.Problems, want)
	}
	for _, problem := range r.Problems {
		if !strings.Contains(problem.Error, want[problem.Source]) {
			t.Errorf("%s: %q, want it to say %q", problem.Source, problem.Error, want[problem.Source])
		}
	}
}

func TestLoadDefaultsWhenNoneLoads(t *testing.T) {
	t.Parallel()
	r := Load(pipeline(t), []Candidate{{"bundle", filepath.Join(t.TempDir(), "none.json")}})
	if r.Source != "defaults" || r.Config == nil || len(r.Problems) != 1 {
		t.Fatalf("got %q, %v; want the defaults and one problem", r.Source, r.Problems)
	}
}

func TestLoadTriesANewerBundle(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	newer := write(t, dir, "newer.json", `{"format": 2, "version": 9999, "General": {"displayName": "Ada"}, "FutureSection": {}}`)
	r := Load(pipeline(t), []Candidate{{"bundle", newer}})
	if r.Source != "bundle" {
		t.Fatalf("source %q, want bundle (problems %v)", r.Source, r.Problems)
	}
}

func TestLoadConvertsFormat1(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	old := write(t, dir, "old.json", `{"version": 75, "General": {"displayName": "Ada"}}`)
	r := Load(pipeline(t), []Candidate{{"bundle", old}})
	if r.Source != "bundle" || r.Config.Value("format") != float64(2) {
		t.Fatalf("source %q, format %v; want the bundle as format 2 (problems %v)", r.Source, r.Config.Value("format"), r.Problems)
	}
}
