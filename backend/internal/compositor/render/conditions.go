package render

import (
	"regexp"
	"strings"
)

// --- BindConditions' rule: a keybind's "Only when" ---

// internalPanel matches the connector names of a laptop's own panel
var internalPanel = regexp.MustCompile(`^(eDP|LVDS|DSI)-`)

// bindLayouts is BindConditions.layoutsOf: the layouts a bind needs, its
// own and strips for a strip action
func bindLayouts(bind any) []string {
	var out []string
	own := str(or(get(bind, "whenLayout"), ""))
	if own != "" {
		out = append(out, own)
	}
	if strings.HasPrefix(str(or(get(bind, "action"), "")), "strip") && own != "strips" {
		out = append(out, "strips")
	}
	return out
}

func layoutHolds(layout string, facts any) bool {
	switch layout {
	case "strips":
		return isTrue(get(facts, "strips"))
	case "tiling":
		return !isTrue(get(facts, "strips"))
	case "grid":
		return isTrue(get(facts, "grid"))
	case "dynamic":
		return isTrue(get(facts, "dynamic"))
	}
	return false
}

func monitorsHold(monitors string, outputs any) bool {
	names := items(outputs)
	if len(names) == 0 {
		return false
	}
	internal := 0
	for _, n := range names {
		if internalPanel.MatchString(str(n)) {
			internal++
		}
	}
	if monitors == "external" {
		return internal < len(names)
	}
	return internal == len(names)
}

// BindUnmet is BindConditions.unmet: the first part of a bind's condition
// that doesn't hold under facts ({ kind, strips, grid, dynamic, outputs }),
// "" when it holds.
func BindUnmet(bind, facts any) string {
	var list []any
	if str(or(get(bind, "action"), "")) != "raw" {
		list = items(get(bind, "whenCompositors"))
	}
	if len(list) > 0 {
		kind, found := str(or(get(facts, "kind"), "")), false
		for _, c := range list {
			found = found || str(c) == kind
		}
		if !found {
			return "compositor"
		}
	}
	for _, layout := range bindLayouts(bind) {
		if !layoutHolds(layout, facts) {
			return layout
		}
	}
	if m := str(or(get(bind, "whenMonitors"), "")); m != "" && !monitorsHold(m, get(facts, "outputs")) {
		return m
	}
	return ""
}

// BindHolds is BindConditions.holds: whether a bind's condition holds, so
// it's bound.
func BindHolds(bind, facts any) bool { return BindUnmet(bind, facts) == "" }
