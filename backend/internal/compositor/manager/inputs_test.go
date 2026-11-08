package manager

import (
	"os/exec"
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
