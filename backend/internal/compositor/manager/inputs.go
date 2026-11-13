package manager

import (
	"encoding/json"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// Facts are what only the shell knows of the layer (compositor.inputs):
// what the compositor can do, the shell's paths and apps, the window look
// as the theme and the Appearance settings resolve it, the blur behind
// axiom's surfaces now, the cursor theme's XCursor name, the theme's
// colors, the motion, the primary monitor and its unsaved edits (previews).
// The rest (binds, profiles, strips, the look's and input's settings, the
// session, the options) the manager reads from the config, and the
// outputs from the compositor (buildInputs).
type Facts struct {
	Kind     string          `json:"kind"`
	Supports map[string]bool `json:"supports"`
	// SwayFX
	Fx  bool    `json:"fx"`
	Ctx BindCtx `json:"ctx"`
	// StartPattern finds the line starting axiom in a user's config
	StartPattern string `json:"startPattern"`
	// PrimaryMonitor is General.primaryMonitor as resolved (the first
	// output when it's unset or not connected): a strip on the primary
	// monitor goes there (primaryOf)
	PrimaryMonitor string    `json:"primaryMonitor"`
	Look           LookFacts `json:"look"`
	Blur           BlurFacts `json:"blur"`
	// XCursor is the cursor theme's XCursor name (CursorThemeManager)
	XCursor string `json:"xcursor"`
	// Palette is the theme's colors by name (Theme.stringToColorMap), as
	// the shell writes them (render.TextHex), for those the managed options
	// name
	Palette map[string]string `json:"palette"`
	Motion  Motion            `json:"motion"`
	// Previews are the shell's unsaved edits of the sections the layer
	// reads (ConfigOps.previewOps), laid over the config as they show
	Previews []config.Op `json:"previews"`
	// Frameworks are the input method frameworks installed ("fcitx5",
	// "ibus"): the daemon's to find (Options.LookPath), not the shell's
	Frameworks []string `json:"-"`
	// AppIDs gives an installed app's window app ids (a window rule's `app`
	// condition): the daemon's to read (Options.AppIDs), not the shell's
	AppIDs func(desktopID string) []string `json:"-"`
}

// BindCtx is what a bind's command runs with: axiom's paths and the apps.
type BindCtx struct {
	AxiomBin       string `json:"axiomBin"`
	ShellCommand   string `json:"shellCommand"`
	RestartCommand string `json:"restartCommand"`
	Terminal       string `json:"terminal"`
	FileManager    string `json:"fileManager"`
	Browser        string `json:"browser"`
}

// LookFacts are the window look's values the shell resolves
// (WindowLookConfig): the border colors (as the shell writes them,
// render.TextHex), the shape (axiom's while it matches it) and the shadow,
// null while none is cast.
type LookFacts struct {
	Active      string       `json:"active"`
	Inactive    string       `json:"inactive"`
	BorderWidth float64      `json:"borderWidth"`
	Radius      float64      `json:"radius"`
	Shadow      *ShadowFacts `json:"shadow"`
}

// ShadowFacts are the windows' shadow as cast (render.Look's
// opts.shadow), its color "" for the compositor's own.
type ShadowFacts struct {
	Size     float64 `json:"size"`
	Color    string  `json:"color"`
	Alpha    float64 `json:"alpha"`
	Soft     bool    `json:"soft"`
	Strength float64 `json:"strength"`
}

// BlurFacts are the blur behind axiom's surfaces: as saved (for a file)
// and now (paused over a fullscreen window).
type BlurFacts struct {
	Saved          bool    `json:"saved"`
	Now            bool    `json:"now"`
	ThroughWindows bool    `json:"throughWindows"`
	Backdrops      bool    `json:"backdrops"`
	Threshold      float64 `json:"threshold"`
}

// Motion is the shell's motion (Look & Feel → Motion), for the managed
// animations.
type Motion struct {
	Fast    float64 `json:"fast"`
	Normal  float64 `json:"normal"`
	Slow    float64 `json:"slow"`
	Enabled bool    `json:"enabled"`
}

// tree is v as the JSON tree it marshals to
func tree(v any) any {
	data, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	out, err := jsonx.Unmarshal(data)
	if err != nil {
		return nil
	}
	return out
}

// buildInputs is what the layer is made of: the config (cfg, with the
// shell's previews laid over it), the shell's facts and the outputs
// connected (nil until read: the files then keep what they say), as the writers read it, with layerKey (a change re-applies the layer), liveKey (a change
// is only evaluated at runtime) and liveRestKey (liveKey but for the blur
// now).
func buildInputs(cfg *jsonx.Object, f *Facts, outputs []render.Output) Inputs {
	if cfg == nil {
		cfg = jsonx.NewObject()
	}
	if len(f.Previews) > 0 {
		cfg = jsonx.Clone(cfg).(*jsonx.Object)
		// One at a time: a preview the config has no place for is left out,
		// as the rest still show
		for _, op := range f.Previews {
			_ = config.ApplyOps(cfg, []config.Op{op})
		}
	}
	at := func(path ...string) any {
		v, _ := config.Lookup(cfg, config.Keys(path...))
		return v
	}
	flag := func(path ...string) bool { b, _ := at(path...).(bool); return b }

	workspaces := at("Workspaces")
	strips := stripsOf(workspaces, primaryOf(f.PrimaryMonitor, outputs))
	// The binds to bind: not paused, their "Only when" holding
	conditions := bindFacts(f, workspaces, strips, outputs)
	binds := jsonx.Arr()
	for _, b := range itemsOf(at("Keybinds", "binds")) {
		if paused, _ := getAny(b, "paused").(bool); !paused && render.BindHolds(b, conditions) {
			binds.Append(b)
		}
	}
	stripOptions := jsonx.Obj("stripColumnWidth", getAny(workspaces, "stripColumnWidth"), "stripFollowFocus", getAny(workspaces, "stripFollowFocus"))
	behaviour := at("WindowBehaviour")
	managed := jsonx.NewObject()
	for _, part := range []any{at("Compositor", "hyprland"), behaviour} {
		if o, ok := part.(*jsonx.Object); ok {
			for _, k := range o.Keys() {
				managed.Set(k, o.Value(k))
			}
		}
	}
	// The saved profile's rules for what's connected ([] for none); sway's
	// name each output by its connector (SwayConnectorRules)
	var outputRules any
	if outputs != nil {
		outputRules = jsonx.Arr(profileRules(f.Kind == "hyprland", at("Monitors", "items"), outputs)...)
		if f.Kind == "sway" {
			outputRules = render.SwayConnectorRules(outputRules, tree(outputs))
		}
	}
	// Hyprland's: those rules as hl.monitor calls, a mirror named by its
	// connector (the calls, not the outputs, so an output only turned off
	// doesn't change layerKey)
	var monitorCalls any
	if outputRules != nil && f.Kind == "hyprland" {
		monitorCalls = strs(render.MonitorCalls(outputRules, render.MirrorNames(tree(outputs))))
	}
	spec := func(forFile bool) *jsonx.Object {
		surfacesBlur := f.Blur.Now
		if forFile {
			surfacesBlur = f.Blur.Saved
		}
		opts := lookOpts(f.Look)
		opts.Set("surfacesBlur", surfacesBlur)
		return jsonx.Obj(
			"look", render.Look(at("WindowLook"), opts),
			"surfaces", jsonx.Obj("blur", surfacesBlur, "throughWindows", f.Blur.ThroughWindows, "backdrops", f.Blur.Backdrops, "threshold", f.Blur.Threshold),
			"input", render.Input(at("Input"), f.XCursor))
	}
	// Compiled before layerKey, so a usable rule's change re-applies the
	// layer; the report after it, so an issue on a disabled rule doesn't
	compiled, report := windowRules(at("WindowRules"), at("Keybinds"), f)
	in := jsonx.Obj(
		"kind", f.Kind,
		"supports", tree(f.Supports),
		"fx", f.Fx,
		"binds", binds,
		"ctx", tree(f.Ctx),
		"startPattern", f.StartPattern,
		"requiredSettings", flag("Compositor", "requiredSettings"),
		"strips", strips,
		"stripOptions", stripOptions,
		"stripsKey", string(jsonx.MarshalCompact(jsonx.Arr(strips, stripOptions))),
		"outputRules", outputRules,
		"monitorCalls", monitorCalls,
		"session", at("Session"),
		"qt", flag("ThemeIntegrations", "qt"),
		"managed", managed,
		"behaviour", behaviour,
		"swayOptions", at("Compositor", "sway"),
		"niriOptions", at("Compositor", "niri"),
		"colors", colorsNamed(managed, f.Palette),
		"motion", tree(f.Motion),
		"idle", flag("Idle", "enabled"),
		"polkit", flag("Polkit", "enabled"),
		"compositorSwitcher", flag("WindowSwitcher", "compositorSwitcher") && f.Supports["compositorSwitcher"],
		"inputMethod", inputMethodOf(at("Input", "keyboard", "method"), f.Frameworks),
		"windowRules", compiled,
	)
	in.Set("layerKey", string(jsonx.MarshalCompact(in)))
	specFile, specLive := spec(true), spec(false)
	in.Set("specFile", specFile)
	in.Set("specLive", specLive)
	in.Set("liveKey", string(jsonx.MarshalCompact(jsonx.Arr(specFile, specLive))))
	// The live spec but for the blur now (specLive is specFile with
	// Blur.Now): unchanged when only the blur paused or resumed
	in.Set("liveRestKey", string(jsonx.MarshalCompact(specFile)))
	in.Set("windowRulesReport", report)
	return Inputs{in}
}

// ruleRow is what the editor shows of a usable rule: its effects by what
// happens to them (compositor.state's windowRules)
type ruleRow struct {
	Rule    string   `json:"rule"`
	Written []string `json:"written"` // effects the compositor's config applies
	Placed  []string `json:"placed"`  // effects the daemon places after open
	Dropped []string `json:"dropped"` // effects this compositor can't do
	Live    []int    `json:"live"`    // kinds only the daemon can match
	Skipped []int    `json:"skipped"` // kinds this compositor can't match
}

// windowRules is the WindowRules section as f.Kind's compositor takes it:
// the usable rules compiled (Hyprland's lines, niri's nodes, sway's
// {file, runtime} lines; nil for any other kind) and what the editor shows
// of them ({issues, rules}). Only the usable rules (a bad one still saves,
// but isn't compiled).
func windowRules(section, keybinds any, f *Facts) (compiled any, report *jsonx.Object) {
	cfg := windowrules.Parse(section)
	issues := windowrules.Validate(cfg, windowrules.Context{BindIDs: windowrules.BindIDs(keybinds)})
	usable := windowrules.Usable(cfg, issues)
	set := render.RuleSet{Rules: usable, Apps: windowrules.AppIDs(f.AppIDs), Supports: f.Supports}
	var left []render.Unwritten
	switch f.Kind {
	case "hyprland":
		var lines []string
		lines, left = render.HyprRuleLines(set)
		compiled = strs(lines)
	case "niri":
		compiled, left = render.NiriRuleNodes(set)
	case "sway":
		file, left2 := render.SwayRuleLines(set, false)
		runtime, _ := render.SwayRuleLines(set, true)
		left = left2
		compiled = jsonx.Obj("file", strs(file), "runtime", strs(runtime))
	default:
		return nil, jsonx.Obj("issues", tree(issues), "rules", jsonx.Arr())
	}
	byRule := map[string]render.Unwritten{}
	for _, u := range left {
		byRule[u.Rule] = u
	}
	rows := make([]ruleRow, 0, len(usable))
	for _, r := range usable {
		u := byRule[r.ID]
		row := ruleRow{Rule: r.ID, Written: []string{}, Placed: orEmpty(u.Placed), Dropped: orEmpty(u.Dropped),
			Live: orEmpty(u.Live), Skipped: orEmpty(u.Skipped)}
		// Nothing is printed for a rule none of whose kinds is written
		if len(u.Live)+len(u.Skipped) < len(r.Kinds) {
			for _, key := range render.RuleEffects(r.Window) {
				if !slices.Contains(u.Placed, key) && !slices.Contains(u.Dropped, key) {
					row.Written = append(row.Written, key)
				}
			}
		}
		rows = append(rows, row)
	}
	return compiled, jsonx.Obj("issues", tree(issues), "rules", tree(rows))
}

func orEmpty[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

// lookOpts are render.Look's opts from the shell's look, its colors as
// "rrggbb"
func lookOpts(l LookFacts) *jsonx.Object {
	var shadow any
	if s := l.Shadow; s != nil {
		color := ""
		if s.Color != "" {
			color = render.TextHex(s.Color)
		}
		shadow = jsonx.Obj("size", s.Size, "color", color, "alpha", s.Alpha, "soft", s.Soft, "strength", s.Strength)
	}
	return jsonx.Obj("activeHex", render.TextHex(l.Active), "inactiveHex", render.TextHex(l.Inactive),
		"borderWidth", l.BorderWidth, "radius", l.Radius, "shadow", shadow)
}

// colorsNamed are the theme colors (palette) the managed options name
// (every string in them is tried: one that isn't a color, a curve's name,
// is left out), as "rrggbb"
func colorsNamed(managed any, palette map[string]string) *jsonx.Object {
	out := jsonx.NewObject()
	var walk func(v any)
	walk = func(v any) {
		switch x := v.(type) {
		case string:
			if hex := render.TextHex(palette[x]); hex != "" {
				out.Set(x, hex)
			}
		case *jsonx.Object:
			for _, k := range x.Keys() {
				walk(x.Value(k))
			}
		case *jsonx.Array:
			for _, item := range x.Items {
				walk(item)
			}
		}
	}
	walk(managed)
	return out
}

// primaryOf is the primary monitor (Facts.PrimaryMonitor) among outputs
// (nil until read: primary): primary while it's connected and on, else the
// first output on, as the shell resolves General.primaryMonitor, so a strip
// on the primary monitor follows it before the shell's facts do.
func primaryOf(primary string, outputs []render.Output) string {
	first := ""
	for _, o := range outputs {
		if o.Disabled {
			continue
		}
		if o.Name == primary {
			return primary
		}
		if first == "" {
			first = o.Name
		}
	}
	if first == "" {
		return primary
	}
	return first
}

// stripsOf are the strips (Hyprland's scrolling layout) per monitor, as
// WorkspacesConfig.strips: [{ monitor, direction }] from each strip's
// screen target (the primary monitor's name, "*" for every monitor a named
// entry doesn't cover, or each one named), a monitor's first entry kept;
// the scrolling layout makes every monitor a horizontal strip.
func stripsOf(workspaces any, primary string) *jsonx.Array {
	if getAny(workspaces, "layout") == "scrolling" {
		return jsonx.Arr(jsonx.Obj("monitor", "*", "direction", "horizontal"))
	}
	out, seen := jsonx.Arr(), map[string]bool{}
	for _, strip := range itemsOf(getAny(workspaces, "strips")) {
		screen := getAny(strip, "screen")
		var monitors []any
		switch getAny(screen, "mode") {
		case "all":
			monitors = []any{"*"}
		case "named":
			monitors = itemsOf(getAny(screen, "names"))
		default:
			monitors = []any{primary}
		}
		for _, m := range monitors {
			name := jsonx.ToString(m)
			if seen[name] {
				continue
			}
			seen[name] = true
			out.Append(jsonx.Obj("monitor", m, "direction", getAny(strip, "direction")))
		}
	}
	return out
}

// bindFacts are what a bind's "Only when" is decided on (render.BindHolds,
// KeybindManager.conditionFacts): the compositor, whether any output is a
// strip (where the compositor has strips), the grid layout, dynamic
// workspaces, and the connected outputs' names (nil until read, which
// holds no monitor condition)
func bindFacts(f *Facts, workspaces any, strips *jsonx.Array, outputs []render.Output) *jsonx.Object {
	var names any
	if outputs != nil {
		list := jsonx.Arr()
		for _, o := range outputs {
			if !o.Disabled {
				list.Append(o.Name)
			}
		}
		names = list
	}
	return jsonx.Obj(
		"kind", f.Kind,
		"strips", f.Supports["stripsAlways"] || (f.Supports["strips"] && len(strips.Items) > 0),
		"grid", getAny(workspaces, "layout") == "grid",
		"dynamic", f.Supports["dynamicWorkspaces"],
		"outputs", names,
	)
}

// inputMethodOf is the input method the session starts (render.
// InputMethodEnv's): Input.keyboard.method (schema-filled) with its framework
// resolved to one installed, "" for none or while axiom doesn't manage the
// input method (enabled off): auto is fcitx5 when it's installed, else
// ibus; a framework named only while it's installed, so a session without
// it gets no variables and no failing autostart.
func inputMethodOf(method any, installed []string) *jsonx.Object {
	has := func(name string) bool {
		for _, n := range installed {
			if n == name {
				return true
			}
		}
		return false
	}
	framework, _ := getAny(method, "framework").(string)
	if enabled, _ := getAny(method, "enabled").(bool); !enabled {
		framework = "none"
	}
	resolved := ""
	switch framework {
	case "auto":
		for _, n := range []string{"fcitx5", "ibus"} {
			if has(n) {
				resolved = n
				break
			}
		}
	case "fcitx5", "ibus":
		if has(framework) {
			resolved = framework
		}
	}
	autostart, _ := getAny(method, "autostart").(bool)
	legacy, _ := getAny(method, "legacyApps").(bool)
	return jsonx.Obj("framework", resolved, "autostart", autostart, "legacyApps", legacy)
}
