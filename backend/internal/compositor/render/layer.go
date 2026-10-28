package render

import (
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- CompositorLayer: what axiom asks of the compositor, decided once in a
// neutral shape every config writer turns into its own text ---

// hexByte is Math.round(v).toString(16).padStart(2, "0")
func hexByte(v float64) string {
	r := round(v)
	if math.IsNaN(r) {
		return "NaN"
	}
	s := strconv.FormatInt(int64(r), 16)
	if len(s) < 2 {
		s = "0" + s
	}
	return s
}

// Hex is CompositorLayer.hex: a color ({ r, g, b } in 0-1) as "rrggbb".
func Hex(color any) string {
	return hexByte(num(get(color, "r"))*255) + hexByte(num(get(color, "g"))*255) + hexByte(num(get(color, "b"))*255)
}

var colorText = regexp.MustCompile(`^#(?:[0-9a-fA-F]{2})?([0-9a-fA-F]{6})$`)

// TextHex is a color as the shell writes it ("#rrggbb", or "#aarrggbb"
// with alpha) as "rrggbb" (its alpha left out), or "" for anything else.
func TextHex(text string) string {
	if m := colorText.FindStringSubmatch(text); m != nil {
		return strings.ToLower(m[1])
	}
	return ""
}

var sixHex = regexp.MustCompile(`^[0-9a-fA-F]{6}`)

// Luminance is CompositorLayer.luminance: the relative luminance (0–1) of
// "rrggbb".
func Luminance(hex any) float64 {
	s := str(hex)
	if !sixHex.MatchString(s) {
		return 0
	}
	linear := func(i int) float64 {
		n, _ := strconv.ParseInt(s[i:i+2], 16, 32)
		c := float64(n) / 255
		if c <= 0.04045 {
			return c / 12.92
		}
		return pow((c+0.055)/1.055, 2.4)
	}
	return 0.2126*linear(0) + 0.7152*linear(2) + 0.0722*linear(4)
}

// AlphaHex is CompositorLayer.alphaHex: 0–1 as two hex digits.
func AlphaHex(alpha float64) string {
	return hexByte(math.Max(0, math.Min(1, alpha)) * 255)
}

var lookPartNames = []string{"borders", "shape", "gaps", "blur", "shadow", "dim", "opacity"}

// setDefined sets key unless the value is missing (JS leaves an undefined
// property out of JSON)
func setDefined(o *jsonx.Object, key string, from any, field string) {
	if v, ok := prop(from, field); ok {
		o.Set(key, v)
	}
}

// prop is v[key] and whether it's there
func prop(v any, key string) (any, bool) {
	if o, ok := v.(*jsonx.Object); ok {
		return o.Get(key)
	}
	return nil, false
}

func clamp01(a float64) float64 { return math.Max(0, math.Min(1, a)) }

// Look is CompositorLayer.look: the window look (WindowLook's values) as
// the parts that are on. opts: { activeHex, inactiveHex, borderWidth,
// radius, surfacesBlur, shadow }.
func Look(values, opts any) *jsonx.Object {
	var cast any
	if truthy(get(get(values, "shadow"), "enabled")) {
		cast = get(opts, "shadow")
	}
	var shadow any
	if truthy(cast) {
		strength := math.Max(0, num(or(get(cast, "strength"), 1.0)))
		alpha := clamp01(num(get(cast, "alpha")) * strength)
		s := jsonx.NewObject()
		setDefined(s, "size", cast, "size")
		setDefined(s, "power", get(values, "shadow"), "power")
		color := get(cast, "color")
		if !jsonx.StrictEqual(color, "") {
			s.Set("color", jsCat(color)+AlphaHex(alpha))
		} else {
			s.Set("color", "")
		}
		setDefined(s, "rgb", cast, "color")
		s.Set("alpha", alpha)
		s.Set("baseAlpha", clamp01(num(get(cast, "alpha"))))
		s.Set("strength", strength)
		s.Set("soft", isTrue(get(cast, "soft")))
		shadow = s
	}
	parts := []string{}
	for _, part := range lookPartNames {
		if part == "shadow" {
			if shadow != nil {
				parts = append(parts, part)
			}
		} else if isTrue(get(get(values, part), "enabled")) {
			parts = append(parts, part)
		}
	}
	on := func(part string) bool { return truthy(get(get(values, part), "enabled")) }
	out := jsonx.Obj("parts", strs(parts), "values", values)
	if on("borders") {
		b := jsonx.NewObject()
		setDefined(b, "active", opts, "activeHex")
		setDefined(b, "inactive", opts, "inactiveHex")
		out.Set("borders", b)
	} else {
		out.Set("borders", nil)
	}
	if on("shape") {
		s := jsonx.NewObject()
		setDefined(s, "width", opts, "borderWidth")
		setDefined(s, "radius", opts, "radius")
		out.Set("shape", s)
	} else {
		out.Set("shape", nil)
	}
	if on("gaps") {
		g := jsonx.NewObject()
		setDefined(g, "inner", get(values, "gaps"), "inner")
		setDefined(g, "outer", get(values, "gaps"), "outer")
		out.Set("gaps", g)
	} else {
		out.Set("gaps", nil)
	}
	if on("blur") {
		bv := get(values, "blur")
		b := jsonx.Obj("windows", isTrue(get(bv, "windowBlur")), "surfaces", isTrue(get(opts, "surfacesBlur")))
		setDefined(b, "size", bv, "size")
		setDefined(b, "passes", bv, "passes")
		b.Set("xray", isTrue(get(bv, "xray")))
		setDefined(b, "noise", bv, "noise")
		setDefined(b, "contrast", bv, "contrast")
		out.Set("blur", b)
	} else {
		out.Set("blur", nil)
	}
	out.Set("shadow", shadow)
	if on("dim") {
		d := jsonx.NewObject()
		setDefined(d, "strength", get(values, "dim"), "strength")
		out.Set("dim", d)
	} else {
		out.Set("dim", nil)
	}
	if on("opacity") {
		o := jsonx.NewObject()
		ov := get(values, "opacity")
		setDefined(o, "active", ov, "active")
		setDefined(o, "inactive", ov, "inactive")
		setDefined(o, "fullscreen", ov, "fullscreen")
		out.Set("opacity", o)
	} else {
		out.Set("opacity", nil)
	}
	return out
}

// jsCat is a value as `+` with a string writes it (undefined as
// "undefined")
func jsCat(v any) string {
	if v == nil {
		return "undefined"
	}
	return str(v)
}

// SurfaceBlur is CompositorLayer.surfaceBlur: what blurs behind axiom's
// surfaces, by namespace, as rule groups ({ name, namespaces, on, blur,
// popups, threshold, xray, noAnim }). surfaces: { blur, throughWindows,
// backdrops, threshold }.
func (t *Tables) SurfaceBlur(surfaces any) []*jsonx.Object {
	on := isTrue(get(surfaces, "blur"))
	xray := !isTrue(get(surfaces, "throughWindows"))
	threshold := or(get(surfaces, "threshold"), nil)
	row := func(name string, namespaces []string, rowOn bool, fields ...any) *jsonx.Object {
		r := jsonx.Obj("name", name, "namespaces", strs(namespaces), "on", rowOn, "blur", false, "popups", false,
			"threshold", nil, "xray", nil, "noAnim", false)
		for i := 0; i < len(fields); i += 2 {
			r.Set(fields[i].(string), fields[i+1])
		}
		return r
	}
	return []*jsonx.Object{
		row("axiom-blur", t.BlurSurfaces, on, "blur", true, "popups", true, "threshold", threshold, "xray", xray),
		// Hyprland never blurs a popup with xray; niri is told the same
		row("axiom-blur-popups", t.BlurChrome, on, "popups", true, "threshold", threshold, "xray", false),
		row("axiom-blur-backdrops", t.BlurBackdrops, on && isTrue(get(surfaces, "backdrops")), "blur", true, "threshold", 0.01, "xray", xray),
		row("axiom-blur-no-anim", t.BlurBacked, on, "noAnim", true),
		row("axiom-blur-over-overlay", t.BlurOverOverlay, on, "blur", true, "threshold", threshold, "xray", false),
	}
}

// GaussianShadow is CompositorLayer.gaussianShadow: a compositor shadow
// that's a gaussian standing in for axiom's own, as { radius, alpha }.
func GaussianShadow(shadow any) (radius, alpha float64) {
	size := math.Max(2, num(get(shadow, "size")))
	return round(size * 0.7),
		math.Min(1, num(get(shadow, "baseAlpha"))*math.Min(1, 0.2*log(size))*num(or(get(shadow, "strength"), 1.0)))
}

var inputPartNames = []string{"keyboard", "mouse", "touchpad", "cursor"}

// Input is CompositorLayer.input: the input (Input's values) as the parts
// that are on, with the cursor ({ theme, size, xcursor }) or null.
func Input(values any, xcursorTheme any) *jsonx.Object {
	parts := []string{}
	for _, part := range inputPartNames {
		if isTrue(get(get(values, part), "enabled")) {
			parts = append(parts, part)
		}
	}
	cursor := get(values, "cursor")
	out := jsonx.Obj("parts", strs(parts), "values", values)
	if truthy(get(cursor, "enabled")) && truthy(get(cursor, "theme")) {
		c := jsonx.Obj("theme", get(cursor, "theme"))
		setDefined(c, "size", cursor, "size")
		x := xcursorTheme
		if !truthy(x) {
			x = get(cursor, "theme")
		}
		c.Set("xcursor", x)
		out.Set("cursor", c)
	} else {
		out.Set("cursor", nil)
	}
	return out
}

// Field is one of CompositorLayer.compositorFields: a setting a
// compositor's config takes, by its x-compositor.<compositor> spec.
type Field struct {
	Name   string
	Schema any
	Value  any
	Spec   any
	// On: whether its `if` switch is on; nil without one
	On any
}

// CompositorFields is CompositorLayer.compositorFields.
func CompositorFields(objectSchema, values any, compositor, prefix string) []Field {
	var out []Field
	props := get(objectSchema, "properties")
	for _, key := range keys(props) {
		fieldSchema := get(props, key)
		value, ok := prop(values, key)
		if !ok {
			continue
		}
		spec := get(get(fieldSchema, "x-compositor"), compositor)
		if truthy(spec) {
			var on any
			if truthy(get(spec, "if")) {
				on = isTrue(get(values, str(get(spec, "if"))))
			}
			out = append(out, Field{prefix + key, fieldSchema, value, spec, on})
		} else if str(get(fieldSchema, "type")) == "object" && truthy(get(fieldSchema, "properties")) {
			out = append(out, CompositorFields(fieldSchema, value, compositor, prefix+key+".")...)
		}
	}
	return out
}

// AnnotatedFields is CompositorLayer.annotatedFields: with gated each
// field only while its `if` switch is on, else once changed from its
// default; without, every one.
func AnnotatedFields(sectionSchema, values any, compositor string, gated bool) []Field {
	var out []Field
	for _, f := range CompositorFields(sectionSchema, values, compositor, "") {
		if !gated {
			out = append(out, f)
			continue
		}
		if f.On != nil {
			if f.On.(bool) {
				out = append(out, f)
			}
			continue
		}
		if def, ok := prop(f.Schema, "default"); !ok || !jsonx.StrictEqual(f.Value, def) {
			out = append(out, f)
		}
	}
	return out
}

// The variables Hyprland's wiki recommends, good on any Wayland compositor
var recommendedEnv = [][2]string{{"GDK_BACKEND", "wayland,x11,*"}, {"QT_QPA_PLATFORM", "wayland;xcb"}, {"CLUTTER_BACKEND", "wayland"},
	{"ELECTRON_OZONE_PLATFORM_HINT", "auto"}, {"QT_AUTO_SCREEN_SCALE_FACTOR", "1"}, {"QT_WAYLAND_DISABLE_WINDOWDECORATION", "1"}}

var envName = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// SessionEnv is CompositorLayer.sessionEnv: the session's environment ([{
// name, value }], each name once): the recommended one, the theme
// integrations', the cursor's, then the session's own, which win.
func SessionEnv(session, cursor, integrations any) *jsonx.Array {
	type pair struct {
		name  string
		value any
	}
	var all []pair
	if truthy(get(session, "recommendedEnv")) {
		for _, p := range recommendedEnv {
			all = append(all, pair{p[0], p[1]})
		}
	}
	if truthy(get(integrations, "qt")) {
		all = append(all, pair{"QT_QPA_PLATFORMTHEME", "qt5ct"})
	}
	if truthy(cursor) {
		all = append(all, pair{"XCURSOR_THEME", or(get(cursor, "xcursor"), get(cursor, "theme"))},
			pair{"XCURSOR_SIZE", jsCat(get(cursor, "size"))})
	}
	for _, e := range items(get(session, "env")) {
		all = append(all, pair{trim(str(or(get(e, "name"), ""))), str(or(get(e, "value"), ""))})
	}
	var kept []pair
	for _, p := range all {
		if envName.MatchString(p.name) {
			kept = append(kept, p)
		}
	}
	out := jsonx.Arr()
	for i, p := range kept {
		later := false
		for _, q := range kept[i+1:] {
			if q.name == p.name {
				later = true
				break
			}
		}
		if !later {
			out.Append(jsonx.Obj("name", p.name, "value", p.value))
		}
	}
	return out
}
