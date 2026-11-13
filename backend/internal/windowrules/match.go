package windowrules

import "regexp"

// Facts are what the rules test of a window.
type Facts struct {
	AppID, Title string
	XWayland     bool
	Process      *ProcessFacts // nil: not known (no pid, not ours, an X11 bridge)
	Game         bool
}

// ProcessFacts are a window's process name and the names above it, nearest first.
type ProcessFacts struct {
	Name      string
	Ancestors []string
}

// Matcher is rules ready to test windows: every kind lowered and its
// patterns compiled once.
type Matcher struct {
	rules [][]compiledKind
}

// compiledKind is a lowered kind with its patterns compiled.
type compiledKind struct {
	index int // its place in the rule's Kinds
	tests []compiledTest
	flags []Flag
}

type compiledTest struct {
	field   Field
	re      *regexp.Regexp
	negated bool
}

// NewMatcher lowers each rule's kinds; a kind Lower refuses, whose pattern
// doesn't compile, or that tests xwayland when xwayland is false (the
// compositor can't tell) matches nothing: the kinds compositor.state reports
// as skipped.
func NewMatcher(rules []Rule, apps AppIDs, xwayland bool) Matcher {
	m := Matcher{rules: make([][]compiledKind, len(rules))}
	for i, r := range rules {
		for ki, k := range r.Kinds {
			if ck, ok := compileKind(k, apps, xwayland); ok {
				ck.index = ki
				m.rules[i] = append(m.rules[i], ck)
			}
		}
	}
	return m
}

func compileKind(k Kind, apps AppIDs, xwayland bool) (compiledKind, bool) {
	l, err := Lower(k, apps)
	if err != nil {
		return compiledKind{}, false
	}
	ck := compiledKind{flags: l.Flags}
	for _, f := range l.Flags {
		if f.Field == FieldXwayland && !xwayland {
			return compiledKind{}, false
		}
	}
	for _, t := range l.Tests {
		re, err := regexp.Compile(t.Regex)
		if err != nil {
			return compiledKind{}, false
		}
		ck.tests = append(ck.tests, compiledTest{field: t.Field, re: re, negated: t.Negated})
	}
	return ck, true
}

// Match is the indices of the rules (in NewMatcher's order) one of whose
// kinds matches f.
func (m Matcher) Match(f Facts) []int {
	var out []int
	for i, kinds := range m.rules {
		for _, k := range kinds {
			if k.matches(f) {
				out = append(out, i)
				break
			}
		}
	}
	return out
}

func (k compiledKind) matches(f Facts) bool {
	for _, fl := range k.flags {
		got := f.XWayland
		if fl.Field == FieldGame {
			got = f.Game
		}
		if got != fl.Want {
			return false
		}
	}
	for _, t := range k.tests {
		if !t.holds(f) {
			return false
		}
	}
	return true
}

// holds tests one pattern. A window whose process isn't known satisfies no
// process or startedFrom test, negated or not: "isn't" means "known not to be".
func (t compiledTest) holds(f Facts) bool {
	switch t.field {
	case FieldAppID:
		return t.re.MatchString(f.AppID) != t.negated
	case FieldTitle:
		return t.re.MatchString(f.Title) != t.negated
	case FieldProcess:
		return f.Process != nil && t.re.MatchString(f.Process.Name) != t.negated
	case FieldStartedFrom:
		if f.Process == nil {
			return false
		}
		found := false
		for _, a := range f.Process.Ancestors {
			if t.re.MatchString(a) {
				found = true
				break
			}
		}
		return found != t.negated
	}
	return false
}
