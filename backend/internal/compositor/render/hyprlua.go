package render

import (
	"math"
	"slices"
	"sort"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- HyprLua: Hyprland's Lua config from schema fields ---

var luaEscapes = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\r", `\r`)

// LuaString is HyprLua.string: a Lua string literal.
func LuaString(text any) string {
	return `"` + luaEscapes.Replace(jsCat(text)) + `"`
}

// LuaValue is HyprLua.value: strings quoted, numbers without float noise.
func LuaValue(v any) string {
	switch x := v.(type) {
	case string:
		return LuaString(x)
	case float64:
		return fmtNum(round(x*10000) / 10000)
	case nil:
		return "undefined"
	}
	return str(v)
}

func convert(spec, v any, resolveHex any) any {
	if s, ok := prop(spec, "scale"); ok && s != nil {
		return num(v) * num(s)
	}
	switch str(get(spec, "value")) {
	case "int":
		if truthy(v) {
			return 1.0
		}
		return 0.0
	case "number":
		return num(v)
	case "color":
		return "rgba(" + jsCat(call(resolveHex, v)) + str(or(get(spec, "alpha"), "ff")) + ")"
	}
	return v
}

// setPath sets the dotted path in a nested table, making the tables on
// the way (HyprLua._set)
func setPath(table *jsonx.Object, path string, v any) {
	names := strings.Split(path, ".")
	node := table
	for _, key := range names[:len(names)-1] {
		next, ok := node.Value(key).(*jsonx.Object)
		if !ok {
			next = jsonx.NewObject()
			node.Set(key, next)
		}
		node = next
	}
	node.Set(names[len(names)-1], v)
}

// ConfigTable is HyprLua.configTable: the nested option table for values
// (objectSchema's fields with x-compositor.hyprland). resolveHex gives a
// theme color's "rrggbb"; overrides map option paths to values that win.
func ConfigTable(objectSchema, values, resolveHex, overrides any) *jsonx.Object {
	table := jsonx.NewObject()
	for _, f := range CompositorFields(objectSchema, values, "hyprland", "") {
		spec := f.Spec
		if f.On != nil {
			if !f.On.(bool) {
				continue
			}
		} else if !truthy(get(spec, "always")) {
			if def, ok := prop(f.Schema, "default"); ok && jsonx.StrictEqual(f.Value, def) {
				continue
			}
		}
		if skip, ok := prop(spec, "skip"); ok && jsonx.StrictEqual(f.Value, skip) {
			continue
		}
		v := convert(spec, f.Value, resolveHex)
		var paths []string
		if s, ok := get(spec, "key").(string); ok {
			paths = []string{s}
		} else {
			paths = stringList(get(spec, "key"))
		}
		for _, p := range paths {
			setPath(table, p, v)
		}
	}
	for _, p := range keys(overrides) {
		setPath(table, p, get(overrides, p))
	}
	return table
}

// Serialize is HyprLua.serialize: a table as a Lua literal, keys sorted;
// nested tables on lines of their own below the top level, until one fits
// on a line.
func Serialize(table *jsonx.Object, pad string) string {
	ks := table.Keys()
	sort.Strings(ks)
	entry := func(key string) string {
		v := table.Value(key)
		if a, ok := v.(*jsonx.Array); ok {
			vals := make([]string, len(a.Items))
			for i, x := range a.Items {
				vals[i] = LuaValue(x)
			}
			return key + " = { " + strings.Join(vals, ", ") + " }"
		}
		if o, ok := v.(*jsonx.Object); ok {
			return key + " = " + Serialize(o, pad+"  ")
		}
		return key + " = " + LuaValue(v)
	}
	entries := make([]string, len(ks))
	for i, k := range ks {
		entries[i] = entry(k)
	}
	flat := "{ " + strings.Join(entries, ", ") + " }"
	if len(ks) == 0 {
		return "{}"
	}
	if pad != "" && jsLen(flat) <= 100 && !strings.Contains(flat, "\n") {
		return flat
	}
	var b strings.Builder
	b.WriteString("{\n")
	for i, e := range entries {
		if i > 0 {
			b.WriteString("\n")
		}
		b.WriteString(pad + "  " + e + ",")
	}
	b.WriteString("\n" + pad + "}")
	return b.String()
}

// hlConfig is `hl.config(<table>)`, or "" for an empty table
func hlConfig(table *jsonx.Object) string {
	if table.Len() == 0 {
		return ""
	}
	return "hl.config(" + Serialize(table, "") + ")"
}

// SoftShadow is HyprLua.softShadow: Hyprland's shadow standing in for
// axiom's own (a soft one), as { range, power, alpha }.
func SoftShadow(shadow any) (rng, power, alpha float64) {
	lum := Luminance(get(shadow, "rgb"))
	factor := math.Max(0.01, 0.3*pow(0.018/0.3, lum/0.45))
	return round(num(get(shadow, "size")) * 1.2), 4,
		math.Min(1, num(get(shadow, "baseAlpha"))*factor*num(or(get(shadow, "strength"), 1.0)))
}

// jsOr is a || b
func jsOr(a, b any) any {
	if truthy(a) {
		return a
	}
	return b
}

// LookLua is HyprLua.lookLua: the look's parts that are on (look:
// CompositorLayer.look) as the lines of one hl.config(), plus the rule
// keeping windows unblurred while only axiom's surfaces blur.
func LookLua(look, lookSchema any) []string {
	blur := get(look, "blur")
	table := ConfigTable(lookSchema, get(look, "values"), nil, blurOverrides(blur))
	if b := get(look, "borders"); truthy(b) {
		setPath(table, "general.col", jsonx.Obj("active_border", "rgb("+jsCat(get(b, "active"))+")",
			"inactive_border", "rgb("+jsCat(get(b, "inactive"))+")"))
	}
	if s := get(look, "shape"); truthy(s) {
		setPath(table, "general.border_size", get(s, "width"))
		setPath(table, "decoration.rounding", get(s, "radius"))
	}
	if g := get(look, "gaps"); truthy(g) {
		setPath(table, "general.gaps_in", get(g, "inner"))
		setPath(table, "general.gaps_out", get(g, "outer"))
	}
	if s := get(look, "shadow"); truthy(s) {
		soft := truthy(get(s, "soft")) && !jsonx.StrictEqual(get(s, "rgb"), "")
		rng, power, alpha := get(s, "size"), get(s, "power"), num(get(s, "alpha"))
		if soft {
			r, p, a := SoftShadow(s)
			rng, power, alpha = r, p, a
		}
		setPath(table, "decoration.shadow.enabled", true)
		setPath(table, "decoration.shadow.range", rng)
		setPath(table, "decoration.shadow.render_power", power)
		// Spread evenly, as axiom's own (0 still resets the user's)
		setPath(table, "decoration.shadow.offset", jsonx.Arr(0.0, 0.0))
		if !jsonx.StrictEqual(get(s, "rgb"), "") {
			setPath(table, "decoration.shadow.color", "rgba("+jsCat(get(s, "rgb"))+AlphaHex(alpha)+")")
		}
	}
	if d := get(look, "dim"); truthy(d) {
		setPath(table, "decoration.dim_inactive", true)
		setPath(table, "decoration.dim_strength", num(get(d, "strength"))/100)
	}
	return append(luaLines(table), noWindowBlurRule(blur)...)
}

// LookBlurLua is the part of LookLua that follows whether axiom's surfaces
// blur (look.blur.surfaces): sent alone when only that changed.
func LookBlurLua(look any) []string {
	blur := get(look, "blur")
	overrides, table := blurOverrides(blur), jsonx.NewObject()
	for _, p := range keys(overrides) {
		setPath(table, p, get(overrides, p))
	}
	return append(luaLines(table), noWindowBlurRule(blur)...)
}

// blurOverrides: Hyprland's blur is on while windows or axiom's surfaces
// blur (look.blur, nil while the part is off)
func blurOverrides(blur any) *jsonx.Object {
	overrides := jsonx.NewObject()
	if truthy(blur) {
		overrides.Set("decoration.blur.enabled", jsOr(get(blur, "windows"), get(blur, "surfaces")))
		if !truthy(get(blur, "windows")) {
			overrides.Set("decoration.blur.popups", false)
		}
	}
	return overrides
}

// noWindowBlurRule keeps windows unblurred while only axiom's surfaces
// blur: redefined (on or off) while the blur part is on; turning the part
// off reloads Hyprland, which drops it
func noWindowBlurRule(blur any) []string {
	if !truthy(blur) {
		return nil
	}
	enabled := !truthy(get(blur, "windows")) && truthy(get(blur, "surfaces"))
	return []string{`hl.window_rule({ name = "axiom-no-window-blur", match = { class = ".*" }, no_blur = true, enabled = ` + boolText(enabled) + ` })`}
}

// luaLines is one hl.config() of table, as lines (none when it's empty)
func luaLines(table *jsonx.Object) []string {
	if table.Len() == 0 {
		return nil
	}
	return strings.Split(hlConfig(table), "\n")
}

func boolText(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// LayerRulesLua is a named layer rule per LayerStack.layers entry (adding
// one again replaces it): its order, which Hyprland reads as a surface
// maps, and its animation.
func (t *Tables) LayerRulesLua() []string {
	out := make([]string, len(t.Layers))
	for i, l := range t.Layers {
		ns := str(l.Value("namespace"))
		effects := ""
		if truthy(l.Value("noAnim")) {
			effects += ", no_anim = true"
		}
		if order, ok := l.Get("order"); ok {
			effects += ", order = " + str(order)
		}
		out[i] = "hl.layer_rule({ name = " + LuaString("axiom-"+ns) + ", match = { namespace = " + LuaString("^axiom-"+ns+"$") + " }" + effects + " })"
	}
	return out
}

// BlurLua is HyprLua.blurLua: the blur behind axiom's surfaces as named
// layer rules, always written, enabled or not.
func (t *Tables) BlurLua(surfaces any) []string {
	var out []string
	for _, rule := range t.SurfaceBlur(surfaces) {
		var effects []string
		if isTrue(rule.Value("blur")) {
			effects = append(effects, "blur = true")
		}
		if isTrue(rule.Value("popups")) {
			effects = append(effects, "blur_popups = true")
		}
		if th := rule.Value("threshold"); th != nil {
			effects = append(effects, "ignore_alpha = "+LuaValue(th))
		}
		if x := rule.Value("xray"); x != nil {
			effects = append(effects, "xray = "+str(x))
		}
		if isTrue(rule.Value("noAnim")) {
			effects = append(effects, "no_anim = true")
		}
		out = append(out, "hl.layer_rule({ name = "+LuaString(rule.Value("name"))+", match = { namespace = "+
			LuaString("^axiom-("+strings.Join(stringList(rule.Value("namespaces")), "|")+")$")+" }, "+strings.Join(effects, ", ")+
			", enabled = "+str(rule.Value("on"))+" })")
	}
	return out
}

var stripDirections = map[string]string{"horizontal": "right", "vertical": "down"}

func stripDirection(d any) any {
	if v, ok := stripDirections[str(d)]; ok {
		return v
	}
	return nil
}

// StripsLua is HyprLua.stripsLua: the strips (Hyprland's scrolling layout),
// [{ monitor, direction }] with monitors resolved ("*" = every monitor).
func StripsLua(strips, workspacesSchema, values any) []string {
	list := items(strips)
	if len(list) == 0 {
		return []string{}
	}
	table := ConfigTable(workspacesSchema, values, nil, nil)
	for _, s := range list {
		if str(get(s, "monitor")) == "*" {
			setPath(table, "general.layout", "scrolling")
			setPath(table, "scrolling.direction", stripDirection(get(s, "direction")))
			break
		}
	}
	out := []string{}
	if table.Len() > 0 {
		out = append(out, hlConfig(table))
	}
	for _, s := range list {
		if str(get(s, "monitor")) != "*" {
			out = append(out, "hl.workspace_rule({ workspace = "+LuaString("m["+jsCat(get(s, "monitor"))+"]")+
				`, layout = "scrolling", layout_opts = { direction = `+LuaString(stripDirection(get(s, "direction")))+" } })")
		}
	}
	return out
}

// StripsRuntimeLua is HyprLua.stripsRuntimeLua: stripsLua's lines applied
// once per Hyprland config load (key names them in AXIOM_STRIPS).
func StripsRuntimeLua(lines []string, key string) []string {
	out := []string{"if AXIOM_STRIPS == nil then"}
	for _, l := range lines {
		out = append(out, "  "+l)
	}
	return append(out, "  AXIOM_STRIPS = "+LuaString(key), "elseif AXIOM_STRIPS ~= "+LuaString(key)+" then",
		`  hl.dispatch(hl.dsp.exec_cmd("hyprctl reload"))`, "end")
}

// MonitorSpec is HyprLua.monitorSpec: a monitor rule as hl.monitor()'s spec.
func MonitorSpec(rule any) *jsonx.Object {
	if truthy(get(rule, "disabled")) {
		return jsonx.Obj("output", get(rule, "output"), "disabled", true)
	}
	spec := jsonx.Obj("output", get(rule, "output"), "mode", jsOr(get(rule, "mode"), "preferred"),
		"position", fmtNum(round(num(or(get(rule, "x"), 0.0))))+"x"+fmtNum(round(num(or(get(rule, "y"), 0.0)))),
		"scale", or(get(rule, "scale"), 1.0))
	for _, k := range []string{"transform", "mirror", "vrr"} {
		if v := get(rule, k); truthy(v) {
			spec.Set(k, v)
		}
	}
	if get(rule, "bitdepth") == 10.0 {
		spec.Set("bitdepth", 10.0)
	}
	if cm := get(rule, "cm"); truthy(cm) && cm != "auto" {
		spec.Set("cm", cm)
	}
	if v, ok := prop(rule, "sdrBrightness"); ok && v != 1.0 {
		spec.Set("sdrbrightness", v)
	}
	if v, ok := prop(rule, "sdrSaturation"); ok && v != 1.0 {
		spec.Set("sdrsaturation", v)
	}
	return spec
}

var specOrder = []string{"output", "mode", "position", "scale"}

// InlineSpec is HyprLua.inlineSpec: a spec on one line, output first.
func InlineSpec(spec *jsonx.Object) string {
	ks := spec.Keys()
	rank := func(k string) int {
		if i := slices.Index(specOrder, k); i >= 0 {
			return i
		}
		return 99
	}
	sort.SliceStable(ks, func(i, j int) bool {
		if ri, rj := rank(ks[i]), rank(ks[j]); ri != rj {
			return ri < rj
		}
		return ks[i] < ks[j]
	})
	parts := make([]string, len(ks))
	for i, k := range ks {
		parts[i] = k + " = " + LuaValue(spec.Value(k))
	}
	return "{ " + strings.Join(parts, ", ") + " }"
}

// MonitorCalls is hl.monitor() calls for rules applied now
// (outputs.apply); mirrorName gives the connector a mirror target is on
// (MirrorNames), or "".
func MonitorCalls(rules any, mirrorName any) []string {
	var out []string
	for _, rule := range items(rules) {
		spec := MonitorSpec(rule)
		if m, ok := spec.Get("mirror"); ok {
			if name := call(mirrorName, m); truthy(name) {
				spec.Set("mirror", name)
			} else {
				spec.Delete("mirror")
			}
		}
		out = append(out, "hl.monitor("+InlineSpec(spec)+")")
	}
	return out
}

// MirrorNames is MonitorCalls' mirrorName for details (the outputs
// connected): the name of the one a rule's output names (its connector, or
// "desc:" and its description), or "".
func MirrorNames(details any) Func {
	return func(args ...any) any {
		value := ""
		if len(args) > 0 {
			value = str(or(args[0], ""))
		}
		for _, d := range items(details) {
			name := str(or(get(d, "name"), ""))
			if names(value, name, str(or(get(d, "description"), ""))) {
				return name
			}
		}
		return ""
	}
}

// HyprFileMonitorCalls are the hl.monitor() calls of a profile in a
// module or managed config axiom wrote: the profile it holds until the
// outputs are read.
func HyprFileMonitorCalls(text any) []string {
	out := []string{}
	for _, l := range strings.Split(str(or(text, "")), "\n") {
		if l = strings.TrimSpace(l); strings.HasPrefix(l, `hl.monitor({ output = "`) {
			out = append(out, l)
		}
	}
	return out
}

// InputLua is HyprLua.inputLua: the input's parts that are on as one
// hl.config(), or none.
func InputLua(input, inputSchema any) []string {
	table := ConfigTable(inputSchema, get(input, "values"), nil, jsonx.NewObject())
	if table.Len() == 0 {
		return []string{}
	}
	return strings.Split(hlConfig(table), "\n")
}

// GreeterLua is the greeter's Hyprland's Lua: the Input options marked
// x-greeter (none a color, so no resolveHex), or none.
func GreeterLua(inputSchema, input any) []string {
	if !truthy(input) {
		return nil
	}
	if table := ConfigTable(greeterSchema(inputSchema), input, nil, jsonx.NewObject()); table.Len() > 0 {
		return []string{hlConfig(table)}
	}
	return nil
}

// greeterSchema is objectSchema with only its x-greeter settings
func greeterSchema(objectSchema any) *jsonx.Object {
	props := jsonx.NewObject()
	out := jsonx.Obj("type", "object", "properties", props)
	p := get(objectSchema, "properties")
	for _, key := range keys(p) {
		field := get(p, key)
		if isTrue(get(field, "x-greeter")) {
			props.Set(key, field)
		} else if str(get(field, "type")) == "object" && truthy(get(field, "properties")) {
			if inner := greeterSchema(field); get(inner, "properties").(*jsonx.Object).Len() > 0 {
				props.Set(key, inner)
			}
		}
	}
	return out
}

// LeaveSubmap is HyprLua.leaveSubmap.
func LeaveSubmap(name string) string {
	return "if hl.get_current_submap() == " + LuaString(name) + ` then hl.dispatch(hl.dsp.submap("reset")) end`
}

// The window switcher's submap and events (HyprLua's switcher)
const (
	SwitcherSubmap   = "axiom_switcher"
	SwitcherEvent    = "axiom-switcher:"
	SwitcherLeaveLua = "if axiom_switcher_leave then axiom_switcher_leave() end"
)

var switcherModifierKeys = map[string][]string{"SUPER": {"Super_L", "Super_R"}, "CTRL": {"Control_L", "Control_R"},
	"ALT": {"Alt_L", "Alt_R"}, "SHIFT": {"Shift_L", "Shift_R"}}

func switcherDispatch(verb string) string {
	return "hl.dispatch(hl.dsp.event(" + LuaString(SwitcherEvent+verb) + "))"
}

// SwitcherBindLua is HyprLua.switcherBindLua: the switcher bind's
// dispatcher.
func SwitcherBindLua(step any) string {
	return "function() hl.dispatch(hl.dsp.submap(" + LuaString(SwitcherSubmap) + ")); if axiom_switcher_watch then axiom_switcher_watch() end; " +
		switcherDispatch("step "+jsCat(step)) + " end"
}

// SwitcherLua is HyprLua.switcherLua: the switcher's submap and its key
// listener, for entries ([{ mods, key, step }]).
func SwitcherLua(entries any) []string {
	var binds, ks, held []string
	bind := func(key, body, options string) {
		ks = append(ks, key)
		binds = append(binds, "  hl.bind("+LuaString(key)+", function() "+body+" end, { "+options+" })")
	}
	for _, e := range items(entries) {
		mods := stringList(get(e, "mods"))
		bind(JoinKey(mods, str(get(e, "key"))), switcherDispatch("step "+jsCat(get(e, "step"))), "repeating = true")
		for _, m := range SwitcherHeld(mods) {
			for _, k := range switcherModifierKeys[m] {
				if !slices.Contains(held, k) {
					held = append(held, k)
				}
			}
		}
	}
	if len(binds) > 0 {
		bind("Return", switcherDispatch("commit")+"; axiom_switcher_leave()", "ignore_mods = true")
		bind("Escape", switcherDispatch("cancel")+"; axiom_switcher_leave()", "ignore_mods = true")
	}
	quoted := func(list []string) string {
		q := make([]string, len(list))
		for i, s := range list {
			q[i] = LuaString(s)
		}
		return strings.Join(q, ", ")
	}
	out := []string{"hl.define_submap(" + LuaString(SwitcherSubmap) + ", function()", "  for _, key in ipairs(AXIOM_SWITCHER_KEYS or {}) do hl.unbind(key) end"}
	out = append(out, binds...)
	return append(out, "end)", "AXIOM_SWITCHER_KEYS = { "+quoted(ks)+" }", "AXIOM_SWITCHER_HELD = { "+quoted(held)+" }",
		`function axiom_switcher_unwatch()
  if AXIOM_SWITCHER_SUB then AXIOM_SWITCHER_SUB:remove() end
  AXIOM_SWITCHER_SUB = nil
end`, `function axiom_switcher_leave()
  axiom_switcher_unwatch()
  `+LeaveSubmap(SwitcherSubmap)+`
end`, `function axiom_switcher_watch()
  if AXIOM_SWITCHER_SUB then return end
  AXIOM_SWITCHER_SUB = hl.on("input.keyboard.key", function(_, _, state)
    if state ~= 0 then return end
    AXIOM_SWITCHER_CHECK = hl.timer(function()
      if hl.get_current_submap() ~= `+LuaString(SwitcherSubmap)+` then return axiom_switcher_unwatch() end
      for _, key in ipairs(AXIOM_SWITCHER_HELD) do
        if hl.is_key_down(key) then return end
      end
      `+switcherDispatch("commit")+`
      axiom_switcher_leave()
    end, { timeout = 10, type = "oneshot" })
  end)
end`)
}
