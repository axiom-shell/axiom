package daemon

import (
	"encoding/json"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The ConfigOps.* shared cases (recorded from the shell's ConfigOps.qml).
// The contract check sees config.set's params only as ConfigManager.commit's
// literal ({ops, takeover}), not the ops ConfigOps.diff builds in them, so
// here: each diff the shell makes, sent as commit sends it, decodes
// strictly as config.set's params and gives the shell's after once applied,
// and Go's Diff makes the same bytes; each apply of the shell's (a push's
// changes) is what Go's ApplyOps makes.
func TestSharedConfigOpsCases(t *testing.T) {
	t.Parallel()
	cases := testkit.Cases(t, "ConfigOps.")
	if len(cases) == 0 {
		t.Fatal("no ConfigOps cases recorded")
	}
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			t.Parallel()
			before := object(t, c.Args[0])
			switch c.Op {
			case "ConfigOps.diff":
				var p setParams
				raw := `{"ops":` + string(c.Expected) + `,"takeover":false}`
				if err := rpc.DecodeStrict(json.RawMessage(raw), &p); err != nil {
					t.Fatalf("config.set doesn't decode the shell's params: %v", err)
				}
				got := jsonx.Clone(before).(*jsonx.Object)
				if err := config.ApplyOps(got, p.Ops); err != nil {
					t.Fatal(err)
				}
				if after := c.Args[1]; !jsonx.Equal(got, after) {
					t.Errorf("applied: got %s, want %s", jsonx.MarshalCompact(got), jsonx.MarshalCompact(after))
				}
				c.Compare(t, opsTree(t, config.Diff(before, object(t, c.Args[1]))))
			case "ConfigOps.apply":
				// null: ops the shell doesn't apply (it reads the config again)
				if string(c.Expected) == "null\n" {
					return
				}
				var ops []config.Op
				if err := json.Unmarshal(jsonx.MarshalCompact(c.Args[1]), &ops); err != nil {
					t.Fatal(err)
				}
				got := jsonx.Clone(before).(*jsonx.Object)
				if err := config.ApplyOps(got, ops); err != nil {
					t.Fatal(err)
				}
				c.Compare(t, got)
			default:
				t.Skipf("%s has no Go side", c.Op)
			}
		})
	}
}

func object(t *testing.T, v any) *jsonx.Object {
	t.Helper()
	o, ok := jsonx.AsObject(v)
	if !ok {
		t.Fatalf("not an object: %s", jsonx.MarshalCompact(v))
	}
	return o
}

// opsTree is ops as the JSON tree the shell's would be read into (none
// as [], as the shell's).
func opsTree(t *testing.T, ops []config.Op) any {
	t.Helper()
	data, err := json.Marshal(append([]config.Op{}, ops...))
	if err != nil {
		t.Fatal(err)
	}
	v, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return v
}
