package render

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/kdl"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A parsed node is written back as niri reads it: escapes, a float kept a
// float, a name that isn't bare quoted.
func TestKdlNodeText(t *testing.T) {
	t.Parallel()
	nodes, err := kdl.Parse("spawn \"a \\\"b\\\"\r\" 1 2.0 0.25 true focus=false\n\"odd name\" 1\n")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := KdlNodeText(nodes[0]), `spawn "a \"b\"\r" 1 2.0 0.25 true focus=false`; got != want {
		t.Errorf("got %s, want %s", got, want)
	}
	if got, want := KdlNodeText(nodes[1]), `"odd name" 1`; got != want {
		t.Errorf("got %s, want %s", got, want)
	}
}

// The switcher binds go to niri's recent-windows, except one without a
// modifier or a mouse wheel key (niri refuses those there): they stay axiom's.
func TestNiriRecentWindows(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	binds := jsonx.Arr(jsonx.Obj("key", "ALT + Tab", "action", "windowSwitcher"),
		jsonx.Obj("key", "F13", "action", "windowSwitcher"),
		jsonx.Obj("key", "ALT + mouse_down", "action", "windowSwitcherReverse"),
		jsonx.Obj("key", "SUPER + Q", "action", "closeWindow"))
	rest, recent := tab.NiriRecentWindows(binds)
	if recent == nil || len(rest.Items) != 3 || str(get(rest.Items[0], "key")) != "F13" || str(get(rest.Items[1], "key")) != "ALT + mouse_down" {
		t.Fatalf("rest %v, recent %v", rest.Items, recent)
	}
}

// The edge comes out at the outer gap: struts of outer - inner, negative
// where the inner gaps are wider (niri draws the edge narrower then).
func TestNiriLookGapsEdge(t *testing.T) {
	t.Parallel()
	look := jsonx.Obj("gaps", jsonx.Obj("inner", float64(10), "outer", float64(0)))
	got := KdlSerialize(NiriLookNodes(look), 0)
	want := "layout {\n    gaps 10\n    struts {\n        left -10\n        right -10\n        top -10\n        bottom -10\n    }\n}"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
