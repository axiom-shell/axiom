package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v116 is the module options audit's renames and reshapes:
//   - the Markets module's layout and the Cheatsheet module's view became
//     style, the Agenda module's maxEvents count;
//   - the Favourites module's showLabels (on/off) became labels
//     (auto/hide);
//   - the Login and Password modules' centered (on/off) became alignment
//     (center/left);
//   - the Markets bar widget's showPortfolio became showHoldings, the Network
//     bar widget's showVpn showVpnLock, and the Workspaces bar widget's
//     labels cellLabels (bar widgets only: a Network module gets its own
//     showVpn, and QuickActions keeps labels).
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
	renameWidget := func(typ, from, to string) int {
		return eachTyped(cfg.Value("Bars"), typ, func(p *jsonx.Object) bool { return renameInPlace(p, from, to) })
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
	note(eachModule(cfg, "Login", centeredToAlignment)+eachModule(cfg, "Password", centeredToAlignment),
		"Login/Password module(s): centered became alignment")
	note(renameWidget("Markets", "showPortfolio", "showHoldings"), "Markets widget(s): showPortfolio became showHoldings")
	note(renameWidget("Network", "showVpn", "showVpnLock"), "Network widget(s): showVpn became showVpnLock")
	note(renameWidget("Workspaces", "labels", "cellLabels"), "Workspaces widget(s): labels became cellLabels")
	return changes
}

// centeredToAlignment turns a module's centered flag into alignment (true
// centers, false left); with alignment already set, or a non-boolean, the
// flag is just dropped.
func centeredToAlignment(p *jsonx.Object) bool {
	if !p.Has("centered") {
		return false
	}
	on, ok := p.Value("centered").(bool)
	if p.Has("alignment") || !ok {
		p.Delete("centered")
		return true
	}
	renameInPlace(p, "centered", "alignment")
	if on {
		p.Set("alignment", "center")
	} else {
		p.Set("alignment", "left")
	}
	return true
}
