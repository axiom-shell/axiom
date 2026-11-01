package render

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The description the compositor gets for a bind: "Section: Label", the
// section from the action unless the description names its own
func TestDescriptionFor(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	for _, c := range []struct {
		bind *jsonx.Object
		want string
	}{
		{jsonx.Obj("action", "closeWindow"), "Window: Close"},
		{jsonx.Obj("action", "closeWindow", "description", "Kill it"), "Window: Kill it"},
		{jsonx.Obj("action", "closeWindow", "description", "Mine: Kill it"), "Mine: Kill it"},
	} {
		if got := tab.DescriptionFor(c.bind); got != c.want {
			t.Errorf("%s: got %q, want %q", jsonx.MarshalCompact(c.bind), got, c.want)
		}
	}
}
