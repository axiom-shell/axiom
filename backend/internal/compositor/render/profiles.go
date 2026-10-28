package render

import (
	"slices"
	"strings"
)

// Output is a connected output as the profile picker sees it: its
// connector, its description as the shell gives it ("make model serial",
// the parts the compositor knows) and whether it's off.
type Output struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Disabled    bool   `json:"disabled"`
}

// names is whether a rule's output ("desc:" and a description, or a
// connector) is the output with this name and description.
func names(output, name, description string) bool {
	if desc, ok := strings.CutPrefix(output, "desc:"); ok {
		return trim(description) == trim(desc)
	}
	return name == output
}

// ruleOutput is a rule's output, "" when it has none.
func ruleOutput(rule any) string { return str(or(get(rule, "output"), "")) }

// connected is whether a rule's output names one of outputs.
func connected(output string, outputs []Output) bool {
	for _, o := range outputs {
		if names(output, o.Name, o.Description) {
			return true
		}
	}
	return false
}

// MatchProfile is the index of the saved profile (Monitors.items) for
// what's connected, or -1 when none turns any output on. Only enabled
// outputs count. A profile listing exactly
// those wins (a disabled rule's output may be missing), else the one
// turning on most of them; ties go to the earlier profile
// (MonitorLayout.matchProfile).
func MatchProfile(profiles any, outputs []Output) int {
	var on []Output
	for _, o := range outputs {
		if !o.Disabled {
			on = append(on, o)
		}
	}
	best, bestScore := -1, 0
	for i, profile := range items(profiles) {
		rules := items(get(profile, "outputs"))
		score, exact := 0, true
		for _, rule := range rules {
			found := connected(ruleOutput(rule), on)
			disabled := truthy(get(rule, "disabled"))
			if found && !disabled {
				score++
			}
			if !found && !disabled {
				exact = false
			}
		}
		for _, o := range on {
			exact = exact && slices.ContainsFunc(rules, func(rule any) bool { return names(ruleOutput(rule), o.Name, o.Description) })
		}
		if exact && score > 0 {
			score += 1000
		}
		if score > bestScore {
			best, bestScore = i, score
		}
	}
	return best
}

// SavedRules is the matched profile's rules naming a connected output
// (disabled ones too, so an output turned off stays off), or none when no
// profile matches: what a compositor is told to apply for what's
// connected.
func SavedRules(profiles any, outputs []Output) []any {
	index := MatchProfile(profiles, outputs)
	if index < 0 {
		return nil
	}
	var out []any
	for _, rule := range items(get(items(profiles)[index], "outputs")) {
		if connected(ruleOutput(rule), outputs) {
			out = append(out, rule)
		}
	}
	return out
}

// HyprlandRules is SavedRules for Hyprland, which lays a monitor plugged in
// out itself before the daemon's switch lands: with them, for each output
// a profile names that the matched profile's rules leave out, connected or
// not, the rule every profile naming it agrees on (an external monitor
// always set the same way), so it's laid out once, on plug and after the
// switch alike. An output the profiles set differently gets no rule
// (Hyprland's own layout, then the switch: a second modeset).
func HyprlandRules(profiles any, outputs []Output) []any {
	out := SavedRules(profiles, outputs)
	if out == nil {
		return nil
	}
	var covered []Output
	for _, o := range outputs {
		if slices.ContainsFunc(out, func(rule any) bool { return names(ruleOutput(rule), o.Name, o.Description) }) {
			covered = append(covered, o)
		}
	}
	var order []string
	agreed := map[string]any{}
	specs := map[string]string{}
	for _, profile := range items(profiles) {
		for _, rule := range items(get(profile, "outputs")) {
			output := ruleOutput(rule)
			if output == "" || connected(output, covered) {
				continue
			}
			spec := InlineSpec(MonitorSpec(rule))
			if seen, ok := specs[output]; !ok {
				order = append(order, output)
				specs[output], agreed[output] = spec, rule
			} else if seen != spec {
				agreed[output] = nil
			}
		}
	}
	for _, output := range order {
		if agreed[output] != nil {
			out = append(out, agreed[output])
		}
	}
	return out
}
