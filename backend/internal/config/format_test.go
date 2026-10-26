package config_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func v2(t *testing.T) config.V2Pipeline {
	t.Helper()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return config.V2Pipeline{S: schema.New(root)}
}

func load(t *testing.T, p config.V2Pipeline, text string) config.Loaded {
	t.Helper()
	parsed, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	l, err := p.Load(parsed)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

// A format it can't read says what it read, as JSON, and never claims to
// read the format it refuses.
func TestFormatsItCantReadSayWhy(t *testing.T) {
	t.Parallel()
	p := v2(t)
	for _, c := range []struct{ text, want, not string }{
		{`{"format": 1, "version": 70}`, `format 1 has no "format" key`, "reads 1"},
		{`{"format": null, "version": 76}`, "format: null isn't", "<nil>"},
		{`{"format": "2", "version": 76}`, `format: "2" isn't`, ""},
		{`{"format": 3, "version": 76}`, "format: 3 isn't", ""},
	} {
		l := load(t, p, c.text)
		if len(l.Errors) != 1 || !strings.Contains(l.Errors[0], c.want) || c.not != "" && strings.Contains(l.Errors[0], c.not) {
			t.Errorf("%s: %q", c.text, l.Errors)
		}
	}
}

// The keys a format-1 file loses to format 1's own pass are reported
// (and so logged) with format 2's.
func TestFormat1ReportsRemovedKeys(t *testing.T) {
	t.Parallel()
	l := load(t, v2(t), `{"version": 74, "NoSuchSection": {"a": 1}}`)
	if len(l.Errors) > 0 || !l.FromFormat1 {
		t.Fatalf("errors %q", l.Errors)
	}
	if !slices.ContainsFunc(l.Removed, func(k string) bool { return strings.Contains(k, "NoSuchSection") }) {
		t.Errorf("removed %q", l.Removed)
	}
}
