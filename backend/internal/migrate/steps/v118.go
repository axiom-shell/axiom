package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v118 moves the popout-only options of two bar widgets into their popout's
// own `properties`, where the Bar editor's Popout card edits the options of
// the module the popout shows: the Network widget's popoutVpn became
// popout.properties.showVpn (WifiNetworks' key), the IdleInhibitor widget's
// presets popout.properties.presets (Caffeine's).
//
// A value already at the target wins; a `popout` or `popout.properties`
// that isn't an object leaves the widget alone. A second run changes
// nothing.
func v118(cfg *jsonx.Object) []string {
	var changes []string
	note := func(n int, what string) {
		if n > 0 {
			changes = append(changes, fmt.Sprintf("%d %s", n, what))
		}
	}
	move := func(typ, from, to string) int {
		return eachTyped(cfg.Value("Bars"), typ, func(p *jsonx.Object) bool { return moveIntoPopout(p, from, to) })
	}
	note(move("Network", "popoutVpn", "showVpn"), "Network widget(s): popoutVpn moved to popout.properties.showVpn")
	note(move("IdleInhibitor", "presets", "presets"), "Idle inhibitor widget(s): presets moved to popout.properties.presets")
	return changes
}

// moveIntoPopout moves the widget key from to popout.properties.<to>,
// creating the objects on the way; a value already there is kept and from
// dropped. A widget without from, or whose popout or popout.properties is
// not an object, is left alone.
func moveIntoPopout(p *jsonx.Object, from, to string) bool {
	if !p.Has(from) {
		return false
	}
	var popout any = jsonx.Obj()
	if p.Has("popout") {
		popout = p.Value("popout")
	}
	popoutObj, ok := popout.(*jsonx.Object)
	if !ok {
		return false
	}
	var props any = jsonx.Obj()
	if popoutObj.Has("properties") {
		props = popoutObj.Value("properties")
	}
	propsObj, ok := props.(*jsonx.Object)
	if !ok {
		return false
	}
	if !propsObj.Has(to) {
		propsObj.Set(to, p.Value(from))
	}
	popoutObj.Set("properties", propsObj)
	p.Set("popout", popoutObj)
	p.Delete(from)
	return true
}
