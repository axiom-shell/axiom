package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v117 is the module options' re-defaults to Auto (user: "Migrate to
// Auto"; existing cards, deliberate picks included):
//   - the Quick actions module's style tiles became auto (it then follows
//     the card's size);
//   - the Markets and Cheatsheet modules' style list became auto.
//
// Each part acts on the old value only, so a second run changes nothing.
func v117(cfg *jsonx.Object) []string {
	var changes []string
	note := func(n int, what string) {
		if n > 0 {
			changes = append(changes, fmt.Sprintf("%d %s", n, what))
		}
	}
	toAuto := func(typ, from string) int {
		return eachModule(cfg, typ, func(p *jsonx.Object) bool {
			if p.Value("style") != from {
				return false
			}
			p.Set("style", "auto")
			return true
		})
	}

	note(toAuto("QuickActions", "tiles"), "Quick actions module(s): style tiles became auto")
	note(toAuto("Markets", "list"), "Markets module(s): style list became auto")
	note(toAuto("Cheatsheet", "list"), "Cheatsheet module(s): style list became auto")
	return changes
}
