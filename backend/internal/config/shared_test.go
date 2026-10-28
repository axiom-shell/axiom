package config

import (
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/migrate/legacy"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The schema.* shared cases (recorded from SchemaValidation.qml, which the
// shell still fills defaults with, against the live schema and the tests'
// own) replayed through the Go pipeline: each output must be the JS bytes
// exactly. The greeter's exported bundle, filled (tst_GreeterBundle), must
// also be a valid config.
func TestSharedSchemaCases(t *testing.T) {
	t.Parallel()
	for _, c := range testkit.Cases(t, "schema.") {
		t.Run(c.Name, func(t *testing.T) {
			out := runSchemaOp(t, c)
			c.Compare(t, out)
			if strings.HasPrefix(c.Name, "schema/GreeterBundle/") {
				s := schema.New(c.Args[1])
				if errs := ValidationErrors(s, out, s.Root()); len(errs) > 0 {
					t.Errorf("the filled bundle isn't valid: %q", errs)
				}
			}
		})
	}
}

func runSchemaOp(t *testing.T, c testkit.Case) any {
	t.Helper()
	switch c.Op {
	case "schema.applyDefaults":
		root := c.Args[1]
		if len(c.Args) > 2 {
			root = c.Args[2]
		}
		out, ok := ApplyDefaults(schema.New(root), c.Args[0], true, c.Args[1])
		if !ok {
			return nil
		}
		return out
	case "schema.resolveRef":
		return schema.New(c.Args[1]).Resolve(c.Args[0])
	}
	t.Fatalf("unknown op %s", c.Op)
	return nil
}

// The corpus, frozen when the shell's migrations went: every past schema
// version's defaults and the old configs, loaded whole, must come out as
// the shell's ConfigManager made them.
func TestFrozenLoadCases(t *testing.T) {
	t.Parallel()
	s := schema.New(legacy.Schema())
	for _, c := range testkit.Frozen(t, "load") {
		t.Run(c.Name, func(t *testing.T) {
			t.Parallel()
			loaded, err := LoadLegacy(s, c.Input)
			if err != nil {
				t.Fatal(err)
			}
			c.Check(t, loaded.Object())
		})
	}
}
