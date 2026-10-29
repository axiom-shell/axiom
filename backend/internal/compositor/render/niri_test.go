package render

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The switcher binds go to niri's recent-windows, except one without a
// modifier (niri refuses it there): it stays axiom's.
func TestNiriRecentWindows(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	binds := jsonx.Arr(jsonx.Obj("key", "ALT + Tab", "action", "windowSwitcher"),
		jsonx.Obj("key", "F13", "action", "windowSwitcher"),
		jsonx.Obj("key", "SUPER + Q", "action", "closeWindow"))
	rest, recent := tab.NiriRecentWindows(binds)
	if recent == nil || len(rest.Items) != 2 || str(get(rest.Items[0], "key")) != "F13" {
		t.Fatalf("rest %v, recent %v", rest.Items, recent)
	}
}
