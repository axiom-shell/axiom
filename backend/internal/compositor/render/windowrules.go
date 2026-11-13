package render

import (
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// --- The user's window rules in each compositor's language. A pattern is
// quoted for the language it lands in: Lua and KDL strings escape it
// natively; sway reads a criterion's value after its own unescaping, so it
// gets `\x22` for a quote and `\x24` for a `$` (a variable), and a config
// file doubles every backslash on top. Every compositor lets the later rule
// win for the same property, so rules are written lowest priority first:
// the higher one in the list lands last. Which kinds and effects get
// written is decided once (compile) from the backend's capabilities; the
// printers only print. ---

// RuleSet is what the window rule renderers take.
type RuleSet struct {
	Rules    []windowrules.Rule // windowrules.Usable: enabled, valid, highest priority first
	Apps     windowrules.AppIDs // an `app` condition's app ids
	Supports map[string]bool    // the backend's supports (compositor.inputs)
}

// Unwritten is what a renderer left out of a rule's config: the daemon
// places Live kinds and Placed effects after a window opens.
type Unwritten struct {
	Rule    string   // the rule's id
	Live    []int    // kinds (indices into Rule.Kinds) only the daemon can match (Kind.Live)
	Skipped []int    // kinds this compositor can't match
	Placed  []string // effects (schema keys) the daemon places after open
	Dropped []string // effects (schema keys) the compositor can't do: never applied
}

// ruleEffects are the effect keys in the order they're written.
var ruleEffects = []string{"monitor", "workspace", "special", "float", "size", "center", "fullscreen",
	"maximize", "pin", "opacity", "noBlur", "noFocus", "noScreenShare", "tearing"}

// ruleGates are the capability each gated effect needs (read-only).
var ruleGates = map[string]string{"special": "namedSpecial", "maximize": "ruleMaximize", "pin": "pin", "opacity": "windowOpacity",
	"noBlur": "windowBlur", "noScreenShare": "ruleNoScreenShare", "tearing": "ruleTearing"}

// ruleKind is a kept kind: its patterns by field and its xwayland want.
type ruleKind struct {
	index    int
	pos, neg map[windowrules.Field]string
	xwayland *bool
}

type compiledRule struct {
	rule    windowrules.Rule
	kinds   []ruleKind
	effects []string
}

// rulePrinter is what differs between compositors in compile.
type rulePrinter struct {
	placed func(key string, w windowrules.WindowEffects) bool // the daemon places it
	cannot []string                                           // effects it has no way to write
}

func (c compiledRule) has(key string) bool { return slices.Contains(c.effects, key) }

// compile decides, for each rule, which kinds and effects are written, and
// reports the rest. Rules stay highest first; Unwritten lists only rules with
// something left out.
func compile(set RuleSet, p rulePrinter) ([]compiledRule, []Unwritten) {
	var out []compiledRule
	var left []Unwritten
	for _, r := range set.Rules {
		c := compiledRule{rule: r}
		u := Unwritten{Rule: r.ID}
		for i, k := range r.Kinds {
			if k.Live() {
				u.Live = append(u.Live, i)
				continue
			}
			l, err := windowrules.Lower(k, set.Apps)
			rk := ruleKind{index: i, pos: map[windowrules.Field]string{}, neg: map[windowrules.Field]string{}}
			ok := err == nil
			for _, t := range l.Tests {
				if t.Negated {
					rk.neg[t.Field] = t.Regex
				} else {
					rk.pos[t.Field] = t.Regex
				}
			}
			for _, f := range l.Flags {
				switch {
				case f.Field != windowrules.FieldXwayland:
				case !set.Supports["ruleXwayland"], rk.xwayland != nil && *rk.xwayland != f.Want:
					ok = false
				default:
					want := f.Want
					rk.xwayland = &want
				}
			}
			if ok {
				c.kinds = append(c.kinds, rk)
			} else {
				u.Skipped = append(u.Skipped, i)
			}
		}
		for _, key := range RuleEffects(r.Window) {
			switch gate := ruleGates[key]; {
			case gate != "" && !set.Supports[gate], slices.Contains(p.cannot, key):
				u.Dropped = append(u.Dropped, key)
			case p.placed(key, r.Window):
				u.Placed = append(u.Placed, key)
			default:
				c.effects = append(c.effects, key)
			}
		}
		if len(u.Live)+len(u.Skipped)+len(u.Placed)+len(u.Dropped) > 0 {
			left = append(left, u)
		}
		if len(c.kinds) > 0 && len(c.effects) > 0 {
			out = append(out, c)
		}
	}
	slices.Reverse(out)
	return out, left
}

// RuleEffects are the effects (schema keys) a rule sets, in the order they're written.
func RuleEffects(w windowrules.WindowEffects) []string {
	var keys []string
	for _, key := range ruleEffects {
		if ruleSet(w, key) {
			keys = append(keys, key)
		}
	}
	return keys
}

// ruleSet is whether the rule sets the effect (its value isn't "unset").
func ruleSet(w windowrules.WindowEffects, key string) bool {
	switch key {
	case "monitor":
		return w.Monitor != ""
	case "workspace":
		return w.Workspace != ""
	case "special":
		return w.Special.ID != ""
	case "float":
		return w.Float
	case "size":
		return w.Width != 0 && w.Height != 0
	case "center":
		return w.Center
	case "fullscreen":
		return w.Fullscreen
	case "maximize":
		return w.Maximize
	case "pin":
		return w.Pin
	case "opacity":
		return w.Opacity != 0
	case "noBlur":
		return w.NoBlur
	case "noFocus":
		return w.NoFocus
	case "noScreenShare":
		return w.NoScreenShare
	}
	return w.Tearing
}

func isDigits(s string) bool { return s != "" && strings.Trim(s, "0123456789") == "" }

func opacityText(pct int) string { return fmtNum(float64(pct) / 100) }

// --- Hyprland ---

// HyprRuleLines are the rules as Hyprland Lua `hl.window_rule` lines.
func HyprRuleLines(set RuleSet) ([]string, []Unwritten) {
	rules, left := compile(set, rulePrinter{placed: func(string, windowrules.WindowEffects) bool { return false }})
	var lines []string
	for _, c := range rules {
		w := c.rule.Window
		var fx []string
		for _, key := range c.effects {
			fx = append(fx, hyprEffect(key, w))
		}
		for _, k := range c.kinds {
			name := "axiom-rule-" + c.rule.ID + "-" + strconv.Itoa(k.index)
			lines = append(lines, "hl.window_rule({ name = "+LuaString(name)+", match = { "+hyprMatch(k)+" }, "+strings.Join(fx, ", ")+" })")
		}
	}
	return lines, left
}

func hyprMatch(k ruleKind) string {
	var m []string
	for _, f := range []struct {
		field        windowrules.Field
		key, initial string
	}{{windowrules.FieldAppID, "class", "initial_class"}, {windowrules.FieldTitle, "title", "initial_title"}} {
		pos, hasPos := k.pos[f.field]
		if hasPos {
			m = append(m, f.key+" = "+LuaString(pos))
		}
		if neg, ok := k.neg[f.field]; ok {
			key := f.key
			// a Lua table has one `class` key and RE2 has no lookahead, so the
			// negation goes on the initial value (equal at open)
			if hasPos {
				key = f.initial
			}
			m = append(m, key+" = "+LuaString("negative:"+neg))
		}
	}
	if k.xwayland != nil {
		m = append(m, "xwayland = "+boolText(*k.xwayland))
	}
	return strings.Join(m, ", ")
}

func hyprEffect(key string, w windowrules.WindowEffects) string {
	switch key {
	case "monitor":
		return "monitor = " + LuaString(w.Monitor)
	case "workspace":
		ws := "name:" + w.Workspace
		if isDigits(w.Workspace) {
			ws = w.Workspace
		}
		if !w.Follow {
			ws += " silent"
		}
		return "workspace = " + LuaString(ws)
	case "special":
		ws := "special:" + w.Special.ID
		if w.Special.Silent {
			ws += " silent"
		}
		return "workspace = " + LuaString(ws)
	case "size":
		return "size = " + LuaString(strconv.Itoa(w.Width)+" "+strconv.Itoa(w.Height))
	case "opacity":
		return "opacity = " + LuaString(opacityText(w.Opacity)+" override")
	}
	return map[string]string{"float": "float", "center": "center", "fullscreen": "fullscreen", "maximize": "maximize", "pin": "pin",
		"noBlur": "no_blur", "noFocus": "no_initial_focus", "noScreenShare": "no_screen_share", "tearing": "immediate"}[key] + " = true"
}

// --- niri ---

// NiriRuleNodes are the rules as niri `window-rule` nodes (KdlSerialize prints them).
func NiriRuleNodes(set RuleSet) (*jsonx.Array, []Unwritten) {
	rules, left := compile(set, rulePrinter{
		placed: func(key string, w windowrules.WindowEffects) bool { return key == "workspace" && isDigits(w.Workspace) },
		cannot: []string{"special", "pin", "tearing"},
	})
	out := jsonx.Arr()
	for _, c := range rules {
		fx := niriEffects(c)
		if len(fx) == 0 {
			continue
		}
		var plain []any
		var negated []ruleKind
		for _, k := range c.kinds {
			if len(k.neg) == 0 {
				plain = append(plain, niriMatch("match", k.pos))
			} else {
				negated = append(negated, k)
			}
		}
		if len(plain) > 0 {
			out.Append(block("window-rule", append(plain, fx...)...))
		}
		for _, k := range negated {
			var children []any
			if len(k.pos) > 0 {
				children = append(children, niriMatch("match", k.pos))
			}
			for _, f := range []windowrules.Field{windowrules.FieldAppID, windowrules.FieldTitle} {
				if re, ok := k.neg[f]; ok {
					children = append(children, niriMatch("exclude", map[windowrules.Field]string{f: re}))
				}
			}
			out.Append(block("window-rule", append(children, fx...)...))
		}
	}
	return out, left
}

func niriMatch(name string, tests map[windowrules.Field]string) *jsonx.Object {
	props := jsonx.NewObject()
	if re, ok := tests[windowrules.FieldAppID]; ok {
		props.Set("app-id", re)
	}
	if re, ok := tests[windowrules.FieldTitle]; ok {
		props.Set("title", re)
	}
	return Node(name, jsonx.Arr(), props, nil)
}

func niriEffects(c compiledRule) []any {
	w := c.rule.Window
	var fx []any
	for _, key := range c.effects {
		switch key {
		case "monitor":
			fx = append(fx, node("open-on-output", w.Monitor))
		case "workspace":
			fx = append(fx, node("open-on-workspace", w.Workspace))
		case "float":
			fx = append(fx, node("open-floating", true))
		case "size":
			fx = append(fx, block("default-column-width", node("fixed", float64(w.Width))),
				block("default-window-height", node("fixed", float64(w.Height))))
		case "fullscreen":
			fx = append(fx, node("open-fullscreen", true))
		case "maximize":
			fx = append(fx, node("open-maximized-to-edges", true))
		case "opacity":
			fx = append(fx, node("opacity", real(float64(w.Opacity)/100)))
		case "noBlur":
			fx = append(fx, block("background-effect", node("blur", false)))
		case "noFocus":
			fx = append(fx, node("open-focused", false))
		case "noScreenShare":
			fx = append(fx, node("block-out-from", "screencast"))
		}
	}
	return fx // center writes nothing: niri opens a floating window at the center
}

// --- sway ---

// SwayRuleLines are the rules as sway `for_window` and `no_focus` lines, for
// a config file or (runtime) to send over IPC.
func SwayRuleLines(set RuleSet, runtime bool) ([]string, []Unwritten) {
	rules, left := compile(set, rulePrinter{
		placed: func(key string, _ windowrules.WindowEffects) bool { return key == "special" },
		cannot: []string{"maximize", "noScreenShare"},
	})
	var lines []string
	emit := func(line string) {
		if !runtime {
			line = swayFileEscapes.Replace(line)
		}
		lines = append(lines, line)
	}
	// over IPC an unquoted chain is split at its commas
	chain := func(cmds []string) string {
		if runtime {
			return SwayBindCommand(strings.Join(cmds, ", "), true)
		}
		return strings.Join(cmds, ", ")
	}
	for _, c := range rules {
		cmds := swayCommands(c)
		for _, k := range c.kinds {
			for _, list := range swayLists(k) {
				if len(cmds) > 0 {
					emit("for_window " + list + " " + chain(cmds))
				}
				if c.has("noFocus") {
					emit("no_focus " + list)
				}
			}
		}
	}
	return lines, left
}

// swayLists are a kind's criteria lists: sway's app_id matches only Wayland
// windows and class only X11 ones, so an app id test is written on both
// unless an xwayland condition picks one.
func swayLists(k ruleKind) []string {
	value := func(f windowrules.Field) string {
		pos, neg := k.pos[f], k.neg[f]
		switch {
		case pos != "" && neg != "":
			return `\A(?=` + pos + `)(?!` + neg + `)`
		case neg != "":
			return `\A(?!` + neg + `)`
		}
		return pos
	}
	_, hasApp := k.pos[windowrules.FieldAppID]
	_, hasAppNeg := k.neg[windowrules.FieldAppID]
	hasApp = hasApp || hasAppNeg
	build := func(appKey, shell string) string {
		var cr []string
		if hasApp {
			cr = append(cr, appKey+`="`+SwayCriterion(value(windowrules.FieldAppID))+`"`)
		}
		if _, ok := k.pos[windowrules.FieldTitle]; ok || k.neg[windowrules.FieldTitle] != "" {
			cr = append(cr, `title="`+SwayCriterion(value(windowrules.FieldTitle))+`"`)
		}
		if shell != "" {
			cr = append(cr, `shell="`+shell+`"`)
		}
		return "[" + strings.Join(cr, " ") + "]"
	}
	switch {
	case k.xwayland != nil && *k.xwayland:
		return []string{build("class", "xwayland")}
	case k.xwayland != nil:
		return []string{build("app_id", "xdg_shell")}
	case hasApp:
		return []string{build("app_id", ""), build("class", "")}
	}
	return []string{build("", "")}
}

// swayCommands are the commands of a rule's effects; sticky and center come
// last: on a tiled window they fail, and sway goes on with the rest.
func swayCommands(c compiledRule) []string {
	w := c.rule.Window
	var cmds []string
	add := func(key string, cmd ...string) {
		if c.has(key) {
			cmds = append(cmds, cmd...)
		}
	}
	add("monitor", "move container to output "+SwayQuote(w.Monitor))
	if c.has("workspace") {
		ws, move := "workspace "+SwayQuote(w.Workspace), "move container to workspace "+SwayQuote(w.Workspace)
		if isDigits(w.Workspace) {
			ws, move = "workspace number "+w.Workspace, "move container to workspace number "+w.Workspace
		}
		cmds = append(cmds, move)
		if w.Follow {
			cmds = append(cmds, ws)
		}
	}
	add("float", "floating enable")
	add("size", "resize set "+strconv.Itoa(w.Width)+" px "+strconv.Itoa(w.Height)+" px")
	add("fullscreen", "fullscreen enable")
	add("opacity", "opacity "+opacityText(w.Opacity))
	add("noBlur", "blur disable")
	add("tearing", "allow_tearing yes")
	add("pin", "sticky enable")
	add("center", "move position center")
	return cmds
}

// SwayCriterion is a pattern as a sway criterion's value between double
// quotes, sent over IPC (a config file doubles its backslashes too).
func SwayCriterion(re string) string {
	var b strings.Builder
	for i := 0; i < len(re); i++ {
		switch {
		case re[i] == '\\' && i+1 < len(re):
			if re[i+1] == '$' {
				b.WriteString(`\x24`)
			} else {
				b.WriteString(re[i : i+2])
			}
			i++
		case re[i] == '"':
			b.WriteString(`\x22`)
		default:
			b.WriteByte(re[i])
		}
	}
	return b.String()
}
