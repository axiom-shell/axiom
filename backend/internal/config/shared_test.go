package config

import (
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
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

func stringsArray(list []string) *jsonx.Array {
	a := jsonx.Arr()
	for _, s := range list {
		a.Append(s)
	}
	return a
}

// recordedValueOf answers as the recorded valueOf did ({"$fn": {"[\"key\"]":
// answer}}): a key it wasn't asked for, or answered undefined for
// ({"$undefined": true}), isn't there.
func recordedValueOf(fn any) schema.ValueOf {
	fnObj, _ := jsonx.AsObject(fn)
	answers, _ := jsonx.AsObject(fnObj.Value("$fn"))
	return func(key string) (any, bool) {
		answer, ok := answers.Get(string(jsonx.MarshalCompact(jsonx.Arr(key))))
		if o, isObj := answer.(*jsonx.Object); isObj && o.Len() == 1 && o.Has("$undefined") {
			return nil, false
		}
		return answer, ok
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
	case "schema.showIfHolds":
		return schema.Holds(c.Args[0], recordedValueOf(c.Args[1]))
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
			c.Check(t, jsonx.Obj(
				"config", loaded.Config,
				"removed", stringsArray(loaded.Removed),
				"changes", stringsArray(loaded.Changes),
				"secrets", jsonx.NewObject(), // legacy.js's were always empty
				"errors", stringsArray(loaded.Errors),
			))
		})
	}
}
