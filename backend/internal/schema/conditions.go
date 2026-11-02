package schema

import (
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// ValueOf looks a condition's key up: a sibling's value, or with a leading
// "/" a dotted path from the config's root (or a runtime value such as
// "/$compositor"). ok is false for a value that isn't there.
type ValueOf func(key string) (value any, ok bool)

// Holds reports whether a condition (x-showIf, x-enabledIf, x-scopeIf's
// `when`) holds: every key must, each as
//
//	value            equal to it
//	[values]         one of them
//	{not: value}     anything but it
//	{notEmpty: true} a non-empty string or list
//	{includes: v}    a list holding v
//	anyOf: [conds]   any of the conditions
//
// A missing or null condition holds. This is SchemaLayout.showIfHolds.
func Holds(condition any, valueOf ValueOf) bool {
	cond, ok := condition.(*jsonx.Object)
	if !jsonx.Truthy(condition) {
		return true
	}
	if !ok {
		// A truthy non-object condition has no keys: every() of nothing
		return true
	}
	for _, key := range cond.Keys() {
		want := cond.Value(key)
		if key == "anyOf" {
			any := false
			if list, ok := want.(*jsonx.Array); ok {
				for _, c := range list.Items {
					if Holds(c, valueOf) {
						any = true
						break
					}
				}
			}
			if !any {
				return false
			}
			continue
		}
		value, present := valueOf(key)
		switch w := want.(type) {
		case *jsonx.Array:
			found := false
			if present {
				for _, x := range w.Items {
					if jsonx.SameValueZero(x, value) {
						found = true
						break
					}
				}
			}
			if !found {
				return false
			}
		case *jsonx.Object:
			if jsonx.Truthy(w.Value("notEmpty")) {
				if length(value, present) <= 0 {
					return false
				}
				continue
			}
			if item, ok := w.Get("includes"); ok {
				list, isList := value.(*jsonx.Array)
				if !present || !isList || !slices.ContainsFunc(list.Items, func(x any) bool { return jsonx.SameValueZero(x, item) }) {
					return false
				}
				continue
			}
			not, hasNot := w.Get("not")
			// value !== want.not, with undefined on either side
			equal := present == hasNot && (!present || jsonx.StrictEqual(value, not))
			if equal {
				return false
			}
		default:
			if !present || !jsonx.StrictEqual(value, want) {
				return false
			}
		}
	}
	return true
}

// length is value?.length ?? 0 for a string or a list (UTF-16 units for a
// string, as JS counts; only zero or not matters here).
func length(value any, present bool) int {
	if !present {
		return 0
	}
	switch v := value.(type) {
	case string:
		return len(v)
	case *jsonx.Array:
		return len(v.Items)
	}
	return 0
}
