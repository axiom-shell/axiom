package render

import (
	"regexp"
	"slices"
	"strings"
)

// --- BindActions' functions, on its tables ---

// at is v[i] for an array, nil past its end
func at(v any, i int) any {
	list := items(v)
	if i < len(list) {
		return list[i]
	}
	return nil
}

// SwitcherHeld is BindActions.switcherHeld: the modifiers a switcher combo
// is held by (all but SHIFT, unless SHIFT is all there is).
func SwitcherHeld(mods []string) []string {
	held := []string{}
	for _, m := range mods {
		if m != "SHIFT" && (m == "SUPER" || m == "CTRL" || m == "ALT") {
			held = append(held, m)
		}
	}
	if len(held) > 0 || !slices.Contains(mods, "SHIFT") {
		return held
	}
	return []string{"SHIFT"}
}

// CallOf is BindActions.callOf: a bind's call, "toggle" unless its action
// has the one it names.
func (t *Tables) CallOf(bind any) any {
	if get(get(t.Calls, str(get(bind, "action"))), str(get(bind, "call"))) != nil {
		return get(bind, "call")
	}
	return "toggle"
}

// CallFunction is BindActions.callFunction: the IPC function a bind's call
// runs.
func (t *Tables) CallFunction(bind any) string {
	return str(or(get(get(t.Calls, str(get(bind, "action"))), str(t.CallOf(bind))), "toggle"))
}

// NeedsArgument is BindActions.needsArgument.
func (t *Tables) NeedsArgument(action any) bool { return t.ArgumentKinds.Has(str(action)) }

// SectionFor is BindActions.sectionFor.
func (t *Tables) SectionFor(action any) string {
	a := str(action)
	return str(or(or(at(get(t.IPCActions, a), 2), at(get(t.CompositorActions, a), 1)), "Axiom"))
}

// DefaultLabel is BindActions.defaultLabel.
func (t *Tables) DefaultLabel(bind any) string {
	argument := trim(str(or(get(bind, "argument"), "")))
	action := str(get(bind, "action"))
	if action == "exec" {
		return argument
	}
	label := jsReplace(str(or(or(at(get(t.IPCActions, action), 1), at(get(t.CompositorActions, action), 0)), "")), "{0}", argument)
	if c := str(t.CallOf(bind)); c != "toggle" {
		return label + " (" + c + ")"
	}
	return label
}

var ownSection = regexp.MustCompile(`^[^:]+: \S`)

// HasOwnSection is BindActions.hasOwnSection.
func HasOwnSection(description any) bool {
	return ownSection.MatchString(trim(str(or(description, ""))))
}

// DescriptionFor is BindActions.descriptionFor: "Section: Label".
func (t *Tables) DescriptionFor(bind any) string {
	own := trim(str(or(get(bind, "description"), "")))
	if HasOwnSection(own) {
		return own
	}
	if own == "" {
		own = t.DefaultLabel(bind)
	}
	return t.SectionFor(get(bind, "action")) + ": " + own
}

// jsReplace is String.prototype.replace with a string pattern: the first
// occurrence, with the replacement's $$, $&, $` and $' as JS reads them
func jsReplace(s, pattern, repl string) string {
	i := strings.Index(s, pattern)
	if i < 0 {
		return s
	}
	var b strings.Builder
	for j := 0; j < len(repl); j++ {
		if repl[j] != '$' || j+1 >= len(repl) {
			b.WriteByte(repl[j])
			continue
		}
		switch repl[j+1] {
		case '$':
			b.WriteByte('$')
		case '&':
			b.WriteString(pattern)
		case '`':
			b.WriteString(s[:i])
		case '\'':
			b.WriteString(s[i+len(pattern):])
		default:
			b.WriteByte('$')
			continue
		}
		j++
	}
	return s[:i] + b.String() + s[i+len(pattern):]
}
