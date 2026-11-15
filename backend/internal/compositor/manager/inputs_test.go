package manager

import (
	"os/exec"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// What buildInputs reads from the config beyond the goldens' (which hold
// the rest): paused binds left out, the strips by their screen targets,
// and the shell's previews laid over the config.
func TestBuildInputs(t *testing.T) {
	t.Parallel()
	strip := func(screen *jsonx.Object, direction string) *jsonx.Object {
		return jsonx.Obj("screen", screen, "direction", direction)
	}
	cfg := func(layout string) *jsonx.Object {
		return jsonx.Obj(
			"Keybinds", jsonx.Obj("binds", jsonx.Arr(jsonx.Obj("id", "a", "paused", false), jsonx.Obj("id", "b", "paused", true))),
			"Workspaces", jsonx.Obj("layout", layout, "stripColumnWidth", 50.0, "stripFollowFocus", true, "strips", jsonx.Arr(
				strip(jsonx.Obj("mode", "primary"), "vertical"),
				strip(jsonx.Obj("mode", "named", "names", jsonx.Arr("DP-1", "HDMI-A-1")), "horizontal"),
				strip(jsonx.Obj("mode", "all"), "horizontal"))))
	}
	cases := []struct {
		name, layout string
		previews     []config.Op
		binds        string
		strips       string
	}{
		{"strips by target", "perMonitor", nil, `[{"id":"a","paused":false}]`,
			`[{"monitor":"DP-1","direction":"vertical"},{"monitor":"HDMI-A-1","direction":"horizontal"},{"monitor":"*","direction":"horizontal"}]`},
		{"scrolling", "scrolling", nil, `[{"id":"a","paused":false}]`, `[{"monitor":"*","direction":"horizontal"}]`},
		{"previewed", "perMonitor", []config.Op{
			config.SetValue(config.Keys("Keybinds", "binds"), jsonx.Arr(jsonx.Obj("id", "c"))),
			config.SetValue(config.Keys("Workspaces", "layout"), "scrolling"),
			// No place for it (layout is a string): left out, the rest shown
			config.SetValue(config.Keys("Workspaces", "layout", "deeper"), 1.0),
		}, `[{"id":"c"}]`, `[{"monitor":"*","direction":"horizontal"}]`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			saved := cfg(c.layout)
			in := buildInputs(saved, &Facts{Kind: "hyprland", PrimaryMonitor: "DP-1", Previews: c.previews}, nil)
			if got := string(jsonx.MarshalCompact(in.get("binds"))); got != c.binds {
				t.Errorf("binds: got %s, want %s", got, c.binds)
			}
			if got := string(jsonx.MarshalCompact(in.get("strips"))); got != c.strips {
				t.Errorf("strips: got %s, want %s", got, c.strips)
			}
			if !jsonx.Equal(saved, cfg(c.layout)) {
				t.Error("the previews changed the config")
			}
		})
	}
}

// The shell's colors come as their text: the look's as "rrggbb", and of
// the palette only the names the managed options hold (a curve's name
// isn't one)
func TestShellColors(t *testing.T) {
	t.Parallel()
	cfg := jsonx.Obj(
		"Compositor", jsonx.Obj("hyprland", jsonx.Obj("decoration", jsonx.Obj("col", jsonx.Arr("accent")), "bezier", "easeOut")),
		"WindowBehaviour", jsonx.Obj("group", "base0D"),
		"WindowLook", jsonx.Obj("shadow", jsonx.Obj("enabled", true, "power", 2.0)))
	in := buildInputs(cfg, &Facts{
		Palette: map[string]string{"accent": "#C4A7E7", "base0D": "#80112233", "base00": "#191724", "easeOut": "x"},
		Look:    LookFacts{Active: "#9ccfd8", Inactive: "#ff403d52", Shadow: &ShadowFacts{Size: 8, Color: "#101010", Alpha: 0.5, Strength: 1}},
	}, nil)
	if got := string(jsonx.MarshalCompact(in.get("colors"))); got != `{"accent":"c4a7e7","base0D":"112233"}` {
		t.Errorf("colors: %s", got)
	}
	look := getAny(in.get("specLive"), "look")
	if got := string(jsonx.MarshalCompact(getAny(look, "shadow"))); got != `{"size":8,"power":2,"color":"10101080","rgb":"101010","alpha":0.5,"baseAlpha":0.5,"strength":1,"soft":false}` {
		t.Errorf("shadow: %s", got)
	}
}

// The input method the session starts: none while off, its framework only
// while installed (auto prefers fcitx5), and its switches as set.
func TestInputMethodOf(t *testing.T) {
	t.Parallel()
	method := func(framework string) *jsonx.Object {
		return jsonx.Obj("enabled", true, "framework", framework, "autostart", false, "legacyApps", true)
	}
	// Input.keyboard.method's schema defaults, turned on
	defaults := jsonx.Obj("enabled", true, "framework", "fcitx5", "autostart", true, "legacyApps", false)
	off := jsonx.Obj("enabled", false, "framework", "fcitx5", "autostart", true, "legacyApps", false)
	for _, c := range []struct {
		name      string
		method    any
		installed []string
		want      string
	}{
		{"the default, installed", defaults, []string{"fcitx5"}, "fcitx5"},
		{"the default, not installed", defaults, []string{"ibus"}, ""},
		{"auto prefers fcitx5", method("auto"), []string{"fcitx5", "ibus"}, "fcitx5"},
		{"auto takes ibus", method("auto"), []string{"ibus"}, "ibus"},
		{"auto with neither", method("auto"), nil, ""},
		{"ibus installed", method("ibus"), []string{"fcitx5", "ibus"}, "ibus"},
		{"ibus not installed", method("ibus"), []string{"fcitx5"}, ""},
		{"none", method("none"), []string{"fcitx5", "ibus"}, ""},
		{"off", off, []string{"fcitx5", "ibus"}, ""},
	} {
		got := inputMethodOf(c.method, c.installed)
		if f := got.Value("framework"); f != c.want {
			t.Errorf("%s: framework %v, want %q", c.name, f, c.want)
		}
		if wantOn := c.method == defaults || c.method == off; got.Value("autostart") != wantOn || got.Value("legacyApps") != !wantOn {
			t.Errorf("%s: switches %v", c.name, got)
		}
	}
}

// The frameworks installed are found by their programs
func TestFrameworks(t *testing.T) {
	t.Parallel()
	m := &Manager{o: Options{LookPath: func(p string) (string, error) {
		if p == "ibus-daemon" {
			return "/usr/bin/ibus-daemon", nil
		}
		return "", exec.ErrNotFound
	}}}
	if got := m.frameworks(); len(got) != 1 || got[0] != "ibus" {
		t.Errorf("frameworks %v, want [ibus]", got)
	}
}

// A strip on the primary monitor follows it to a connected output when the
// one named is unplugged or off (primaryOf)
func TestPrimaryOf(t *testing.T) {
	t.Parallel()
	dp := render.Output{Name: "DP-1"}
	edp := render.Output{Name: "eDP-1"}
	off := render.Output{Name: "HDMI-A-1", Disabled: true}
	tests := []struct {
		name    string
		primary string
		outputs []render.Output
		want    string
	}{
		{"connected", "DP-1", []render.Output{edp, dp}, "DP-1"},
		{"unplugged: the first on", "DP-1", []render.Output{off, edp}, "eDP-1"},
		{"off: the first on", "HDMI-A-1", []render.Output{off, edp}, "eDP-1"},
		{"not read yet: as named", "DP-1", nil, "DP-1"},
		{"none on: as named", "DP-1", []render.Output{off}, "DP-1"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := primaryOf(tt.primary, tt.outputs); got != tt.want {
				t.Errorf("primaryOf = %q, want %q", got, tt.want)
			}
		})
	}
}

// A bind is bound only while its "Only when" holds: the compositor, the
// strips (a strip action needs them too), the outputs connected (unknown
// until read, which binds no monitor-gated bind)
func TestBindConditions(t *testing.T) {
	t.Parallel()
	binds := jsonx.Arr(
		jsonx.Obj("id", "any", "action", "launcher"),
		jsonx.Obj("id", "niri", "action", "launcher", "whenCompositors", jsonx.Arr("niri")),
		jsonx.Obj("id", "notNiri", "action", "launcher", "whenCompositors", jsonx.Arr("hyprland", "sway")),
		jsonx.Obj("id", "narrow", "action", "stripNarrower"),
		jsonx.Obj("id", "split", "action", "toggleSplit", "whenLayout", "tiling"),
		jsonx.Obj("id", "docked", "action", "launcher", "whenMonitors", "external"),
		jsonx.Obj("id", "laptop", "action", "launcher", "whenMonitors", "laptopOnly"),
	)
	hypr := map[string]bool{"strips": true}
	strip := jsonx.Arr(jsonx.Obj("screen", jsonx.Obj("mode", "all"), "direction", "horizontal"))
	for _, c := range []struct {
		name      string
		kind      string
		supports  map[string]bool
		workspace *jsonx.Object
		outputs   []render.Output
		want      string
	}{
		{"hyprland tiling, outputs unknown", "hyprland", hypr, jsonx.Obj("layout", "standard"), nil, `["any","notNiri","split"]`},
		{"hyprland with a strip", "hyprland", hypr, jsonx.Obj("layout", "standard", "strips", strip), nil, `["any","notNiri","narrow"]`},
		{"hyprland scrolling", "hyprland", hypr, jsonx.Obj("layout", "scrolling"), nil, `["any","notNiri","narrow"]`},
		{"sway ignores strips", "sway", nil, jsonx.Obj("layout", "standard", "strips", strip), nil, `["any","notNiri","split"]`},
		{"niri, always strips", "niri", map[string]bool{"strips": true, "stripsAlways": true}, jsonx.Obj("layout", "standard"), nil, `["any","niri","narrow"]`},
		{"laptop alone", "hyprland", hypr, jsonx.Obj("layout", "standard"), []render.Output{{Name: "eDP-1"}}, `["any","notNiri","split","laptop"]`},
		{"docked, lid closed", "hyprland", hypr, jsonx.Obj("layout", "standard"), []render.Output{{Name: "eDP-1", Disabled: true}, {Name: "DP-2"}}, `["any","notNiri","split","docked"]`},
	} {
		cfg := jsonx.Obj("Keybinds", jsonx.Obj("binds", binds), "Workspaces", c.workspace)
		in := buildInputs(cfg, &Facts{Kind: c.kind, Supports: c.supports, PrimaryMonitor: "DP-1"}, c.outputs)
		ids := jsonx.Arr()
		for _, b := range itemsOf(in.get("binds")) {
			ids.Append(getAny(b, "id"))
		}
		if got := string(jsonx.MarshalCompact(ids)); got != c.want {
			t.Errorf("%s: %s, want %s", c.name, got, c.want)
		}
	}
}

// The WindowRules section as each compositor takes it: only the usable rules
// compiled (and in layerKey), the report for all of them
func TestWindowRulesInputs(t *testing.T) {
	t.Parallel()
	rule := func(id string, enabled bool, kinds, window string) string {
		return `{"id":"` + id + `","enabled":` + map[bool]string{true: "true", false: "false"}[enabled] +
			`,"windows":` + kinds + `,"window":` + window + `}`
	}
	one := `[{"conditions":[{"field":"appId","op":"is","value":"x"}]}]`
	cfgWith := func(t *testing.T, rules ...string) *jsonx.Object {
		t.Helper()
		v, err := jsonx.Unmarshal([]byte(`{"WindowRules":{"rules":[` + strings.Join(rules, ",") + `]}}`))
		if err != nil {
			t.Fatal(err)
		}
		return v.(*jsonx.Object)
	}
	facts := func(kind string) *Facts {
		return &Facts{Kind: kind, Supports: map[string]bool{"pin": true, "namedSpecial": true}}
	}
	build := func(t *testing.T, kind string, f func(*Facts), rules ...string) Inputs {
		t.Helper()
		fs := facts(kind)
		if f != nil {
			f(fs)
		}
		return buildInputs(cfgWith(t, rules...), fs, nil)
	}
	report := func(in Inputs) string { return string(jsonx.MarshalCompact(in.get("windowRulesReport"))) }

	float := rule("a", true, one, `{"float":true}`)
	off := rule("b", false, one, `{"float":true}`)
	broken := rule("c", true, `[]`, `{"float":true}`)

	t.Run("usable only", func(t *testing.T) {
		t.Parallel()
		with := build(t, "hyprland", nil, float, off, broken)
		without := build(t, "hyprland", nil, float)
		if string(jsonx.MarshalCompact(with.get("windowRules"))) != string(jsonx.MarshalCompact(without.get("windowRules"))) {
			t.Errorf("a disabled or bad rule reached the compositor: %s", jsonx.MarshalCompact(with.get("windowRules")))
		}
		if with.str("layerKey") != without.str("layerKey") {
			t.Error("a rule not written changed layerKey")
		}
		if !strings.Contains(report(with), `"code":"noKinds"`) || report(with) == report(without) {
			t.Errorf("the report: %s", report(with))
		}
	})
	t.Run("layerKey follows a usable rule", func(t *testing.T) {
		t.Parallel()
		base := build(t, "hyprland", nil, float, off)
		if build(t, "hyprland", nil, float, rule("b", false, one, `{"float":true,"pin":true}`)).str("layerKey") != base.str("layerKey") {
			t.Error("a disabled rule changed layerKey")
		}
		if build(t, "hyprland", nil, rule("a", true, one, `{"float":true,"pin":true}`), off).str("layerKey") == base.str("layerKey") {
			t.Error("a usable rule's change left layerKey")
		}
	})
	t.Run("shapes", func(t *testing.T) {
		t.Parallel()
		if h := build(t, "hyprland", nil, float).get("windowRules"); len(strList(h)) != 1 {
			t.Errorf("hyprland: %s", jsonx.MarshalCompact(h))
		}
		if n, ok := build(t, "niri", nil, float).get("windowRules").(*jsonx.Array); !ok || len(n.Items) != 1 {
			t.Errorf("niri: not one node")
		}
		s := build(t, "sway", nil, float).get("windowRules")
		if // one line for app_id and one for class
		len(strList(getAny(s, "file"))) != 2 || len(strList(getAny(s, "runtime"))) != 2 {
			t.Errorf("sway: %s", jsonx.MarshalCompact(s))
		}
		other := build(t, "none", nil, float)
		if other.get("windowRules") != nil || report(other) != `{"issues":[],"rules":[]}` {
			t.Errorf("another kind: %v %s", other.get("windowRules"), report(other))
		}
	})
	t.Run("rows", func(t *testing.T) {
		t.Parallel()
		// pin is Placed nowhere here (Hyprland writes it) and dropped on a
		// compositor without it; a live-only kind leaves nothing written
		live := rule("l", true, `[{"conditions":[{"field":"process","op":"is","value":"p"}]}]`, `{"float":true}`)
		in := build(t, "hyprland", func(f *Facts) { f.Supports["pin"] = false }, rule("a", true, one, `{"float":true,"pin":true}`), live)
		want := `[{"rule":"a","written":["float"],"placed":[],"dropped":["pin"],"live":[],"skipped":[]},` +
			`{"rule":"l","written":[],"placed":[],"dropped":[],"live":[0],"skipped":[]}]`
		if got := string(jsonx.MarshalCompact(getAny(in.get("windowRulesReport"), "rules"))); got != want {
			t.Errorf("rows:\n%s\nwant\n%s", got, want)
		}
	})
	t.Run("app ids", func(t *testing.T) {
		t.Parallel()
		app := rule("p", true, `[{"conditions":[{"field":"app","op":"is","value":"x.desktop"}]}]`, `{"float":true}`)
		resolved := build(t, "hyprland", func(f *Facts) {
			f.AppIDs = func(string) []string { return []string{"x", "x-class"} }
		}, app)
		if h := strList(resolved.get("windowRules")); len(h) != 1 || !strings.Contains(h[0], "x-class") {
			t.Errorf("app not resolved: %v", h)
		}
		unresolved := build(t, "hyprland", nil, app)
		if !strings.Contains(report(unresolved), `"skipped":[0]`) || len(strList(unresolved.get("windowRules"))) != 0 {
			t.Errorf("no app ids: %s", report(unresolved))
		}
	})
}
