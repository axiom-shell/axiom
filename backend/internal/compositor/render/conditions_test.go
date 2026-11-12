package render

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A raw command's own compositor is appliesUnder's, so BindUnmet doesn't
// turn it down for another compositor (BindConditions.unmet's same row).
func TestBindUnmetRawCompositor(t *testing.T) {
	t.Parallel()
	bind := jsonx.Obj("action", "raw", "compositor", "sway")
	facts := jsonx.Obj("kind", "niri", "outputs", []any{"eDP-1"})
	if got := BindUnmet(bind, facts); got != "" {
		t.Errorf("BindUnmet(raw sway, niri) = %q, want empty", got)
	}
}
