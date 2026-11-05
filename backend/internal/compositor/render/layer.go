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
	threshold := get(surfaces, "threshold")
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

// fitShadow is a shadow's size and color as a compositor draws it: the
// gaussian standing in for axiom's own when it's soft (and has a color to
// tint), else the spec's own.
func fitShadow(shadow any) (size, color any) {
	if !truthy(get(shadow, "soft")) || !truthy(get(shadow, "rgb")) {
		return get(shadow, "size"), get(shadow, "color")
	}
	r, a := GaussianShadow(shadow)
	return r, jsCat(get(shadow, "rgb")) + AlphaHex(a)
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

// XkbLayouts is InputSources.xkb: the compositor's xkb layouts from the
// input sources (Input.keyboard.sources): the xkb sources' distinct layout and
// variant pairs in order, then (with engines: Input.keyboard.method.enabled) any an
// ime source types on that none has, as { layouts, variants, layout:
// "us,de", variant: "" or ",neo" }. Never empty: "us" alone.
func XkbLayouts(sources any, engines bool) *jsonx.Object {
	type pair struct{ layout, variant string }
	var pairs []pair
	add := func(layout, variant string) {
		if layout == "" {
			return
		}
		for _, p := range pairs {
			if p.layout == layout && p.variant == variant {
				return
			}
		}
		pairs = append(pairs, pair{layout, variant})
	}
	kinds := []string{"xkb"}
	if engines {
		kinds = append(kinds, "ime")
	}
	for _, kind := range kinds {
		for _, s := range items(sources) {
			if get(s, "kind") == kind {
				add(text(get(s, "layout")), text(get(s, "variant")))
			}
		}
	}
	if len(pairs) == 0 {
		add("us", "")
	}
	layouts, variants := make([]string, len(pairs)), make([]string, len(pairs))
	anyVariant := false
	for i, p := range pairs {
		layouts[i], variants[i] = p.layout, p.variant
		anyVariant = anyVariant || p.variant != ""
	}
	variant := ""
	if anyVariant {
		variant = strings.Join(variants, ",")
	}
	return jsonx.Obj("layouts", strs(layouts), "variants", strs(variants), "layout", strings.Join(layouts, ","), "variant", variant)
}

// text is String(v ?? "").trim()
func text(v any) string {
	if v == nil {
		return ""
	}
	return trim(str(v))
}

// derived is a field's value as its spec's `from` makes it of the value
// stored (the input sources' xkb layouts or variants, the engines' counting
// while its siblings' method.enabled is on), ok false for a `from` it
// doesn't know
func derived(spec, value, siblings any) (any, bool) {
	switch str(or(get(spec, "from"), "")) {
	case "":
		return value, true
	case "xkbLayout":
		return XkbLayouts(value, isTrue(path(siblings, "method.enabled"))).Value("layout"), true
	case "xkbVariant":
		return XkbLayouts(value, isTrue(path(siblings, "method.enabled"))).Value("variant"), true
	}
	return nil, false
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
		// A list: the field writes several options (Input.keyboard.sources'
		// layouts and variants), each from its `from`
		specs := []any{spec}
		if list, ok := spec.(*jsonx.Array); ok {
			specs = list.Items
		}
		if truthy(spec) {
			for _, s := range specs {
				v, ok := derived(s, value, values)
				if !ok {
					continue
				}
				var on any
				if truthy(get(s, "if")) {
					on = isTrue(path(values, str(get(s, "if"))))
				}
				out = append(out, Field{prefix + key, fieldSchema, v, s, on})
			}
		} else if str(get(fieldSchema, "type")) == "object" && truthy(get(fieldSchema, "properties")) {
			out = append(out, CompositorFields(fieldSchema, value, compositor, prefix+key+".")...)
		}
	}
	return out
}

// path is the value at a dotted path under v (an `if` naming a sibling
// object's switch: "method.enabled")
func path(v any, dotted string) any {
	for _, key := range strings.Split(dotted, ".") {
		v = get(v, key)
	}
	return v
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

// The input method frameworks' variables, by the fcitx5 wiki's "Using
// Fcitx 5 on Wayland" (XMODIFIERS for XWayland, QT_IM_MODULES' fallback
// order for Qt 6.7+, SDL_IM_MODULE for SDL2) and ibus's equivalents;
// GLFW_IM_MODULE takes only ibus (kitty's GLFW), which fcitx5 also
// speaks. No GTK_IM_MODULE / QT_IM_MODULE: on Wayland they bypass GTK's and
// Qt's text-input path ("Do NOT set GTK_IM_MODULE"), so only legacyApps
// (X11, Gtk2, Qt5 under sway) adds them.
var inputMethodEnv = map[string][][2]string{
	"fcitx5": {{"XMODIFIERS", "@im=fcitx"}, {"QT_IM_MODULES", "wayland;fcitx;ibus"}, {"SDL_IM_MODULE", "fcitx"}, {"GLFW_IM_MODULE", "ibus"}},
	"ibus":   {{"XMODIFIERS", "@im=ibus"}, {"QT_IM_MODULES", "wayland;ibus"}, {"SDL_IM_MODULE", "ibus"}, {"GLFW_IM_MODULE", "ibus"}},
}

// inputMethodModule is the GTK / Qt im module legacyApps names
var inputMethodModule = map[string]string{"fcitx5": "fcitx", "ibus": "ibus"}

// The command starting each framework: fcitx5 as a daemon, replacing a
// running one; ibus-daemon (ibus-daemon(1)) daemonized (-d), replacing (-r),
// with XIM (-x), restarting on exit (-R)
var inputMethodCommand = map[string]string{"fcitx5": "fcitx5 -d --replace", "ibus": "ibus-daemon -drxR"}

// InputMethodEnv is the input method's variables for the session (im: {
// framework: "fcitx5" | "ibus" | "" for none (as resolved: installed),
// legacyApps })
func InputMethodEnv(im any) [][2]string {
	framework := str(or(get(im, "framework"), ""))
	out := append([][2]string(nil), inputMethodEnv[framework]...)
	if len(out) > 0 && truthy(get(im, "legacyApps")) {
		m := inputMethodModule[framework]
		out = append(out, [2]string{"GTK_IM_MODULE", m}, [2]string{"QT_IM_MODULE", m})
	}
	return out
}

// InputMethodCommand is the command starting the input method's framework
// (im as InputMethodEnv's, with autostart), "" for none
func InputMethodCommand(im any) string {
	if !truthy(get(im, "autostart")) {
		return ""
	}
	return inputMethodCommand[str(or(get(im, "framework"), ""))]
}

// SessionEnv is CompositorLayer.sessionEnv: the session's environment ([{
// name, value }], each name once): the recommended one, the theme
// integrations' and the input method's (integrations.inputMethod, as
// InputMethodEnv's), the cursor's, then the session's own, which win.
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
	for _, p := range InputMethodEnv(get(integrations, "inputMethod")) {
		all = append(all, pair{p[0], p[1]})
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
