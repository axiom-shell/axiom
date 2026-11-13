package windowrules

import (
	"errors"
	"fmt"
	"strings"
)

// ErrNoApp is Lower's error for an `app` condition whose app isn't installed.
var ErrNoApp = errors.New("windowrules: no installed app")

// Live: only the daemon can test it (process, startedFrom, game).
func (f Field) Live() bool {
	return f == FieldProcess || f == FieldStartedFrom || f == FieldGame
}

// Live: one of its conditions is live, so no compositor config can match it.
func (k Kind) Live() bool {
	for _, c := range k.Conditions {
		if c.Field.Live() {
			return true
		}
	}
	return false
}

// CompiledKinds are the rule's kinds a compositor's config can match, in order.
func (r Rule) CompiledKinds() []Kind { return r.kinds(false) }

// LiveKinds are the rule's kinds only the daemon can match, in order.
func (r Rule) LiveKinds() []Kind { return r.kinds(true) }

func (r Rule) kinds(live bool) []Kind {
	var out []Kind
	for _, k := range r.Kinds {
		if k.Live() == live {
			out = append(out, k)
		}
	}
	return out
}

// Test is one field's pattern in a lowered kind; Negated: the window must not match it.
type Test struct {
	Field   Field
	Regex   string
	Negated bool
}

// Flag is a yes/no condition (xwayland, game).
type Flag struct {
	Field Field
	Want  bool
}

// Lowered is a kind as the compositors' renderers and the engine take it.
type Lowered struct {
	Tests []Test
	Flags []Flag
	Live  bool
}

// AppIDs gives the app ids an installed app's windows have (an `app` condition's value).
type AppIDs func(desktopID string) []string

// anyOf is the anchored pattern matching any one of the literals.
func anyOf(ls []string) string {
	alts := make([]string, len(ls))
	for i, l := range ls {
		alts[i] = `(?:` + Literal(l) + `)`
	}
	return `\A(?:` + strings.Join(alts, "|") + `)\z`
}

// Lower is a valid kind as the compositors' renderers and the engine take it:
// positive tests in order, then one negated test per field with its
// literals merged into an alternation.
func Lower(k Kind, apps AppIDs) (Lowered, error) {
	out := Lowered{Live: k.Live()}
	var negFields []Field
	negs := map[Field][]string{}
	negate := func(f Field, literal string) {
		if _, ok := negs[f]; !ok {
			negFields = append(negFields, f)
		}
		negs[f] = append(negs[f], literal)
	}
	for _, c := range k.Conditions {
		switch c.Field {
		case FieldXwayland, FieldGame:
			out.Flags = append(out.Flags, Flag{Field: c.Field, Want: c.Op == OpIs})
			continue
		case FieldApp:
			ids := []string(nil)
			if apps != nil {
				ids = apps(c.Value)
			}
			if len(ids) == 0 {
				return Lowered{}, fmt.Errorf("%w: %s", ErrNoApp, c.Value)
			}
			if c.Op == OpIsNot {
				for _, id := range ids {
					negate(FieldAppID, id)
				}
			} else {
				out.Tests = append(out.Tests, Test{Field: FieldAppID, Regex: anyOf(ids)})
			}
			continue
		case FieldSteamGame:
			if c.Op == OpIsNot {
				negate(FieldAppID, "steam_app_"+c.Value)
				continue
			}
		default:
			if c.Op == OpIsNot {
				negate(c.Field, c.Value)
				continue
			}
		}
		re, err := c.Regex()
		if err != nil {
			return Lowered{}, err
		}
		f := c.Field
		if f == FieldSteamGame {
			f = FieldAppID
		}
		out.Tests = append(out.Tests, Test{Field: f, Regex: re})
	}
	for _, f := range negFields {
		out.Tests = append(out.Tests, Test{Field: f, Regex: anyOf(negs[f]), Negated: true})
	}
	return out, nil
}
