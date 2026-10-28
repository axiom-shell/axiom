package render

import (
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- SwayConf: sway's config and command text ---

var swayPlain = regexp.MustCompile(`^[A-Za-z0-9_.:+\-/@~=*]+$`)

// SwayQuote is SwayConf.quote: a string as one argument of a sway command,
// bare when it's plain word characters, else each run without a `"` in
// double quotes and each `"` in single ones.
func SwayQuote(text any) string {
	value := str(or(text, ""))
	if swayPlain.MatchString(value) {
		return value
	}
	parts := strings.Split(value, `"`)
	for i, p := range parts {
		if p != "" {
			parts[i] = `"` + p + `"`
		}
	}
	if out := strings.Join(parts, `'"'`); out != "" {
		return out
	}
	return `""`
}

var (
	swayFileEscapes = strings.NewReplacer(`\`, `\\`, "\n", `\n`, "\t", `\t`, "\r", `\r`)
	swaySplitting   = regexp.MustCompile(`[;,"']`)
)

// SwayBindCommand is SwayConf.bindCommand: a command as a bind's command,
// for a config file or (runtime) to send now.
func SwayBindCommand(command string, runtime bool) string {
	if !runtime {
		return swayFileEscapes.Replace(command)
	}
	if swaySplitting.MatchString(command) {
		return SwayQuote(command)
	}
	return command
}

// axiom's modifier names as sway's, and its mouse keys as sway's
var (
	swayModNames   = map[string]string{"SUPER": "Mod4", "CTRL": "Ctrl", "ALT": "Mod1", "SHIFT": "Shift", "CAPS": "Lock", "MOD2": "Mod2", "MOD3": "Mod3", "MOD5": "Mod5"}
	swayMouseNames = map[string]string{"mouse:272": "BTN_LEFT", "mouse:273": "BTN_RIGHT", "mouse:274": "BTN_MIDDLE", "mouse:275": "BTN_SIDE",
		"mouse:276": "BTN_EXTRA", "mouse_up": "button4", "mouse_down": "button5", "mouse_left": "button6", "mouse_right": "button7"}
	swayCode = regexp.MustCompile(`^code:(\d+)$`)
)

// SwayKey is a combo as sway binds it (SwayConf.key).
type SwayKey struct {
	Command string // bindsym or bindcode
	Spec    string // "Mod4+Shift+q"
	Mouse   bool
	Tap     bool
}

func (k *SwayKey) json() any {
	if k == nil {
		return nil
	}
	o := jsonx.Obj("command", k.Command, "spec", k.Spec, "mouse", k.Mouse)
	if k.Tap {
		o.Set("tap", true)
	}
	return o
}

// SwayKeyOf is SwayConf.key: a combo as sway binds it, or nil when a
// modifier or the key can't be written.
func SwayKeyOf(combo any) *SwayKey {
	c := SplitKey(combo)
	if c.Key == "" {
		return nil
	}
	if TapModifier(combo) != "" {
		return &SwayKey{Command: "bindsym", Spec: c.Key, Tap: true}
	}
	var mods []string
	for _, m := range c.Mods {
		name, ok := swayModNames[m]
		if !ok {
			return nil
		}
		mods = append(mods, name)
	}
	code := swayCode.FindStringSubmatch(c.Key)
	mouse, isMouse := swayMouseNames[strings.ToLower(c.Key)]
	if strings.HasPrefix(c.Key, "mouse:") && !isMouse {
		return nil
	}
	var name string
	switch {
	case code != nil:
		name = code[1]
	case isMouse:
		name = mouse
	case jsLen(c.Key) == 1:
		name = strings.ToLower(c.Key)
	default:
		name = c.Key
	}
	command := "bindsym"
	if code != nil {
		command = "bindcode"
	}
	return &SwayKey{Command: command, Spec: strings.Join(append(mods, name), "+"), Mouse: isMouse}
}

var swayExecQuoted = regexp.MustCompile(`[;,"'\\]`)

func swayExec(text string) string {
	if swayExecQuoted.MatchString(text) {
		return "exec " + SwayQuote(text)
	}
	return "exec " + text
}

var (
	swayDirections = []string{"left", "right", "up", "down"}
	swayOneWord    = regexp.MustCompile(`^[^\s;,"']+$`)
)

// SwayActionCommand is SwayConf.actionCommand: the sway command of a
// compositor action for argument, or "" when sway can't do it.
func (t *Tables) SwayActionCommand(action, argument string, ctx any) string {
	switch action {
	case "focusDir":
		if slices.Contains(swayDirections, argument) {
			return "focus " + argument
		}
		return ""
	case "moveWindowDir":
		if slices.Contains(swayDirections, argument) {
			return "move " + argument
		}
		return ""
	case "resizeWindow":
		x, y := twoNumbers(argument)
		if !isFinite(x) || !isFinite(y) {
			return ""
		}
		var parts []string
		way := func(v float64) string {
			if v > 0 {
				return "grow"
			}
			return "shrink"
		}
		if x != 0 {
			parts = append(parts, "resize "+way(x)+" width "+fmtNum(math.Abs(x))+" px")
		}
		if y != 0 {
			parts = append(parts, "resize "+way(y)+" height "+fmtNum(math.Abs(y))+" px")
		}
		// Comma: one command list on the same (focused) window
		return strings.Join(parts, ", ")
	case "closeWindow":
		return "kill"
	case "fullscreen":
		return "fullscreen toggle"
	case "toggleFloat":
		return "floating toggle"
	case "pin":
		return "sticky toggle"
	case "centerWindow":
		return "move position center"
	case "toggleSplit":
		return "layout toggle split"
	case "raw":
		return argument
	case "windowSwitcher", "windowSwitcherReverse":
		return "nop axiom switcher step " + jsCat(get(t.SwitcherSteps, action))
	case "toggleSpecial":
		if swayOneWord.MatchString(argument) {
			return "nop axiom special toggle " + argument
		}
		return ""
	case "moveToSpecial":
		if swayOneWord.MatchString(argument) {
			return "nop axiom special move " + argument
		}
		return ""
	case "restartShell":
		return swayExec(jsCat(get(ctx, "restartCommand")))
	case "exitSession":
		return "exit"
	case "terminal", "fileManager", "browser":
		return swayExec(jsCat(get(ctx, action)))
	}
	return ""
}

// SwayCommand is SwayConf.command: a configured bind's command, or "".
func (t *Tables) SwayCommand(bind, ctx any) string {
	argument := trim(str(or(get(bind, "argument"), "")))
	action := str(get(bind, "action"))
	if trim(str(or(get(bind, "key"), ""))) == "" || (t.NeedsArgument(get(bind, "action")) && argument == "") {
		return ""
	}
	if action == "raw" && str(or(get(bind, "compositor"), "hyprland")) != "sway" {
		return ""
	}
	switch {
	case truthy(get(t.CompositorActions, action)):
		return t.SwayActionCommand(action, argument, ctx)
	case action == "exec":
		return swayExec(argument)
	case truthy(get(t.IPCActions, action)):
		return swayExec(jsCat(get(ctx, "shellCommand")) + " ipc " + t.ipcCall(bind, argument, func(a string) string { return ShellWord(a) }))
	}
	return ""
}

// SwayBindLine is SwayConf.bindLine: a configured bind's bindsym (or
// bindcode) line, or "", for a file or (runtime) to send now.
func (t *Tables) SwayBindLine(bind, ctx any, runtime bool) string {
	cmd := t.SwayCommand(bind, ctx)
	k := SwayKeyOf(get(bind, "key"))
	if cmd == "" || k == nil {
		return ""
	}
	flags := append([]string{"--no-warn"}, swayConflictFlags(bind, k)...)
	if !truthy(get(bind, "repeating")) {
		flags = append(flags, "--no-repeat")
	}
	return k.Command + " " + strings.Join(flags, " ") + " " + k.Spec + " " + SwayBindCommand(cmd, runtime)
}

// The flags that are part of a bind's identity to sway
func swayConflictFlags(bind any, k *SwayKey) []string {
	var flags []string
	if k.Mouse {
		flags = append(flags, "--whole-window")
	}
	if truthy(get(bind, "locked")) {
		flags = append(flags, "--locked")
	}
	if truthy(get(bind, "release")) || k.Tap {
		flags = append(flags, "--release")
	}
	return flags
}

// SwayIsComplete is SwayConf.isComplete: whether sway can bind it.
func (t *Tables) SwayIsComplete(bind, ctx any) bool {
	if a := str(get(bind, "action")); a == "mouseDrag" || a == "mouseResize" {
		mod, _ := swayFloating(bind)
		return mod != ""
	}
	return t.SwayBindLine(bind, ctx, false) != ""
}

// swayFloating is a mouse drag or resize bind as sway's floating modifier
// (its modifier, and whether it's inverse), or "" when sway can't do it
func swayFloating(bind any) (string, bool) {
	c := SplitKey(or(get(bind, "key"), ""))
	mod := ""
	if len(c.Mods) == 1 {
		mod = swayModNames[c.Mods[0]]
	}
	if mod == "" || (c.Key != "mouse:272" && c.Key != "mouse:273") {
		return "", false
	}
	right := c.Key == "mouse:273"
	if str(get(bind, "action")) == "mouseDrag" {
		return mod, right
	}
	return mod, !right
}

// SwayFloatingModifier is SwayConf.floatingModifier.
func SwayFloatingModifier(binds any) string {
	var mouse []any
	for _, b := range items(binds) {
		a := str(get(b, "action"))
		if mod, _ := swayFloating(b); (a == "mouseDrag" || a == "mouseResize") && mod != "" {
			mouse = append(mouse, b)
		}
	}
	if len(mouse) == 0 {
		return ""
	}
	first := mouse[0]
	for _, b := range mouse {
		if str(get(b, "action")) == "mouseDrag" {
			first = b
			break
		}
	}
	mod, inverse := swayFloating(first)
	way := "normal"
	if inverse {
		way = "inverse"
	}
	return "floating_modifier " + mod + " " + way
}

func swayPress(bind any, k *SwayKey) string {
	parts := []string{k.Command}
	if truthy(get(bind, "locked")) {
		parts = append(parts, "--locked")
	}
	return strings.Join(append(parts, k.Spec), " ")
}

// swayKeptPresses are the release binds' presses bound to nothing, so sway
// keeps them (an input method's virtual keyboard would fire the release
// once per keyboard otherwise)
func (t *Tables) swayKeptPresses(binds, ctx any) []string {
	type entry struct {
		bind any
		k    *SwayKey
	}
	var complete []entry
	for _, b := range items(binds) {
		if t.SwayBindLine(b, ctx, false) == "" {
			continue
		}
		if k := SwayKeyOf(get(b, "key")); !k.Mouse {
			complete = append(complete, entry{b, k})
		}
	}
	released := func(e entry) bool { return isTrue(get(e.bind, "release")) || e.k.Tap }
	var own, out []string
	for _, e := range complete {
		if !released(e) {
			own = append(own, swayPress(e.bind, e.k))
		}
	}
	for _, e := range complete {
		if !released(e) {
			continue
		}
		if p := swayPress(e.bind, e.k); !slices.Contains(own, p) && !slices.Contains(out, p) {
			out = append(out, p)
		}
	}
	return out
}

var firstWord = regexp.MustCompile(`^(\S+)`)

// SwayBindLines is SwayConf.bindLines: every complete bind's line, then the
// kept presses', then the floating modifier.
func (t *Tables) SwayBindLines(binds, ctx any, runtime bool) []string {
	out := []string{}
	for _, b := range items(binds) {
		if l := t.SwayBindLine(b, ctx, runtime); l != "" {
			out = append(out, l)
		}
	}
	for _, p := range t.swayKeptPresses(binds, ctx) {
		out = append(out, firstWord.ReplaceAllString(p, "$1 --no-warn --no-repeat")+" nop")
	}
	if f := SwayFloatingModifier(binds); f != "" {
		out = append(out, f)
	}
	return out
}

// SwayBindEntries is SwayConf.bindEntries: axiom's complete binds as
// BindKeys' entries.
func (t *Tables) SwayBindEntries(binds, ctx any) *jsonx.Array {
	out := jsonx.Arr()
	for _, b := range items(binds) {
		if !t.SwayIsComplete(b, ctx) {
			continue
		}
		k := SwayKeyOf(get(b, "key"))
		if e := swayEntry(k.Command, k.Spec, t.DescriptionFor(b), ""); e != nil {
			out.Append(e)
		}
	}
	return out
}

// SwayUnbindLines is SwayConf.unbindLines: the commands taking binds' lines
// back out, the floating modifier put back to the user's own (entries are
// SwayConfigBinds') or sway's default.
func (t *Tables) SwayUnbindLines(binds, ctx, entries any) []string {
	out := []string{}
	for _, b := range items(binds) {
		k := SwayKeyOf(get(b, "key"))
		if k == nil || t.SwayBindLine(b, ctx, false) == "" {
			continue
		}
		out = append(out, strings.Join(append(append([]string{"un" + k.Command}, swayConflictFlags(b, k)...), k.Spec), " "))
	}
	for _, p := range t.swayKeptPresses(binds, ctx) {
		out = append(out, "un"+p)
	}
	if SwayFloatingModifier(binds) != "" {
		// The last of the user's lines, as sway takes it
		restore := "floating_modifier none"
		for _, e := range items(entries) {
			if d := str(get(e, "description")); strings.HasPrefix(d, "floating_modifier ") {
				restore = d
			}
		}
		out = append(out, restore)
	}
	return out
}

// --- The window look and the input ---

func hashColor(hex any) string { return "#" + strings.TrimPrefix(str(or(hex, "")), "#") }

// parseHexPrefix is parseInt(text, 16): the leading hex digits, NaN with none
func parseHexPrefix(text string) float64 {
	end := 0
	for end < len(text) && strings.IndexByte("0123456789abcdefABCDEF", text[end]) >= 0 {
		end++
	}
	if end == 0 {
		return math.NaN()
	}
	n, _ := strconv.ParseInt(text[:end], 16, 64)
	return float64(n)
}

// SwayTextOn is SwayConf.textOn: black or white, whichever reads on hex.
func SwayTextOn(hex any) string {
	v := strings.TrimPrefix(str(or(hex, "")), "#")
	part := func(i int) float64 {
		if i >= len(v) {
			return math.NaN()
		}
		return parseHexPrefix(v[i:min(i+2, len(v))]) / 255
	}
	if 0.2126*part(0)+0.7152*part(2)+0.0722*part(4) > 0.5 {
		return "#000000"
	}
	return "#ffffff"
}

// SwayLookLines is SwayConf.lookLines: the look's borders, shape and gaps
// as sway commands (live: for now, so what's open changes too).
func SwayLookLines(look any, live bool) []string {
	out := []string{}
	if b := get(look, "borders"); truthy(b) {
		on, off := hashColor(get(b, "active")), hashColor(get(b, "inactive"))
		out = append(out, "client.focused "+on+" "+on+" "+SwayTextOn(on)+" "+on+" "+on,
			"client.focused_inactive "+off+" "+off+" "+SwayTextOn(off)+" "+off+" "+off,
			"client.unfocused "+off+" "+off+" "+SwayTextOn(off)+" "+off+" "+off)
	}
	if s := get(look, "shape"); truthy(s) {
		width := fmtNum(math.Max(0, round(num(get(s, "width")))))
		out = append(out, "default_border pixel "+width, "default_floating_border pixel "+width)
		if live {
			out = append(out, "[all] border pixel "+width)
		}
	}
	if g := get(look, "gaps"); truthy(g) {
		inner, outer := jsCat(get(g, "inner")), jsCat(get(g, "outer"))
		out = append(out, "gaps inner "+inner, "gaps outer "+outer)
		if live {
			out = append(out, "gaps inner all set "+inner, "gaps outer all set "+outer)
		}
	}
	return out
}

// numberOr0 is Number(v) || 0
func numberOr0(v any) float64 {
	n := num(v)
	if math.IsNaN(n) {
		return 0
	}
	return n
}

func clampRound(v any, low, high float64) float64 {
	return math.Max(low, math.Min(high, round(numberOr0(v))))
}

func toggle(on any) string {
	if truthy(on) {
		return "enable"
	}
	return "disable"
}

// SwayFxLines is SwayConf.fxLines: SwayFX's part of the look and the blur
// behind axiom's surfaces, as commands to send now.
func (t *Tables) SwayFxLines(look, surfaces any) []string {
	out := []string{}
	if s := get(look, "shape"); truthy(s) {
		out = append(out, "corner_radius "+fmtNum(clampRound(get(s, "radius"), 0, 99)))
	}
	if b := get(look, "blur"); truthy(b) {
		out = append(out, "blur_radius "+fmtNum(clampRound(get(b, "size"), 0, 10)), "blur_passes "+fmtNum(clampRound(get(b, "passes"), 0, 10)),
			"blur_xray "+toggle(get(b, "xray")), "blur_noise "+fmtNum(round(num(get(b, "noise")))/1000),
			"blur_contrast "+fmtNum(round(num(get(b, "contrast")))/100))
	}
	if s := get(look, "shadow"); truthy(s) {
		soft := truthy(get(s, "soft")) && truthy(get(s, "rgb"))
		size := get(s, "size")
		var color any = get(s, "color")
		if soft {
			r, a := GaussianShadow(s)
			size = r
			color = jsCat(get(s, "rgb")) + AlphaHex(a)
		}
		out = append(out, "shadow_blur_radius "+fmtNum(clampRound(size, 0, 100)), "shadow_offset 0 0") // spread evenly, as axiom's own
		if !jsonx.StrictEqual(color, "") {
			out = append(out, "shadow_color #"+jsCat(color), "shadow_inactive_color #"+jsCat(color))
		}
	}
	if d := get(look, "dim"); truthy(d) {
		out = append(out, "default_dim_inactive "+fmtNum(clampRound(get(d, "strength"), 0, 100)/100))
	}
	return append(out, t.SwaySurfaceBlurLines(surfaces)...)
}

// SwaySurfaceBlurLines are the rules whose layers blur themselves: the part
// of SwayFxLines that follows whether axiom's surfaces blur.
func (t *Tables) SwaySurfaceBlurLines(surfaces any) []string {
	out := []string{}
	for _, rule := range t.SurfaceBlur(surfaces) {
		if !isTrue(rule.Value("blur")) {
			continue
		}
		for _, name := range stringList(rule.Value("namespaces")) {
			out = append(out, "layer_effects "+SwayQuote("axiom-"+name)+" "+
				SwayQuote("blur "+toggle(rule.Value("on"))+"; blur_xray "+toggle(rule.Value("xray"))+"; blur_ignore_transparent enable"))
		}
	}
	return out
}

// swayValue is a field's value as its sway command takes it, or false to
// leave it
func swayValue(spec, value any) (string, bool) {
	if skip, ok := prop(spec, "skip"); ok && jsonx.StrictEqual(value, skip) {
		return "", false
	}
	if m, ok := prop(spec, "map"); ok && m != nil {
		v := get(m, str(value))
		if v == nil {
			return "", false
		}
		return str(v), true
	}
	switch str(get(spec, "value")) {
	case "enabled":
		if truthy(value) {
			return "enabled", true
		}
		return "disabled", true
	case "yesNo":
		if truthy(value) {
			return "yes", true
		}
		return "no", true
	case "enableDisable":
		return toggle(value), true
	case "raw":
		return str(value), true
	}
	if s, ok := prop(spec, "scale"); ok {
		return fmtNum(round(num(value)*num(s)*1000) / 1000), true
	}
	return SwayQuote(value), true
}

// SwayInputLines is SwayConf.inputLines: the input as sway commands, then
// the cursor theme (live: leaving out what sway takes only from a file).
func SwayInputLines(input, inputSchema any, live bool) []string {
	out := []string{}
	for _, f := range AnnotatedFields(inputSchema, or(get(input, "values"), jsonx.NewObject()), "sway", true) {
		if live && truthy(get(f.Spec, "configOnly")) {
			continue
		}
		if v, ok := swayValue(f.Spec, f.Value); ok {
			out = append(out, jsReplace(str(get(f.Spec, "key")), "{}", v))
		}
	}
	if c := get(input, "cursor"); truthy(c) {
		out = append(out, SwayCursorLine(or(get(c, "xcursor"), get(c, "theme")), get(c, "size")))
	}
	return out
}

// SwayOptionLines is SwayConf.optionLines: a section's options, every field
// with a sway command.
func SwayOptionLines(sectionSchema, values any) []string {
	out := []string{}
	for _, f := range AnnotatedFields(sectionSchema, values, "sway", false) {
		if v, ok := swayValue(f.Spec, f.Value); ok {
			out = append(out, jsReplace(str(get(f.Spec, "key")), "{}", v))
		}
	}
	return out
}

// SwayCursorLine is SwayConf.cursorLine.
func SwayCursorLine(theme, size any) string {
	return "seat * xcursor_theme " + SwayQuote(theme) + " " + fmtNum(round(num(size)))
}

// SwayLoadedMode is the mode whose presence says axiom's file is loaded.
const SwayLoadedMode = "axiom_layer"

// SwayModuleText is SwayConf.moduleText: the included file. parts: {
// header, includeLines, binds, look, input, outputs }.
func SwayModuleText(parts any) string {
	section := func(title, name string) string {
		l := stringList(get(parts, name))
		if len(l) == 0 {
			return ""
		}
		return "\n# " + title + "\n" + strings.Join(l, "\n") + "\n"
	}
	return jsCat(get(parts, "header")) + ` from its settings, and rewritten whenever they (or
# the theme) change: edit those, not this file.
#
# Include it near the top of your sway config, so what follows overrides it:
#   ` + jsCat(get(parts, "includeLines")) + `
# Your own bindsym on one of axiom's keys, after it, wins (sway warns).

# Tells axiom this file is loaded
mode "` + SwayLoadedMode + `" bindsym --no-warn F35 mode default
` + section("Binds", "binds") + section("Window borders and gaps", "look") + section("Input", "input") + section("Monitors", "outputs")
}

// SwayManagedText is SwayConf.managedText: the managed sway config. opts: {
// header, userDir, options, env, start, autostart, isAgent }.
func SwayManagedText(module string, opts any) string {
	var kept []string
	for _, l := range strings.Split(module, "\n") {
		if !strings.HasPrefix(l, "#") {
			kept = append(kept, l)
		}
	}
	body := trim(strings.Join(kept, "\n"))
	var env []string
	for _, e := range items(get(opts, "env")) {
		env = append(env, jsCat(get(e, "name"))+"="+ShellWord(get(e, "value")))
	}
	exec := func(text string) string { return swayExec(SwayBindCommand(text, false)) }
	start := get(opts, "start")
	var lines []string
	if len(env) > 0 {
		lines = append(lines, exec("dbus-update-activation-environment --systemd "+strings.Join(env, " ")))
	}
	prefix := ""
	if len(env) > 0 {
		prefix = "env " + strings.Join(env, " ") + " "
	}
	lines = append(lines, exec(prefix+jsCat(get(start, "command"))))
	isAgent := func(c string) bool { return truthy(call(get(opts, "isAgent"), c)) }
	for _, c := range autostartCommands(get(opts, "autostart"), start, isAgent) {
		lines = append(lines, exec(c))
	}
	userDir := jsCat(get(opts, "userDir"))
	return jsCat(get(opts, "header")) + ` (sway mode: managed) from its settings, and
# rewritten whenever they (or the theme) change: edit those, not this file.
# Your own config goes in ` + userDir + `/, included after this in name
# order, so it overrides it.

` + body + `

# Windows, focus and sway's own options
` + strings.Join(stringList(get(opts, "options")), "\n") + `

# The session
` + strings.Join(lines, "\n") + `

include ` + SwayQuote(userDir+"/*") + `
`
}

// SwayReleasedText is SwayConf.releasedText.
func SwayReleasedText(userDir any, startLines string) string {
	return `# Given back by axiom when it stopped managing sway: this file is yours now,
# and axiom won't write it again. It starts axiom and includes
# ` + jsCat(userDir) + `/, as axiom's managed one did.
` + startLines + `

include ` + SwayQuote(jsCat(userDir)+"/*") + `
`
}

// SwayEmptyModuleText is SwayConf.emptyModuleText.
func SwayEmptyModuleText(header string) string {
	return header + `. axiom isn't in the "included" mode, so this file is
# empty; its include line can go.
`
}

// --- Outputs ---

// Transforms are Wayland's transforms 0-7 as sway's (and niri's config)
// name them.
var Transforms = []string{"normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"}

// transformName is transforms[rule.transform ?? 0] ?? "normal"
func transformName(names []string, v any, fallback string) string {
	n := num(or(v, 0.0))
	if n == math.Trunc(n) && n >= 0 && int(n) < len(names) {
		return names[int(n)]
	}
	return fallback
}

// SwayOutputName is SwayConf.outputName.
func SwayOutputName(output any) string {
	value := str(or(output, ""))
	if strings.HasPrefix(value, "desc:") {
		value = trim(value[5:])
	}
	return SwayQuote(value)
}

var rateSuffix = regexp.MustCompile(`@[\d.]+$`)

// SwayOutputCommand is SwayConf.outputCommand: a monitor rule as one
// `output` command.
func SwayOutputCommand(rule any) string {
	name := SwayOutputName(get(rule, "output"))
	if truthy(get(rule, "disabled")) {
		return "output " + name + " disable"
	}
	parts := []string{"output " + name + " enable"}
	if mode := str(or(get(rule, "mode"), "")); mode != "" && mode != "preferred" {
		if rateSuffix.MatchString(mode) {
			mode += "Hz"
		}
		parts = append(parts, "mode "+mode)
	}
	parts = append(parts, "pos "+fmtNum(round(num(or(get(rule, "x"), 0.0))))+" "+fmtNum(round(num(or(get(rule, "y"), 0.0)))),
		"scale "+jsCat(or(get(rule, "scale"), 1.0)), "transform "+transformName(Transforms, get(rule, "transform"), "normal"))
	sync := "off"
	if num(or(get(rule, "vrr"), 0.0)) > 0 {
		sync = "on"
	}
	depth := "8"
	if get(rule, "bitdepth") == 10.0 {
		depth = "10"
	}
	parts = append(parts, "adaptive_sync "+sync, "render_bit_depth "+depth)
	return strings.Join(parts, " ")
}

// disabledLast is rules with the disabled ones last
func disabledLast(rules any) []any {
	var on, off []any
	for _, r := range items(rules) {
		if truthy(get(r, "disabled")) {
			off = append(off, r)
		} else {
			on = append(on, r)
		}
	}
	return append(on, off...)
}

// SwayOutputLines is SwayConf.outputLines.
func SwayOutputLines(rules any) []string {
	out := []string{}
	for _, r := range disabledLast(rules) {
		out = append(out, SwayOutputCommand(r))
	}
	return out
}

// SwayOutputCommands is SwayConf.outputCommands.
func SwayOutputCommands(rules any) string { return strings.Join(SwayOutputLines(rules), "; ") }

// SwayFileOutputLines is SwayConf.fileOutputLines.
func SwayFileOutputLines(text any) []string {
	out := []string{}
	for _, l := range strings.Split(str(or(text, "")), "\n") {
		if strings.HasPrefix(l, "output ") {
			out = append(out, l)
		}
	}
	return out
}

// --- A user's sway config ---

var (
	swayModBits   = map[string]int{"shift": 1, "lock": 2, "control": 4, "ctrl": 4, "mod1": 8, "alt": 8, "mod2": 16, "mod3": 32, "mod4": 64, "super": 64, "mod5": 128}
	swayMouseKeys = map[string]string{"button1": "mouse:272", "button2": "mouse:274", "button3": "mouse:273", "button4": "mouse_up",
		"button5": "mouse_down", "button6": "mouse_left", "button7": "mouse_right", "btn_left": "mouse:272",
		"btn_right": "mouse:273", "btn_middle": "mouse:274", "btn_side": "mouse:275", "btn_extra": "mouse:276"}

	swayFloatingLine = regexp.MustCompile(`^floating_modifier\s+(\S+)(?:\s+(?:normal|inverse))?$`)
	swaySet          = regexp.MustCompile(`^set\s+(\$\S+)\s+(.*)$`)
	swayModeQuoted   = regexp.MustCompile(`^mode\s+(?:--pango_markup\s+)?"(.+?)"\s*\{$`)
	swayModeBare     = regexp.MustCompile(`^mode\s+(?:--pango_markup\s+)?(.+?)\s*\{$`)
	swayBindsBlock   = regexp.MustCompile(`^((?:bindsym|bindcode)(?:\s+--\S+)*)\s*\{$`)
	swayInlineMode   = regexp.MustCompile(`^mode\s+(?:--pango_markup\s+)?("([^"]+)"|(\S+))\s+((?:bindsym|bindcode)\s.*)$`)
	swayBindLine     = regexp.MustCompile(`^(bindsym|bindcode)\s+(.*)$`)
	swayContinuation = regexp.MustCompile(`\\\n`)
)

// SwayConfigBinds is SwayConf.configBinds: the binds in a sway config's
// text as BindKeys' entries ({ modmask, key, keycode, submap, description }).
func SwayConfigBinds(text any) *jsonx.Array {
	var varNames []string
	vars := map[string]string{}
	expand := func(line string) string {
		names := append([]string(nil), varNames...)
		slices.SortStableFunc(names, func(a, b string) int { return jsLen(b) - jsLen(a) })
		for _, n := range names {
			line = strings.ReplaceAll(line, n, vars[n])
		}
		return line
	}
	type block struct {
		mode, prefix string
		skip         bool
	}
	var blocks []block
	out := jsonx.Arr()
	for _, raw := range strings.Split(swayContinuation.ReplaceAllString(str(or(text, "")), " "), "\n") {
		line := trim(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "}" {
			if len(blocks) > 0 {
				blocks = blocks[:len(blocks)-1]
			}
			continue
		}
		if m := swaySet.FindStringSubmatch(line); m != nil {
			if _, ok := vars[m[1]]; !ok {
				varNames = append(varNames, m[1])
			}
			vars[m[1]] = trim(expand(m[2]))
			continue
		}
		line = expand(line)
		if strings.HasSuffix(line, "{") {
			b := block{}
			isMode := false
			if m := swayModeQuoted.FindStringSubmatch(line); m != nil {
				b.mode, isMode = m[1], true
			} else if m := swayModeBare.FindStringSubmatch(line); m != nil {
				b.mode, isMode = m[1], true
			}
			binds := swayBindsBlock.FindStringSubmatch(line)
			if binds != nil {
				b.prefix = binds[1] + " "
			}
			// Not a key's: a `bar { bindsym button4 … }` is a click on swaybar
			b.skip = !isMode && binds == nil
			blocks = append(blocks, b)
			continue
		}
		if slices.ContainsFunc(blocks, func(b block) bool { return b.skip }) {
			continue
		}
		if len(blocks) > 0 {
			line = blocks[len(blocks)-1].prefix + line
		}
		submap := ""
		target := line
		if m := swayInlineMode.FindStringSubmatch(line); m != nil {
			submap = m[2]
			if submap == "" {
				submap = m[3]
			}
			target = m[4]
		} else {
			for i := len(blocks) - 1; i >= 0; i-- {
				if blocks[i].mode != "" {
					submap = blocks[i].mode
					break
				}
			}
		}
		// The user's floating modifier holds its mouse buttons, so axiom's
		// drag and resize binds on them count as taken
		if m := swayFloatingLine.FindStringSubmatch(target); m != nil && submap == "" {
			for _, button := range []string{"button1", "button3"} {
				if e := swayEntry("bindsym", m[1]+"+"+button, target, ""); e != nil {
					out.Append(e)
				}
			}
			continue
		}
		bind := swayBindLine.FindStringSubmatch(target)
		if bind == nil {
			continue
		}
		words := spaceRun.Split(bind[2], -1)
		for len(words) > 0 && strings.HasPrefix(words[0], "--") {
			words = words[1:]
		}
		combo := ""
		if len(words) > 0 {
			combo, words = words[0], words[1:]
		}
		if e := swayEntry(bind[1], combo, strings.Join(words, " "), submap); e != nil {
			out.Append(e)
		}
	}
	return out
}

func swayEntry(kind, combo, command, submap string) *jsonx.Object {
	var parts []string
	for _, p := range strings.Split(combo, "+") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) == 0 {
		return nil
	}
	mask := 0
	for _, m := range parts[:len(parts)-1] {
		bit, ok := swayModBits[strings.ToLower(m)]
		if !ok {
			return nil
		}
		mask |= bit
	}
	last := parts[len(parts)-1]
	key, keycode := last, 0.0
	if kind == "bindcode" {
		key, keycode = "", jsonx.ToNumber(last)
	} else if m, ok := swayMouseKeys[strings.ToLower(last)]; ok {
		key = m
	}
	return jsonx.Obj("modmask", float64(mask), "key", key, "keycode", keycode, "submap", submap, "description", command)
}
