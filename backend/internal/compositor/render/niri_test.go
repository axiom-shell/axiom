package render

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

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
