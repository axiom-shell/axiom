package manager

import (
	"encoding/json"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
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
	// output when it's unset): a strip on the primary monitor goes there
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
}

// BindCtx is what a bind's command runs with: axiom's paths and the apps.
type BindCtx struct {
	AxiomPath      string `json:"axiomPath"`
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

	binds := jsonx.Arr()
	for _, b := range itemsOf(at("Keybinds", "binds")) {
		if paused, _ := getAny(b, "paused").(bool); !paused {
			binds.Append(b)
		}
	}
	workspaces := at("Workspaces")
	strips := stripsOf(workspaces, f.PrimaryMonitor)
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
	// The saved profile's rules for what's connected ([] for none)
	var outputRules any
	if outputs != nil {
		outputRules = jsonx.Arr(profileRules(f.Kind == "hyprland", at("Monitors", "items"), outputs)...)
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
		"outputs", tree(outputs),
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
	)
	in.Set("layerKey", string(jsonx.MarshalCompact(in)))
	specFile, specLive := spec(true), spec(false)
	in.Set("specFile", specFile)
	in.Set("specLive", specLive)
	in.Set("liveKey", string(jsonx.MarshalCompact(jsonx.Arr(specFile, specLive))))
	// The live spec but for the blur now (specLive is specFile with
	// Blur.Now): unchanged when only the blur paused or resumed
	in.Set("liveRestKey", string(jsonx.MarshalCompact(specFile)))
	return Inputs{in}
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
