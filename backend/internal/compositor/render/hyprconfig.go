package render

import (
	"math"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- HyprConfigLua: the Lua axiom's Hyprland layer is made of ---

// ShellWord is a single-quoted shell word.
func ShellWord(text any) string {
	return "'" + strings.ReplaceAll(jsCat(text), "'", `'\''`) + "'"
}

// indent is lines joined, each but the empty ones after prefix (an element
// holding several lines is prefixed once, as the JS does)
func indent(list []string, prefix string) string {
	out := make([]string, len(list))
	for i, l := range list {
		if l != "" {
			out[i] = prefix + l
		}
	}
	return strings.Join(out, "\n")
}

const exitLua = "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"

func towardsStart(argument string) bool { return argument == "left" || argument == "up" }

// DispatcherLua is HyprConfigLua.dispatcherLua: the dispatcher Lua of a
// compositor action for argument, or "" when the argument doesn't fit it.
// ctx: { shellCommand, restartCommand, terminal, fileManager, browser }.
func (t *Tables) DispatcherLua(action, argument string, ctx any) string {
	switch action {
	case "focusDir":
		return "hl.dsp.focus({ direction = " + LuaString(argument) + " })"
	case "moveWindowDir":
		return "hl.dsp.window.move({ direction = " + LuaString(argument) + " })"
	case "resizeWindow":
		x, y := twoNumbers(argument)
		if !isFinite(x) || !isFinite(y) {
			return ""
		}
		return "hl.dsp.window.resize({ x = " + fmtNum(x) + ", y = " + fmtNum(y) + ", relative = true })"
	case "closeWindow":
		return "hl.dsp.window.close()"
	case "fullscreen":
		return "hl.dsp.window.fullscreen()"
	case "toggleFloat":
		return `hl.dsp.window.float({ action = "toggle" })`
	case "pin":
		return "hl.dsp.window.pin()"
	case "centerWindow":
		return "hl.dsp.window.center()"
	case "toggleGroup":
		return "hl.dsp.group.toggle()"
	case "pseudo":
		return "hl.dsp.window.pseudo()"
	case "toggleSplit":
		return `hl.dsp.layout("togglesplit")`
	// Strips (the scrolling layout)
	case "stripSwapColumn":
		side := "r"
		if towardsStart(argument) {
			side = "l"
		}
		return "hl.dsp.layout(" + LuaString("swapcol "+side) + ")"
	case "stripWider":
		return `hl.dsp.layout("colresize +conf")`
	case "stripNarrower":
		return `hl.dsp.layout("colresize -conf")`
	case "stripFit":
		return `hl.dsp.layout("fit visible")`
	case "stripConsume":
		side := "next"
		if towardsStart(argument) {
			side = "prev"
		}
		return "hl.dsp.layout(" + LuaString("consume_or_expel "+side) + ")"
	case "stripCenter":
		return `hl.dsp.layout("center")`
	// Any dispatcher, as Lua, compiled when the bind is made so a mistake
	// only leaves that bind doing nothing
	case "raw":
		return "(function() local ok, d = pcall(load(" + LuaString("return "+argument) + ") or error) if ok and d then return d end return hl.dsp.no_op() end)()"
	case "windowSwitcher", "windowSwitcherReverse":
		return SwitcherBindLua(get(t.SwitcherSteps, action))
	case "mouseDrag":
		return "hl.dsp.window.drag()"
	case "mouseResize":
		return "hl.dsp.window.resize()"
	case "toggleSpecial":
		return "hl.dsp.workspace.toggle_special(" + LuaString(argument) + ")"
	case "moveToSpecial":
		return "hl.dsp.window.move({ workspace = " + LuaString("special:"+argument) + " })"
	// Run by Hyprland, not over IPC, so it works when the shell is stuck
	case "restartShell":
		return "hl.dsp.exec_cmd(" + LuaString(get(ctx, "restartCommand")) + ")"
	case "exitSession":
		return "hl.dsp.exec_cmd(" + LuaString(exitLua) + ")"
	case "terminal", "fileManager", "browser":
		return "hl.dsp.exec_cmd(" + LuaString(get(ctx, action)) + ")"
	}
	return ""
}

// ipcCall is a bind's IPC call: its action's call with {call} and {0}
// (the argument as wordFor writes it) put in
func (t *Tables) ipcCall(bind any, argument string, wordFor func(string) string) string {
	ipc := str(at(get(t.IPCActions, str(get(bind, "action"))), 0))
	ipc = jsReplace(ipc, "{call}", t.CallFunction(bind))
	return jsReplace(ipc, "{0}", wordFor(argument))
}

// BindLua is HyprConfigLua.bindLua: a configured bind's hl.bind() line, or
// "" when it's incomplete.
func (t *Tables) BindLua(bind, ctx any) string {
	argument := trim(str(or(get(bind, "argument"), "")))
	action := str(get(bind, "action"))
	if trim(str(or(get(bind, "key"), ""))) == "" || (t.NeedsArgument(get(bind, "action")) && argument == "") ||
		(action == "raw" && str(or(get(bind, "compositor"), "hyprland")) != "hyprland") {
		return ""
	}
	dispatcher := ""
	switch {
	case truthy(get(t.CompositorActions, action)):
		dispatcher = t.DispatcherLua(action, argument, ctx)
	case action == "exec":
		dispatcher = "hl.dsp.exec_cmd(" + LuaString(argument) + ")"
	case truthy(get(t.IPCActions, action)):
		ipc := t.ipcCall(bind, argument, func(a string) string { return ShellWord(a) })
		dispatcher = "hl.dsp.exec_cmd(" + LuaString(jsCat(get(ctx, "shellCommand"))+" ipc "+ipc) + ")"
	}
	if dispatcher == "" {
		return ""
	}
	options := []string{"description = " + LuaString(t.DescriptionFor(bind))}
	tap := TapModifier(get(bind, "key")) != ""
	for _, flag := range t.FlagNames {
		if truthy(get(bind, flag)) || (tap && flag == "release") {
			options = append(options, flag+" = true")
		}
	}
	return "hl.bind(" + LuaString(BindKey(get(bind, "key"))) + ", " + dispatcher + ", { " + strings.Join(options, ", ") + " })"
}

// BindKey is HyprConfigLua.bindKey: a tap is written with its modifier
// ("Super_L" → "SUPER + Super_L").
func BindKey(key any) string {
	if tap := TapModifier(key); tap != "" {
		return JoinKey([]string{tap}, SplitKey(key).Key)
	}
	return trim(str(or(key, "")))
}

// switcherEntries are the switcher binds among binds as HyprLua.switcherLua's
// entries
func (t *Tables) switcherEntries(binds, ctx any, complete func(bind, ctx any) bool) *jsonx.Array {
	out := jsonx.Arr()
	for _, b := range items(binds) {
		step, ok := t.SwitcherSteps.Get(str(get(b, "action")))
		if !ok || !complete(b, ctx) {
			continue
		}
		c := SplitKey(get(b, "key"))
		out.Append(jsonx.Obj("mods", strs(c.Mods), "key", c.Key, "step", step))
	}
	return out
}

// BindLines is HyprConfigLua.bindLines: every complete bind's line, then
// the switcher's submap.
func (t *Tables) BindLines(binds, ctx any) []string {
	out := []string{}
	for _, b := range items(binds) {
		if line := t.BindLua(b, ctx); line != "" {
			out = append(out, line)
		}
	}
	entries := t.switcherEntries(binds, ctx, func(b, c any) bool { return t.BindLua(b, c) != "" })
	return append(out, SwitcherLua(entries)...)
}

// RequiredLua is HyprConfigLua.requiredLua.
func RequiredLua(withAnimation bool) []string {
	out := []string{"hl.config({ misc = { allow_session_lock_restore = true } })",
		`hl.window_rule({ name = "axiom-suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })`}
	if withAnimation {
		out = append(out, `hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slide" })`)
	}
	return out
}

// ModuleLua is HyprConfigLua.moduleLua: the included module. parts: {
// header, includeLines, requiredSettings, and the Lua lines of binds, look,
// input, blur, layers, monitors, strips }.
func ModuleLua(parts any) string {
	setup := []string{}
	if truthy(get(parts, "requiredSettings")) {
		setup = append(setup, "M.required()")
	}
	setup = append(setup, "M.binds()", "M.look()", "M.input()", "M.blur()", "M.layers()", "M.monitors()", "M.strips()")
	part := func(name string) string { return indent(stringList(get(parts, name)), "  ") }
	return jsCat(get(parts, "header")) + ` from its Hyprland settings, and rewritten whenever they
-- (or the theme) change: edit those, not this file.
--
-- Load it near the top of hyprland.lua, so what follows overrides it:
--   ` + replaceFirst(str(get(parts, "includeLines")), "\n", "\n--   ") + `
-- setup() applies everything enabled in axiom's settings; call the parts
-- instead to pick. hl.unbind("KEY") after it frees one of axiom's keys.
local M = {}

-- Session lock restore, ignoring apps' maximize requests and a workspaces
-- animation (axiom's grid slides)
function M.required()
` + indent(RequiredLua(true), "  ") + `
end

function M.binds()
` + part("binds") + `
end

-- Window borders in the axiom theme, its shape, gaps, Hyprland's blur and
-- window opacity, as enabled. axiom applies them again after every reload,
-- so they win over what follows while they're on.
function M.look()
` + part("look") + `
end

-- The keyboard, mouse and touchpad, as enabled; applied again after every
-- reload like the look
function M.input()
` + part("input") + `
end

-- Blur behind axiom's surfaces while they're translucent (on or off, so
-- turning it off takes it back), at Hyprland's blur
function M.blur()
` + part("blur") + `
end

-- Stacking order of axiom's surfaces (bars, border, edge menus, backdrops)
function M.layers()
` + part("layers") + `
end

-- Monitor profiles from the Monitors page: the one for what's connected,
-- again whenever a monitor comes or goes
function M.monitors()
` + part("monitors") + `
end

-- Strips (the scrolling layout) on the monitors Workspaces lists
function M.strips()
` + part("strips") + `
end

function M.setup()
` + indent(setup, "  ") + `
end

-- Lets axiom see that this file is loaded
AXIOM_INCLUDED = true

return M
`
}

// EmptyModuleLua is HyprConfigLua.emptyModuleLua: the included module once
// axiom isn't in that mode, every part a no-op.
func EmptyModuleLua(header string) string {
	return header + `: Hyprland mode isn't "included", so this module does
-- nothing. Switching back to included writes it again.
return setmetatable({}, { __index = function() return function() end end })
`
}

var (
	agentPath   = regexp.MustCompile(`^.*/`)
	agentQuotes = regexp.MustCompile(`^["']|["']$`)
	spaceRun    = regexp.MustCompile(`\s+`)
)

// IsAgentCommand is whether an autostart command starts a known polkit
// agent (PolkitAgents.qml's agents): runs one by name or path, or starts
// its unit ("systemctl --user start hyprpolkitagent").
func (t *Tables) IsAgentCommand(command any) bool {
	for _, word := range spaceRun.Split(trim(str(command)), -1) {
		name := agentQuotes.ReplaceAllString(strings.TrimSuffix(agentPath.ReplaceAllString(word, ""), ".service"), "")
		for _, a := range t.PolkitAgents {
			if str(a.Value("process")) == name || str(a.Value("unit")) == name+".service" {
				return true
			}
		}
	}
	return false
}

// autostartCommands are a session's autostart commands that start (enabled,
// not empty; a plain hypridle left out while axiom runs its own idle, a
// polkit agent while it's the agent), trimmed
func autostartCommands(autostart, start any, isAgent func(string) bool) []string {
	var out []string
	for _, e := range items(autostart) {
		command := trim(str(get(e, "command")))
		if !truthy(get(e, "enabled")) || command == "" ||
			(truthy(get(start, "idle")) && command == "hypridle") ||
			(truthy(get(start, "polkit")) && isAgent(str(get(e, "command")))) {
			continue
		}
		out = append(out, command)
	}
	return out
}

// StartLua is HyprConfigLua.startLua: what the managed file runs once
// Hyprland has started: the cursor, axiom, then the autostart commands.
func (t *Tables) StartLua(session, cursor, start any) []string {
	var out []string
	if truthy(cursor) {
		out = append(out, "hl.exec_cmd("+LuaString("hyprctl setcursor "+ShellWord(get(cursor, "theme"))+" "+jsCat(get(cursor, "size")))+")")
	}
	out = append(out, "hl.exec_cmd("+LuaString(get(start, "command"))+")")
	for _, c := range autostartCommands(get(session, "autostart"), start, func(c string) bool { return t.IsAgentCommand(c) }) {
		out = append(out, "hl.exec_cmd("+LuaString(c)+")")
	}
	return out
}

// EnvLua is HyprConfigLua.envLua: the session's environment as hl.env calls.
func EnvLua(env any) string {
	var b strings.Builder
	for _, e := range items(env) {
		b.WriteString("hl.env(" + LuaString(get(e, "name")) + ", " + LuaString(get(e, "value")) + ")\n")
	}
	return b.String()
}

// Animation presets: curves { name: [x1, y1, x2, y2] } and leaves [leaf,
// speed (Hyprland's unit: 100 ms), curve, style]; JSON so the curves keep
// their order
const animationPresetsJSON = `{
  "snappy": {
    "curves": {"axiomSnappy": [0.2, 0, 0, 1]},
    "leaves": [["windows", 2, "axiomSnappy", "popin 90%"], ["layers", 2, "axiomSnappy", "fade"], ["fade", 2, "axiomSnappy", ""], ["border", 1, "axiomSnappy", ""], ["workspaces", 2.5, "axiomSnappy", "slide"], ["specialWorkspace", 2.5, "axiomSnappy", "slidevert"]]
  },
  "bouncy": {
    "curves": {"axiomSnappy": [0.2, 0, 0, 1], "axiomOvershoot": [0.34, 1.56, 0.64, 1]},
    "leaves": [["windows", 4, "axiomOvershoot", "popin 60%"], ["windowsOut", 3, "axiomSnappy", "popin 80%"], ["layers", 3, "axiomOvershoot", "fade"], ["fade", 3, "axiomSnappy", ""], ["border", 2, "axiomSnappy", ""], ["workspaces", 4, "axiomOvershoot", "slide"], ["specialWorkspace", 4, "axiomOvershoot", "slidevert"]]
  },
  "lightning": {
    "curves": {"lightningSlow": [0, 0.85, 0.3, 1], "lightningOut": [0.3, -0.3, 0, 1], "lightningWind": [0.05, 0.9, 0.1, 1], "lightningOvershot": [0.7, 0.6, 0.1, 1.1], "lightningBounce": [1.1, 1.6, 0.1, 0.85], "lightningDecel": [0.05, 0.7, 0.1, 1]},
    "leaves": [["windowsIn", 0.5, "lightningSlow", "popin"], ["windowsOut", 0.5, "lightningOut", "popin"], ["windowsMove", 0.7, "lightningWind", "slide"], ["fade", 2, "lightningOvershot", ""], ["workspaces", 2.5, "lightningWind", "fade"], ["windows", 2, "lightningBounce", "popin"], ["specialWorkspace", 0.8, "lightningDecel", "slidevert"]]
  }
}`

func animationPresets() *jsonx.Object {
	v, err := jsonx.Unmarshal([]byte(animationPresetsJSON))
	if err != nil {
		panic(err)
	}
	return v.(*jsonx.Object)
}

// AnimationsOff is HyprConfigLua.animationsOff: whether the managed settings
// m turn Hyprland's animations off altogether.
func AnimationsOff(m, motion any) bool {
	preset := str(get(m, "animationPreset"))
	return !truthy(get(m, "animations")) || preset == "instant" || (preset == "axiom" && !truthy(get(motion, "enabled")))
}

// AnimationSet is HyprConfigLua.animationSet: the preset (or custom list) of
// m as { curves, leaves }, or nil for Hyprland's own animations.
func AnimationSet(m, motion any) *jsonx.Object {
	set := animationSet(m, motion)
	if set == nil {
		return nil
	}
	leaves := set.Value("leaves").(*jsonx.Array)
	var global any
	hasWorkspaces := false
	for _, leaf := range leaves.Items {
		switch str(at(leaf, 0)) {
		case "global":
			if global == nil {
				global = leaf
			}
		case "workspaces":
			hasWorkspaces = true
		}
	}
	if global != nil && !hasWorkspaces {
		leaves.Append(jsonx.Arr("workspaces", at(global, 1), at(global, 2), "slide"))
	}
	return set
}

func animationSet(m, motion any) *jsonx.Object {
	switch str(get(m, "animationPreset")) {
	case "axiom":
		// Look & Feel → Motion: the shell's durations, in Hyprland's unit
		speed := func(ms any) float64 { return math.Max(0.1, num(ms)/100) }
		return jsonx.Obj("curves", jsonx.Obj("axiomMotion", jsonx.Arr(0.05, 0.7, 0.1, 1.0)), "leaves", jsonx.Arr(
			jsonx.Arr("windows", speed(get(motion, "slow")), "axiomMotion", "popin 80%"),
			jsonx.Arr("layers", speed(get(motion, "normal")), "axiomMotion", "fade"),
			jsonx.Arr("fade", speed(get(motion, "normal")), "axiomMotion", ""),
			jsonx.Arr("border", speed(get(motion, "fast")), "axiomMotion", ""),
			jsonx.Arr("workspaces", speed(get(motion, "slow")), "axiomMotion", "slide"),
			jsonx.Arr("specialWorkspace", speed(get(motion, "slow")), "axiomMotion", "slidevert")))
	case "custom":
		curves := jsonx.NewObject()
		for _, c := range items(get(m, "curves")) {
			parts := strings.Split(str(get(c, "points")), ",")
			points := jsonx.Arr()
			ok := len(parts) == 4
			for _, p := range parts {
				n := jsonx.ToNumber(p)
				ok = ok && isFinite(n)
				points.Append(n)
			}
			if name := trim(str(get(c, "name"))); name != "" && ok {
				curves.Set(name, points)
			}
		}
		leaves := jsonx.Arr()
		for _, a := range items(get(m, "customAnimations")) {
			speed := 0.0
			if truthy(get(a, "enabled")) {
				speed = num(get(a, "duration")) / 100
			}
			curve := trim(str(get(a, "curve")))
			if curve == "" {
				curve = "default"
			}
			leaves.Append(jsonx.Arr(get(a, "leaf"), speed, curve, trim(str(get(a, "style")))))
		}
		return jsonx.Obj("curves", curves, "leaves", leaves)
	}
	preset, ok := animationPresets().Value(str(get(m, "animationPreset"))).(*jsonx.Object)
	if !ok {
		return nil
	}
	return jsonx.Obj("curves", preset.Value("curves"), "leaves", jsonx.Arr(items(preset.Value("leaves"))...))
}

// AnimationsLua is HyprConfigLua.animationsLua: the curves and animations
// of m, or "" for Hyprland's own.
func AnimationsLua(m, motion any) string {
	if AnimationsOff(m, motion) {
		return ""
	}
	set := AnimationSet(m, motion)
	if set == nil {
		return ""
	}
	var out []string
	curves := set.Value("curves")
	for _, name := range keys(curves) {
		p := make([]string, 4)
		for i := range p {
			p[i] = LuaValue(at(get(curves, name), i))
		}
		out = append(out, "hl.curve("+LuaString(name)+`, { type = "bezier", points = { { `+p[0]+", "+p[1]+" }, { "+p[2]+", "+p[3]+" } } })")
	}
	for _, leaf := range items(set.Value("leaves")) {
		speed := num(at(leaf, 1))
		parts := []string{"leaf = " + LuaString(at(leaf, 0)), "enabled = " + boolText(speed > 0)}
		if speed > 0 {
			parts = append(parts, "speed = "+LuaValue(at(leaf, 1)), "bezier = "+LuaString(at(leaf, 2)))
		}
		if speed > 0 && !jsonx.StrictEqual(at(leaf, 3), "") {
			parts = append(parts, "style = "+LuaString(at(leaf, 3)))
		}
		out = append(out, "hl.animation({ "+strings.Join(parts, ", ")+" })")
	}
	return "\n" + strings.Join(out, "\n") + "\n"
}

// ConfigLua is HyprConfigLua.configLua: the managed settings m as one
// hl.config(). opts: { schema, resolveHex, motion }.
func ConfigLua(m, opts any) string {
	overrides := jsonx.NewObject()
	if AnimationsOff(m, get(opts, "motion")) {
		overrides.Set("animations.enabled", false)
	}
	return "hl.config(" + Serialize(ConfigTable(get(opts, "schema"), m, get(opts, "resolveHex"), overrides), "") + ")"
}

// UserFilesLua is HyprConfigLua.userFilesLua: loads user/*.lua in name
// order.
func UserFilesLua(userDir any) string {
	return `-- Your files, through require (as user.<name>) so Hyprland reloads when
-- one changes. Shared modules go in user/lib/ (require("user.lib.x")),
-- which isn't loaded here. A failing file doesn't stop the rest; the
-- errors are raised together at the end (hyprctl configerrors).
local errors = {}
local files = io.popen("cd " .. ` + LuaString(ShellWord(userDir)) + ` .. " 2>/dev/null && ls -1 *.lua 2>/dev/null")
if files then
  for file in files:lines() do
    local ok, err = pcall(require, "user." .. file:gsub("%.lua$", ""))
    if not ok then errors[#errors + 1] = tostring(err) end
  end
  files:close()
end
if #errors > 0 then error(table.concat(errors, "\n")) end`
}

// ManagedLua is HyprConfigLua.managedLua: the managed hyprland.lua. opts:
// configLua's, plus { header, userDir, session, env, cursor, start }.
func (t *Tables) ManagedLua(module string, m, opts any) string {
	var kept []string
	for _, l := range strings.Split(module, "\n") {
		if !strings.HasPrefix(l, "--") {
			kept = append(kept, l)
		}
	}
	body := trim(strings.Join(kept, "\n"))
	userDir := get(opts, "userDir")
	return jsCat(get(opts, "header")) + ` (Hyprland mode: managed) from its Hyprland settings,
-- and rewritten whenever they (or the theme) change: edit those, not this file.
-- Your own config goes in ` + jsCat(userDir) + `/*.lua, loaded after this in name
-- order, so it overrides it. hl.unbind("KEY") there frees one of axiom's keys.

local axiom = (function()
` + indent(strings.Split(body, "\n"), "  ") + `
end)()

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
` + EnvLua(get(opts, "env")) + `
` + ConfigLua(m, opts) + `
axiom.setup()
` + AnimationsLua(m, get(opts, "motion")) + `
hl.on("hyprland.start", function()
` + indent(t.StartLua(get(opts, "session"), get(opts, "cursor"), get(opts, "start")), "  ") + `
end)

` + UserFilesLua(userDir) + `
`
}

// ReleasedLua is HyprConfigLua.releasedLua: the hyprland.lua leaving managed
// gives back when the takeover set nothing aside.
func ReleasedLua(userDir any, startLines string) string {
	return `-- Given back by axiom when it stopped managing Hyprland: this file is yours
-- now, and axiom won't write it again. It starts axiom and loads
-- ` + jsCat(userDir) + `/*.lua, as axiom's managed one did.
` + startLines + `

-- Not when it's required as one of those files itself (a managed takeover
-- adopts it into user/): the file requiring it loads them
if select("#", ...) == 0 then
` + indent(strings.Split(UserFilesLua(userDir), "\n"), "  ") + `
end`
}
