package render

import (
	"math"
	"regexp"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- NiriConf: niri's config text (KDL) and IPC requests. Text is built as
// nodes ({ name, args, props, children }, or { raw } for text as the user
// wrote it) and written out last, so a section is written once per file ---

// Node is NiriConf.node: a node; children nil for none, an array for a
// block.
func Node(name any, args, props, children any) *jsonx.Object {
	return jsonx.Obj("name", name, "args", or(args, jsonx.Arr()), "props", or(props, jsonx.NewObject()), "children", or(children, nil))
}

func node(name string, args ...any) *jsonx.Object { return Node(name, jsonx.Arr(args...), nil, nil) }

func block(name string, children ...any) *jsonx.Object {
	return Node(name, nil, nil, jsonx.Arr(children...))
}

var kdlEscapes = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\r", `\r`, "\t", `\t`)

// KdlString is NiriConf.kdlString.
func KdlString(text any) string { return `"` + kdlEscapes.Replace(jsCat(text)) + `"` }

// real is NiriConf.real: a number niri reads as a float
func real(v any) *jsonx.Object { return jsonx.Obj("real", num(v)) }

// KdlValue is NiriConf.kdlValue.
func KdlValue(v any) string {
	if o, ok := v.(*jsonx.Object); ok && o.Has("real") {
		rounded := round(num(o.Value("real"))*1000) / 1000
		if jsonx.IsInteger(rounded) {
			return toFixed(rounded, 1)
		}
		return fmtNum(rounded)
	}
	switch x := v.(type) {
	case bool:
		return boolText(x)
	case float64:
		return fmtNum(round(x*1000) / 1000)
	}
	return KdlString(v)
}

var kdlBare = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_+\-.]*$`)

func kdlName(name any) string {
	if s := jsCat(name); kdlBare.MatchString(s) {
		return s
	}
	return KdlString(name)
}

// KdlSerialize is NiriConf.serialize: nodes as KDL text, depth levels in.
func KdlSerialize(nodes any, depth int) string {
	pad := strings.Repeat("    ", depth)
	var out []string
	for _, n := range items(nodes) {
		if raw, ok := prop(n, "raw"); ok {
			out = append(out, pad+jsCat(raw))
			continue
		}
		head := []string{kdlName(get(n, "name"))}
		for _, a := range items(get(n, "args")) {
			head = append(head, KdlValue(a))
		}
		props := get(n, "props")
		for _, k := range keys(props) {
			head = append(head, k+"="+KdlValue(get(props, k)))
		}
		h := strings.Join(head, " ")
		children := get(n, "children")
		switch {
		case children == nil:
			out = append(out, pad+h)
		case len(items(children)) == 0:
			out = append(out, pad+h+" {}")
		default:
			out = append(out, pad+h+" {\n"+KdlSerialize(children, depth+1)+"\n"+pad+"}")
		}
	}
	return strings.Join(out, "\n")
}

func nameOf(n any) any { return get(n, "name") }

func isBlock(n any) bool { return get(n, "children") != nil }

// KdlSetPath is NiriConf.setPath: sets the node at the dotted path in
// nodes (changed in place) to args (and props), making the sections on
// the way; a leaf already there is replaced.
func KdlSetPath(nodes *jsonx.Array, path string, args, props any) {
	names := strings.Split(path, ".")
	level := nodes
	for _, name := range names[:len(names)-1] {
		var section any
		for _, n := range level.Items {
			if nameOf(n) == name && isBlock(n) {
				section = n
				break
			}
		}
		if section == nil {
			section = Node(name, jsonx.Arr(), jsonx.NewObject(), jsonx.Arr())
			level.Append(section)
		}
		level = get(section, "children").(*jsonx.Array)
	}
	leaf := names[len(names)-1]
	made := Node(leaf, args, props, nil)
	for i, n := range level.Items {
		if nameOf(n) == leaf {
			level.Items[i] = made
			return
		}
	}
	level.Append(made)
}

var repeatingSections = []string{"window-rule", "layer-rule", "output", "spawn-at-startup", "spawn-sh-at-startup", "workspace", "include"}

// KdlMerged is NiriConf.merged: nodes with sections of the same name joined
// in place of the first (repeating nodes and raw text stay apart).
func KdlMerged(nodes any) *jsonx.Array {
	out := jsonx.Arr()
	for _, n := range items(nodes) {
		if has(n, "raw") {
			out.Append(n)
			continue
		}
		var same any
		if isBlock(n) && !slices.Contains(repeatingSections, str(nameOf(n))) {
			for _, o := range out.Items {
				if jsonx.StrictEqual(nameOf(o), nameOf(n)) && isBlock(o) {
					same = o
					break
				}
			}
		}
		if same == nil {
			if isBlock(n) {
				out.Append(Node(nameOf(n), get(n, "args"), get(n, "props"), jsonx.Arr(items(get(n, "children"))...)))
			} else {
				out.Append(n)
			}
			continue
		}
		sameChildren := get(same, "children").(*jsonx.Array)
		for _, child := range items(get(n, "children")) {
			at := -1
			for i, c := range sameChildren.Items {
				if jsonx.StrictEqual(nameOf(c), nameOf(child)) {
					at = i
					break
				}
			}
			switch {
			case at >= 0 && isBlock(child) && isBlock(sameChildren.Items[at]):
				sameChildren.Items[at] = KdlMerged(jsonx.Arr(sameChildren.Items[at], child)).Items[0]
			case at >= 0:
				sameChildren.Items[at] = child
			default:
				sameChildren.Append(child)
			}
		}
	}
	return out
}

// --- Keys ---

var (
	niriModNames   = map[string]string{"SUPER": "Super", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift", "MOD5": "ISO_Level3_Shift"}
	niriMouseNames = map[string]string{"mouse:272": "MouseLeft", "mouse:273": "MouseRight", "mouse:274": "MouseMiddle", "mouse:275": "MouseBack",
		"mouse:276": "MouseForward", "mouse_up": "WheelScrollUp", "mouse_down": "WheelScrollDown", "mouse_left": "WheelScrollLeft",
		"mouse_right": "WheelScrollRight"}
	niriWheel = regexp.MustCompile(`^mouse_(up|down|left|right)$`)
)

// NiriKey is NiriConf.key: a combo as niri binds it ("Super+Shift+Q"), or ""
// when niri can't bind it.
func NiriKey(combo any) string {
	c := SplitKey(combo)
	if c.Key == "" || strings.HasPrefix(c.Key, "code:") || TapModifier(combo) != "" {
		return ""
	}
	var mods []string
	for _, m := range c.Mods {
		name, ok := niriModNames[m]
		if !ok {
			return ""
		}
		mods = append(mods, name)
	}
	key := c.Key
	if mouse, ok := niriMouseNames[strings.ToLower(c.Key)]; ok {
		key = mouse
	} else if strings.HasPrefix(c.Key, "mouse") {
		return ""
	}
	return strings.Join(append(mods, key), "+")
}

// --- Binds ---

// NiriActionNode is NiriConf.actionNode: the niri action (a node) of a
// compositor action for argument, or nil. ctx: { axiomBin, restartCommand,
// terminal, fileManager, browser, … }.
func (t *Tables) NiriActionNode(action, argument string, ctx any) *jsonx.Object {
	sides := map[string]string{"left": "column-or-monitor-left", "right": "column-or-monitor-right", "up": "window-or-monitor-up", "down": "window-or-monitor-down"}
	switch action {
	case "focusDir":
		if s, ok := sides[argument]; ok {
			return node("focus-" + s)
		}
		return nil
	case "moveWindowDir":
		moves := map[string]string{"left": "move-column-left-or-to-monitor-left", "right": "move-column-right-or-to-monitor-right",
			"up": "move-window-up", "down": "move-window-down"}
		if m, ok := moves[argument]; ok {
			return node(m)
		}
		return nil
	case "resizeWindow":
		// One action a bind: across or along, not both
		x, y := twoNumbers(argument)
		if !isFinite(x) || !isFinite(y) || (x != 0) == (y != 0) {
			return nil
		}
		change := func(v float64) string {
			if v > 0 {
				return "+" + fmtNum(v)
			}
			return fmtNum(v)
		}
		if x != 0 {
			return node("set-column-width", change(x))
		}
		return node("set-window-height", change(y))
	case "closeWindow":
		return node("close-window")
	case "fullscreen":
		return node("fullscreen-window")
	case "toggleFloat":
		return node("toggle-window-floating")
	case "centerWindow":
		return node("center-window")
	case "toggleGroup":
		return node("toggle-column-tabbed-display")
	case "stripSwapColumn":
		if towardsStart(argument) {
			return node("move-column-left")
		}
		return node("move-column-right")
	case "stripWider":
		return node("set-column-width", "+10%")
	case "stripNarrower":
		return node("set-column-width", "-10%")
	case "stripFit":
		return node("expand-column-to-available-width")
	case "stripConsume":
		if towardsStart(argument) {
			return node("consume-or-expel-window-left")
		}
		return node("consume-or-expel-window-right")
	case "stripCenter":
		return node("center-column")
	case "raw":
		return jsonx.Obj("raw", argument)
	case "windowSwitcher", "windowSwitcherReverse":
		way := "previous"
		if num(get(t.SwitcherSteps, action)) > 0 {
			way = "next"
		}
		return niriIPC(ctx, []any{"windowSwitcher", way})
	case "restartShell":
		return node("spawn-sh", get(ctx, "restartCommand"))
	case "exitSession":
		return Node("quit", jsonx.Arr(), jsonx.Obj("skip-confirmation", true), nil)
	case "terminal", "fileManager", "browser":
		return node("spawn-sh", get(ctx, action))
	}
	return nil
}

func niriIPC(ctx any, words []any) *jsonx.Object {
	return node("spawn", append([]any{get(ctx, "axiomBin"), "ipc"}, words...)...)
}

// NiriActionFor is NiriConf.actionFor: a configured bind's action node, or
// nil.
func (t *Tables) NiriActionFor(bind, ctx any) *jsonx.Object {
	argument := trim(str(or(get(bind, "argument"), "")))
	action := str(get(bind, "action"))
	if trim(str(or(get(bind, "key"), ""))) == "" || (t.NeedsArgument(get(bind, "action")) && argument == "") {
		return nil
	}
	if action == "raw" && str(or(get(bind, "compositor"), "hyprland")) != "niri" {
		return nil
	}
	switch {
	case truthy(get(t.CompositorActions, action)):
		return t.NiriActionNode(action, argument, ctx)
	case action == "exec":
		return node("spawn-sh", argument)
	case truthy(get(t.IPCActions, action)):
		call := jsReplace(str(at(get(t.IPCActions, action), 0)), "{call}", t.CallFunction(bind))
		var words []any
		for _, w := range strings.Split(call, " ") {
			if w == "{0}" {
				words = append(words, argument)
			} else {
				words = append(words, w)
			}
		}
		return niriIPC(ctx, words)
	}
	return nil
}

// NiriBindNode is NiriConf.bindNode: a configured bind as a node of niri's
// binds, or nil.
func (t *Tables) NiriBindNode(bind, ctx any) *jsonx.Object {
	action := t.NiriActionFor(bind, ctx)
	k := NiriKey(get(bind, "key"))
	if action == nil || k == "" {
		return nil
	}
	props := jsonx.Obj("hotkey-overlay-title", t.DescriptionFor(bind))
	if !truthy(get(bind, "repeating")) {
		props.Set("repeat", false)
	}
	if truthy(get(bind, "locked")) {
		props.Set("allow-when-locked", true)
	}
	if niriWheel.MatchString(SplitKey(get(bind, "key")).Key) {
		props.Set("cooldown-ms", 150.0)
	}
	return Node(k, jsonx.Arr(), props, jsonx.Arr(action))
}

// NiriRecentWindows takes the switcher binds out of binds into niri's own
// switcher's (`recent-windows { binds { … } }`, which replaces niri's
// default ones): the rest, and that node (nil with none).
func (t *Tables) NiriRecentWindows(binds any) (*jsonx.Array, *jsonx.Object) {
	rest := jsonx.Arr()
	var own []any
	seen := map[string]bool{}
	for _, b := range items(binds) {
		step, ok := t.SwitcherSteps.Get(str(get(b, "action")))
		if !ok {
			rest.Append(b)
			continue
		}
		k := NiriKey(get(b, "key"))
		if k == "" || seen[strings.ToLower(k)] {
			continue
		}
		seen[strings.ToLower(k)] = true
		way := "previous-window"
		if num(step) > 0 {
			way = "next-window"
		}
		own = append(own, Node(k, nil, nil, jsonx.Arr(node(way))))
	}
	if len(own) == 0 {
		return rest, nil
	}
	return rest, block("recent-windows", block("binds", own...))
}

// NiriIsComplete is NiriConf.isComplete.
func (t *Tables) NiriIsComplete(bind, ctx any) bool { return t.NiriBindNode(bind, ctx) != nil }

// NiriBindsNode is NiriConf.bindsNode: the binds section of every complete
// bind (nil with none), each key once.
func (t *Tables) NiriBindsNode(binds, ctx any) *jsonx.Object {
	seen := map[string]bool{}
	var children []any
	for _, b := range items(binds) {
		n := t.NiriBindNode(b, ctx)
		if n == nil || seen[strings.ToLower(str(nameOf(n)))] {
			continue
		}
		seen[strings.ToLower(str(nameOf(n)))] = true
		children = append(children, n)
	}
	if len(children) == 0 {
		return nil
	}
	return block("binds", children...)
}

// NiriBindEntries is NiriConf.bindEntries: axiom's complete binds as
// BindKeys' entries.
func (t *Tables) NiriBindEntries(binds, ctx any) *jsonx.Array {
	out := jsonx.Arr()
	for _, b := range items(binds) {
		if !t.NiriIsComplete(b, ctx) {
			continue
		}
		id := KeyID(get(b, "key"))
		at := strings.Index(id, ":")
		mask, key := "", id
		if at >= 0 {
			mask, key = id[:at], id[at+1:]
		} else if id != "" {
			mask = id[:len(id)-1]
		}
		out.Append(jsonx.Obj("modmask", jsonx.ToNumber(mask), "key", key, "keycode", 0.0, "submap", "", "description", t.DescriptionFor(b)))
	}
	return out
}

// --- The window look ---

// NiriLookNodes is NiriConf.lookNodes: the look's parts that are on as
// niri's nodes.
func NiriLookNodes(look any) *jsonx.Array {
	nodes := jsonx.Arr()
	layout := func(path string, args ...any) { KdlSetPath(nodes, "layout."+path, jsonx.Arr(args...), nil) }
	if b := get(look, "borders"); truthy(b) {
		for _, part := range []string{"border", "focus-ring"} {
			layout(part+".active-color", hashColor(get(b, "active")))
			layout(part+".inactive-color", hashColor(get(b, "inactive")))
		}
	}
	if s := get(look, "shape"); truthy(s) {
		width := math.Max(0, round(num(get(s, "width"))))
		layout("focus-ring.off")
		if width > 0 {
			layout("border.on")
			layout("border.width", width)
		} else {
			layout("border.off")
		}
		nodes.Append(block("window-rule", node("geometry-corner-radius", math.Max(0, round(num(get(s, "radius"))))), node("clip-to-geometry", true)))
	}
	if g := get(look, "gaps"); truthy(g) {
		inner := math.Max(0, round(num(get(g, "inner"))))
		edge := math.Max(0, round(num(get(g, "outer")))-inner)
		layout("gaps", inner)
		for _, side := range []string{"left", "right", "top", "bottom"} {
			layout("struts."+side, edge)
		}
	}
	if b := get(look, "blur"); truthy(b) {
		KdlSetPath(nodes, "blur.passes", jsonx.Arr(math.Max(1, round(num(get(b, "passes"))))), nil)
		KdlSetPath(nodes, "blur.offset", jsonx.Arr(math.Max(0, round(num(get(b, "size"))))), nil)
		KdlSetPath(nodes, "blur.noise", jsonx.Arr(real(math.Max(0, num(get(b, "noise")))/1000)), nil)
		if truthy(get(b, "windows")) {
			nodes.Append(block("window-rule", block("background-effect", node("blur", true), node("xray", isTrue(get(b, "xray"))))))
		}
	}
	if s := get(look, "shadow"); truthy(s) {
		soft := truthy(get(s, "soft")) && truthy(get(s, "rgb"))
		size := num(get(s, "size"))
		var color any = get(s, "color")
		if soft {
			r, a := GaussianShadow(s)
			size = r
			color = jsCat(get(s, "rgb")) + AlphaHex(a)
		}
		layout("shadow.on")
		layout("shadow.softness", math.Max(0, round(size)))
		// Spread evenly, as axiom's own (0 still resets the user's)
		KdlSetPath(nodes, "layout.shadow.offset", jsonx.Arr(), jsonx.Obj("x", 0.0, "y", 0.0))
		if !jsonx.StrictEqual(color, "") {
			layout("shadow.color", "#"+jsCat(color))
			layout("shadow.inactive-color", "#"+jsCat(color))
		}
	}
	if o := get(look, "opacity"); truthy(o) {
		for _, focused := range []bool{true, false} {
			v := get(o, "inactive")
			if focused {
				v = get(o, "active")
			}
			nodes.Append(block("window-rule", Node("match", jsonx.Arr(), jsonx.Obj("is-focused", focused), nil),
				node("opacity", real(math.Max(0, math.Min(100, num(v)))/100))))
		}
	}
	return nodes
}

// NiriSurfaceBlurNodes is NiriConf.surfaceBlurNodes: the blur behind axiom's
// surfaces as niri's layer rules (whether each blurs the wallpaper alone).
func (t *Tables) NiriSurfaceBlurNodes(surfaces any) *jsonx.Array {
	out := jsonx.Arr()
	for _, rule := range t.SurfaceBlur(surfaces) {
		if !isTrue(rule.Value("on")) || !(isTrue(rule.Value("blur")) || isTrue(rule.Value("popups"))) || rule.Value("xray") == nil {
			continue
		}
		out.Append(block("layer-rule",
			Node("match", jsonx.Arr(), jsonx.Obj("namespace", "^axiom-("+strings.Join(stringList(rule.Value("namespaces")), "|")+")$"), nil),
			block("background-effect", node("xray", rule.Value("xray")))))
	}
	return out
}

// --- Input and options ---

// niriNode is a field's node path and argument as niri takes them, or
// false to leave it out. A boolean is written both ways (`prefer-no-csd
// false`, `animations { on }`), so axiom's off wins over the user's own
// on. A flag with no off form (`tap`) is written bare when on and left
// out when off (`flag`; `offFlag` the other way round).
func niriNode(spec, value any) (string, *jsonx.Array, bool) {
	key := str(get(spec, "key"))
	if skip, ok := prop(spec, "skip"); ok && jsonx.StrictEqual(value, skip) {
		return "", nil, false
	}
	switch str(get(spec, "value")) {
	case "flag":
		return key, jsonx.Arr(), truthy(value)
	case "offFlag":
		return key, jsonx.Arr(), !truthy(value)
	case "onOff":
		if truthy(value) {
			return key + ".on", jsonx.Arr(), true
		}
		return key + ".off", jsonx.Arr(), true
	case "not":
		return key, jsonx.Arr(!truthy(value)), true
	}
	scaled := value
	if s, ok := prop(spec, "scale"); ok {
		scaled = round(num(value)*num(s)*1000) / 1000
	}
	if str(get(spec, "value")) == "float" {
		return key, jsonx.Arr(real(scaled)), true
	}
	return key, jsonx.Arr(scaled), true
}

// NiriOptionNodes is NiriConf.optionNodes: a section's fields with a niri
// node as nodes (gated: each when its part is on, else once changed).
func NiriOptionNodes(sectionSchema, values any, gated bool) *jsonx.Array {
	nodes := jsonx.Arr()
	for _, f := range AnnotatedFields(sectionSchema, values, "niri", gated) {
		if key, args, ok := niriNode(f.Spec, f.Value); ok {
			KdlSetPath(nodes, key, args, nil)
		}
	}
	return nodes
}

// NiriInputNodes is NiriConf.inputNodes: the input as nodes, then the
// cursor theme.
func NiriInputNodes(input, inputSchema any) *jsonx.Array {
	nodes := NiriOptionNodes(inputSchema, or(get(input, "values"), jsonx.NewObject()), true)
	if c := get(input, "cursor"); truthy(c) {
		KdlSetPath(nodes, "cursor.xcursor-theme", jsonx.Arr(or(get(c, "xcursor"), get(c, "theme"))), nil)
		KdlSetPath(nodes, "cursor.xcursor-size", jsonx.Arr(round(num(get(c, "size")))), nil)
	}
	return nodes
}

// --- Outputs ---

// niri's IPC names for Wayland's transforms (NiriState.transforms)
var niriIPCTransforms = []string{"Normal", "_90", "_180", "_270", "Flipped", "Flipped90", "Flipped180", "Flipped270"}

var modePattern = regexp.MustCompile(`^(\d+)x(\d+)(?:@([\d.]+)(?:Hz)?)?$`)

// parseMode is MonitorLayout.parseMode: "WxH@R" as its numbers
func parseMode(mode any) (w, h, rate float64, ok bool) {
	m := modePattern.FindStringSubmatch(trim(str(or(mode, ""))))
	if m == nil {
		return 0, 0, 0, false
	}
	if m[3] != "" {
		rate = jsonx.ToNumber(m[3])
	}
	return jsonx.ToNumber(m[1]), jsonx.ToNumber(m[2]), rate, true
}

// connectorFor is NiriConf.connectorFor: the connector a rule's output
// names (a desc: looked up in details), or ""
func connectorFor(output, details any) string {
	value := str(or(output, ""))
	if !strings.HasPrefix(value, "desc:") {
		return value
	}
	for _, d := range items(details) {
		if sameDescription(str(or(get(d, "description"), "")), value[5:]) {
			return str(or(get(d, "name"), ""))
		}
	}
	return ""
}

// NiriOutputNodes is NiriConf.outputNodes: monitor rules as output nodes
// for a file.
func NiriOutputNodes(rules any) *jsonx.Array {
	out := jsonx.Arr()
	for _, rule := range items(rules) {
		name := str(or(get(rule, "output"), ""))
		var children []any
		if truthy(get(rule, "disabled")) {
			children = append(children, node("off"))
		} else {
			if w, h, rate, ok := parseMode(get(rule, "mode")); ok {
				text := fmtNum(w) + "x" + fmtNum(h)
				if rate > 0 {
					text += "@" + toFixed(rate, 3)
				}
				children = append(children, node("mode", text))
			}
			children = append(children, node("scale", real(or(get(rule, "scale"), 1.0))),
				node("transform", transformName(Transforms, get(rule, "transform"), "normal")),
				Node("position", jsonx.Arr(), jsonx.Obj("x", round(num(or(get(rule, "x"), 0.0))), "y", round(num(or(get(rule, "y"), 0.0)))), nil))
			if num(or(get(rule, "vrr"), 0.0)) > 0 {
				props := jsonx.NewObject()
				if get(rule, "vrr") == 2.0 {
					props.Set("on-demand", true)
				}
				children = append(children, Node("variable-refresh-rate", jsonx.Arr(), props, nil))
			}
		}
		if strings.HasPrefix(name, "desc:") {
			name = trim(name[5:])
		}
		out.Append(Node("output", jsonx.Arr(name), nil, jsonx.Arr(children...)))
	}
	return out
}

// NiriOutputRequests is NiriConf.outputRequests: monitor rules as niri's
// Output requests, disabled outputs last.
func NiriOutputRequests(rules, details any) *jsonx.Array {
	requests := jsonx.Arr()
	for _, rule := range disabledLast(rules) {
		output := connectorFor(get(rule, "output"), details)
		if output == "" {
			continue
		}
		send := func(action any) { requests.Append(jsonx.Obj("Output", jsonx.Obj("output", output, "action", action))) }
		if truthy(get(rule, "disabled")) {
			send("Off")
			continue
		}
		send("On")
		if w, h, rate, ok := parseMode(get(rule, "mode")); ok {
			var refresh any
			if rate > 0 {
				refresh = rate
			}
			send(jsonx.Obj("Mode", jsonx.Obj("mode", jsonx.Obj("Specific", jsonx.Obj("width", w, "height", h, "refresh", refresh)))))
		}
		send(jsonx.Obj("Scale", jsonx.Obj("scale", jsonx.Obj("Specific", num(or(get(rule, "scale"), 1.0))))))
		send(jsonx.Obj("Transform", jsonx.Obj("transform", transformName(niriIPCTransforms, get(rule, "transform"), "Normal"))))
		send(jsonx.Obj("Position", jsonx.Obj("position", jsonx.Obj("Specific",
			jsonx.Obj("x", round(num(or(get(rule, "x"), 0.0))), "y", round(num(or(get(rule, "y"), 0.0))))))))
		send(jsonx.Obj("Vrr", jsonx.Obj("vrr", jsonx.Obj("vrr", num(or(get(rule, "vrr"), 0.0)) > 0, "on_demand", get(rule, "vrr") == 2.0))))
	}
	return requests
}

var outputBlock = regexp.MustCompile(`(?ms)^output [^\n]*\{.*?^\}$`)

// NiriFileOutputNodes is NiriConf.fileOutputNodes: a file axiom wrote's
// output nodes, as raw text.
func NiriFileOutputNodes(text any) *jsonx.Array {
	out := jsonx.Arr()
	for _, raw := range outputBlock.FindAllString(str(or(text, "")), -1) {
		out.Append(jsonx.Obj("raw", raw))
	}
	return out
}

// --- The files ---

func nodeList(v any) []any { return items(v) }

// NiriModuleText is NiriConf.moduleText: the module axiom loads into niri.
// parts: { header, includeLines, binds, outputs, look, input, options }.
func NiriModuleText(parts any) string {
	var all []any
	if b := get(parts, "binds"); truthy(b) {
		all = append(all, b)
	}
	for _, k := range []string{"outputs", "options", "look", "input"} {
		all = append(all, nodeList(get(parts, k))...)
	}
	return jsCat(get(parts, "header")) + ` from its settings, and rewritten whenever they (or
// the theme) change: edit those, not this file.
//
// Include it at the end of your niri config, so its look wins:
//   ` + jsCat(get(parts, "includeLines")) + `
// Binds on keys your config binds aren't in it: yours win.

` + KdlSerialize(KdlMerged(jsonx.Arr(all...)), 0) + `
`
}

// NiriManagedText is NiriConf.managedText: the managed niri config.
func NiriManagedText(parts any) string {
	var session []any
	if env := items(get(parts, "env")); len(env) > 0 {
		var vars []any
		for _, e := range env {
			vars = append(vars, node(str(get(e, "name")), get(e, "value")))
		}
		session = append(session, block("environment", vars...))
	}
	start := get(parts, "start")
	session = append(session, node("spawn-sh-at-startup", get(start, "command")))
	isAgent := func(c string) bool { return truthy(call(get(parts, "isAgent"), c)) }
	for _, c := range autostartCommands(get(parts, "autostart"), start, isAgent) {
		session = append(session, node("spawn-sh-at-startup", c))
	}
	userDir := jsCat(get(parts, "userDir"))
	includes := niriIncludes(userDir, get(parts, "userFiles"))
	var after []any
	for _, k := range []string{"outputs", "options", "look", "input"} {
		after = append(after, nodeList(get(parts, k))...)
	}
	after = append(after, session...)
	binds := ""
	if b := get(parts, "binds"); truthy(b) {
		binds = KdlSerialize(jsonx.Arr(b), 0) + "\n\n"
	}
	files := "// (none yet)"
	if len(includes.Items) > 0 {
		files = KdlSerialize(includes, 0)
	}
	return jsCat(get(parts, "header")) + ` (niri mode: managed) from its settings, and
// rewritten whenever they (or the theme) change: edit those, not this file.
// Your own config goes in ` + userDir + `/ as .kdl files, included after
// axiom's binds in name order: your binds win over axiom's, axiom's look
// and settings over yours.

` + binds + `// Your files
` + files + `

` + KdlSerialize(KdlMerged(jsonx.Arr(after...)), 0) + `
`
}

func niriIncludes(userDir string, files any) *jsonx.Array {
	out := jsonx.Arr()
	for _, name := range items(files) {
		out.Append(Node("include", jsonx.Arr(userDir+"/"+jsCat(name)), jsonx.Obj("optional", true), nil))
	}
	return out
}

// NiriWrapperText is NiriConf.wrapperText: the detached mode's wrapper.
func NiriWrapperText(header, main, module any) string {
	return jsCat(header) + ` for its detached mode: niri runs this in place of your
// config while axiom does (load-config-file), and your own again after it.
// Your config is untouched.

` + KdlSerialize(jsonx.Arr(node("include", main), node("include", module)), 0) + `
`
}

// NiriReleasedText is NiriConf.releasedText: the niri config left behind on
// leaving managed when the takeover set nothing aside.
func NiriReleasedText(userDir, userFiles, startNodes, endNodes any) string {
	all := append(append(append([]any{}, items(startNodes)...), niriIncludes(jsCat(userDir), userFiles).Items...), items(endNodes)...)
	return `// Given back by axiom when it stopped managing niri: this file is yours now,
// and axiom won't write it again. It starts axiom and includes the files in
// ` + jsCat(userDir) + `/, as axiom's managed one did.
` + KdlSerialize(jsonx.Arr(all...), 0) + `
`
}

// NiriEmptyModuleText is NiriConf.emptyModuleText.
func NiriEmptyModuleText(header string) string {
	return header + `. axiom isn't in the "included" mode, so this file is
// empty; its include line can go.
`
}
