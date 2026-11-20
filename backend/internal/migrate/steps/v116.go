package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v116 is the module options audit's renames and reshapes:
//   - the Markets module's layout and the Cheatsheet module's view became
//     style, the Agenda module's maxEvents count;
//   - the Favourites module's showLabels (on/off) became labels
//     (auto/hide).
//
// Each part acts on the old shape only, so a second run changes nothing.
func v116(cfg *jsonx.Object) []string {
	var changes []string
	note := func(n int, what string) {
		if n > 0 {
			changes = append(changes, fmt.Sprintf("%d %s", n, what))
		}
	}
	rename := func(typ, from, to string) int {
		return eachModule(cfg, typ, func(p *jsonx.Object) bool { return renameInPlace(p, from, to) })
	}

	note(rename("Markets", "layout", "style"), "Markets module(s): layout became style")
	note(rename("Cheatsheet", "view", "style"), "Cheatsheet module(s): view became style")
	note(rename("Agenda", "maxEvents", "count"), "Agenda module(s): maxEvents became count")
	note(eachModule(cfg, "Favourites", func(p *jsonx.Object) bool {
		if !p.Has("showLabels") {
			return false
		}
		if p.Has("labels") {
			p.Delete("showLabels")
			return true
		}
		on, ok := p.Value("showLabels").(bool)
		if !ok {
			p.Delete("showLabels")
			return true
		}
		renameInPlace(p, "showLabels", "labels")
		if on {
			p.Set("labels", "auto")
		} else {
			p.Set("labels", "hide")
		}
		return true
	}), "Favourites module(s): showLabels became labels")
	return changes
}
