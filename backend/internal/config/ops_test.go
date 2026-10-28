package config

import (
	"encoding/json"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func parseOps(t *testing.T, text string) []Op {
	t.Helper()
	var ops []Op
	if err := json.Unmarshal([]byte(text), &ops); err != nil {
		t.Fatal(err)
	}
	return ops
}

func cfg(t *testing.T, text string) *jsonx.Object {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Object)
}

func TestOps(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, config, ops, want string
		kind                    axerr.Kind
	}{
		// What the shell's ConfigOps.diff sends (tests/tst_ConfigOps.qml)
		{"the shell's set and delete", `{"a":{"b":1,"c":2}}`, `[{"op":"set","path":["a","c"],"value":3},{"op":"delete","path":["a","b"]}]`, `{"a":{"c":3}}`, ""},
		{"set makes objects", `{}`, `[{"op":"set","path":["A","b"],"value":1}]`, `{"A":{"b":1}}`, ""},
		{"set by id", `{"L":[{"id":"x","v":1},{"id":"y","v":2}]}`, `[{"op":"set","path":["L",{"id":"y"},"v"],"value":3}]`, `{"L":[{"id":"x","v":1},{"id":"y","v":3}]}`, ""},
		{"delete by id", `{"L":[{"id":"x"},{"id":"y"}]}`, `[{"op":"delete","path":["L",{"id":"x"}]}]`, `{"L":[{"id":"y"}]}`, ""},
		{"order", `{"L":[{"id":"x"},{"id":"y"}]}`, `[{"op":"order","path":["L"],"value":["y","x"]}]`, `{"L":[{"id":"y"},{"id":"x"}]}`, ""},
		{"append by id", `{"L":[]}`, `[{"op":"set","path":["L",{"id":"n"}],"value":{"id":"n"}}]`, `{"L":[{"id":"n"}]}`, ""},
		{"base matches", `{"a":1}`, `[{"op":"set","path":["a"],"value":2,"base":1}]`, `{"a":2}`, ""},
		{"base differs", `{"a":5}`, `[{"op":"set","path":["a"],"value":2,"base":1}]`, ``, axerr.Conflict},
		{"missing id", `{"L":[]}`, `[{"op":"set","path":["L",{"id":"q"},"v"],"value":1}]`, ``, axerr.NotFound},
		{"order mismatch", `{"L":[{"id":"x"}]}`, `[{"op":"order","path":["L"],"value":["x","y"]}]`, ``, axerr.Conflict},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := cfg(t, c.config)
			err := ApplyOps(got, parseOps(t, c.ops))
			if c.kind != "" {
				if axerr.KindOf(err) != c.kind {
					t.Fatalf("err %v, want %s", err, c.kind)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if s := string(jsonx.MarshalCompact(got)); s != c.want {
				t.Errorf("got %s want %s", s, c.want)
			}
		})
	}
}

func TestPathRefusesPositions(t *testing.T) {
	t.Parallel()
	var p Path
	if err := json.Unmarshal([]byte(`["Bars", 0]`), &p); err == nil {
		t.Error("a numeric index was accepted")
	}
	if err := json.Unmarshal([]byte(`["Bars", {"id": ""}]`), &p); err == nil {
		t.Error("an empty id was accepted")
	}
}

func TestDiff(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, before, after, want string
	}{
		{"same", `{"a":{"b":1}}`, `{"a":{"b":1}}`, `null`},
		{"a leaf", `{"a":{"b":1,"c":2}}`, `{"a":{"b":1,"c":3}}`, `[{"op":"set","path":["a","c"],"value":3}]`},
		{"a list whole", `{"L":[{"id":"x","v":1}]}`, `{"L":[{"id":"x","v":2}]}`, `[{"op":"set","path":["L"],"value":[{"id":"x","v":2}]}]`},
		{"a key gone", `{"a":{"b":1,"c":2}}`, `{"a":{"b":1}}`, `[{"op":"delete","path":["a","c"]}]`},
		{"a key new", `{}`, `{"a":{"b":1}}`, `[{"op":"set","path":["a"],"value":{"b":1}}]`},
		{"object to value", `{"a":{"b":1}}`, `{"a":null}`, `[{"op":"set","path":["a"],"value":null}]`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			before, after := cfg(t, c.before), cfg(t, c.after)
			ops := Diff(before, after)
			got, _ := json.Marshal(ops)
			if string(got) != c.want {
				t.Errorf("got %s want %s", got, c.want)
			}
			// The ops, as JSON both ways, turn before into after
			if err := ApplyOps(before, parseOps(t, string(got))); err != nil {
				t.Fatal(err)
			}
			if !jsonx.Equal(before, after) {
				t.Errorf("applied: %s, want %s", jsonx.MarshalCompact(before), c.after)
			}
		})
	}
}
