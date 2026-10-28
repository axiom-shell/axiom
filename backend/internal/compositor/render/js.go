// Package render is the text of axiom's layer in each compositor's own
// config language: Hyprland's Lua, sway's commands and niri's KDL, the
// window look and input, binds, outputs and the files the config writers
// write (docs/dev/compositor/config-modes.md). Pure: no I/O.
//
// It's a port of the shell's JS helpers (components/methods/HyprLua,
// HyprConfigLua, SwayConf, NiriConf, CompositorLayer, BindKeys, BindActions'
// and KeyNames' functions), function for function and on the same JSON
// values (jsonx), checked byte for byte against the calls their tests make
// (the shared fixtures' <Helper>.<function> suites). What the JS reads from
// LayerStack's tables and the bind actions' (actions.JSON, handed to
// BindActions) comes in as Tables. Values follow the JS: a missing value
// is nil, as null is.
package render

import (
	"math"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf16"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Func is a function value handed in (a theme color's hex, a mirror's
// connector), as the JS callers pass one.
type Func func(args ...any) any

// get is v[key] (v?.[key]): nil when v isn't an object or has no key
func get(v any, key string) any {
	if o, ok := v.(*jsonx.Object); ok {
		return o.Value(key)
	}
	return nil
}

// has is whether key is set on the object v, as JS's `key in v`
func has(v any, key string) bool {
	o, ok := v.(*jsonx.Object)
	return ok && o.Has(key)
}

// or is a ?? b
func or(a, b any) any {
	if a == nil {
		return b
	}
	return a
}

// str is String(v)
func str(v any) string { return jsonx.ToString(v) }

// num is Number(v)
func num(v any) float64 { return jsonx.ToNumber(v) }

// truthy is JS truthiness
func truthy(v any) bool { return jsonx.Truthy(v) }

// isTrue is v === true
func isTrue(v any) bool { b, ok := v.(bool); return ok && b }

// fmtNum is a number as JS writes it
func fmtNum(f float64) string { return jsonx.FormatNumber(f) }

// round is Math.round: halves toward +∞
func round(f float64) float64 { return math.Floor(f + 0.5) }

func isFinite(f float64) bool { return !math.IsNaN(f) && !math.IsInf(f, 0) }

// toFixed is Number.prototype.toFixed for small digits counts
func toFixed(f float64, digits int) string { return strconv.FormatFloat(f, 'f', digits, 64) }

// jsLen is a string's length as JS counts it (UTF-16 units)
func jsLen(s string) int { return len(utf16.Encode([]rune(s))) }

// items is an array's values, nil for anything else
func items(v any) []any {
	if a, ok := v.(*jsonx.Array); ok {
		return a.Items
	}
	return nil
}

// keys is an object's keys in JS order, nil for anything else
func keys(v any) []string {
	if o, ok := v.(*jsonx.Object); ok {
		return o.Keys()
	}
	return nil
}

// strs is a list of strings as a JSON array
func strs(list []string) *jsonx.Array {
	a := jsonx.Arr()
	for _, s := range list {
		a.Append(s)
	}
	return a
}

// stringList is an array's strings (the JS's string arrays handed in)
func stringList(v any) []string {
	var out []string
	for _, x := range items(v) {
		out = append(out, str(x))
	}
	return out
}

// replaceFirst is String.prototype.replace(string, string): the first
// occurrence only
func replaceFirst(s, old, repl string) string { return strings.Replace(s, old, repl, 1) }

var numberSplit = regexp.MustCompile(`[\s,]+`)

// twoNumbers is `text.split(/[\s,]+/).map(Number)`'s first two (NaN when
// missing)
func twoNumbers(text string) (float64, float64) {
	parts := numberSplit.Split(text, -1)
	at := func(i int) float64 {
		if i < len(parts) {
			return jsonx.ToNumber(parts[i])
		}
		return math.NaN()
	}
	return at(0), at(1)
}

// call calls a function handed in (nil when it isn't one)
func call(f any, args ...any) any {
	if fn, ok := f.(Func); ok {
		return fn(args...)
	}
	return nil
}

// trim is String.prototype.trim
func trim(s string) string { return strings.TrimFunc(s, isJSSpace) }

func isJSSpace(r rune) bool {
	switch r {
	case '\t', '\n', '\v', '\f', '\r', ' ', 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff:
		return true
	}
	return r >= 0x2000 && r <= 0x200a
}
