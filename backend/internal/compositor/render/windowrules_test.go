package render

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	lua "github.com/yuin/gopher-lua"

	"github.com/axiom-shell/axiom/backend/internal/compositor/kdl"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

type conds = []windowrules.Condition

func cond(f windowrules.Field, op windowrules.Op, v string) windowrules.Condition {
	return windowrules.Condition{Field: f, Op: op, Value: v}
}

func rule(id string, w windowrules.WindowEffects, kinds ...conds) windowrules.Rule {
	r := windowrules.Rule{ID: id, Enabled: true, Window: w}
	for _, k := range kinds {
		r.Kinds = append(r.Kinds, windowrules.Kind{Conditions: k})
	}
	return r
}

func supports(keys ...string) map[string]bool {
	m := map[string]bool{}
	for _, k := range keys {
		m[k] = true
	}
	return m
}

var (
	hyprSupports  = supports("namedSpecial", "pin", "windowBlur", "windowOpacity", "ruleMaximize", "ruleTearing", "ruleNoScreenShare", "ruleXwayland")
	niriSupports  = supports("windowBlur", "windowOpacity", "ruleMaximize", "ruleNoScreenShare")
	swaySupports  = supports("namedSpecial", "pin", "windowOpacity", "ruleTearing", "ruleXwayland")
	swayFXSupport = supports("namedSpecial", "pin", "windowOpacity", "ruleTearing", "ruleXwayland", "windowBlur")
)

const (
	appID    = windowrules.FieldAppID
	title    = windowrules.FieldTitle
	xway     = windowrules.FieldXwayland
	is       = windowrules.OpIs
	isNot    = windowrules.OpIsNot
	contains = windowrules.OpContains
)

// the plan's two example rules, highest first
func exampleRules() []windowrules.Rule {
	return []windowrules.Rule{
		rule("pip", windowrules.WindowEffects{Float: true, Width: 640, Height: 360, Pin: true, NoFocus: true},
			conds{cond(appID, is, "firefox"), cond(title, contains, "Picture-in-Picture")}),
		rule("games", windowrules.WindowEffects{Workspace: "games", Fullscreen: true, Tearing: true},
			conds{cond(appID, windowrules.OpMatches, `^steam_app_\d+$`)},
			conds{cond(title, is, "Game"), cond(appID, isNot, "steam")}),
	}
}

func TestHyprRuleLines(t *testing.T) {
	t.Parallel()
	one := conds{cond(appID, is, "a")}
	const head = `hl.window_rule({ name = "axiom-rule-r-0", match = { class = "\\A(?:a)\\z" }, `
	effects := []struct {
		name string
		w    windowrules.WindowEffects
		want string
	}{
		{"monitor", windowrules.WindowEffects{Monitor: "DP-1"}, `monitor = "DP-1"`},
		{"workspace number", windowrules.WindowEffects{Workspace: "3"}, `workspace = "3 silent"`},
		{"workspace follow", windowrules.WindowEffects{Workspace: "3", Follow: true}, `workspace = "3"`},
		{"workspace name", windowrules.WindowEffects{Workspace: "my ws"}, `workspace = "name:my ws silent"`},
		{"workspace relative-looking name", windowrules.WindowEffects{Workspace: "-1"}, `workspace = "name:-1 silent"`},
		{"workspace name follow", windowrules.WindowEffects{Workspace: "e+1", Follow: true}, `workspace = "name:e+1"`},
		{"special shown", windowrules.WindowEffects{Special: windowrules.Special{ID: "g"}}, `workspace = "special:g"`},
		{"special silent", windowrules.WindowEffects{Special: windowrules.Special{ID: "g", Silent: true}}, `workspace = "special:g silent"`},
		{"float", windowrules.WindowEffects{Float: true}, `float = true`},
		{"size", windowrules.WindowEffects{Width: 800, Height: 600}, `size = "800 600"`},
		{"center", windowrules.WindowEffects{Center: true}, `center = true`},
		{"fullscreen", windowrules.WindowEffects{Fullscreen: true}, `fullscreen = true`},
		{"maximize", windowrules.WindowEffects{Maximize: true}, `maximize = true`},
		{"pin", windowrules.WindowEffects{Pin: true}, `pin = true`},
		{"opacity 80", windowrules.WindowEffects{Opacity: 80}, `opacity = "0.8 override"`},
		{"opacity 5", windowrules.WindowEffects{Opacity: 5}, `opacity = "0.05 override"`},
		{"opacity 100", windowrules.WindowEffects{Opacity: 100}, `opacity = "1 override"`},
		{"noBlur", windowrules.WindowEffects{NoBlur: true}, `no_blur = true`},
		{"noFocus", windowrules.WindowEffects{NoFocus: true}, `no_initial_focus = true`},
		{"noScreenShare", windowrules.WindowEffects{NoScreenShare: true}, `no_screen_share = true`},
		{"tearing", windowrules.WindowEffects{Tearing: true}, `immediate = true`},
	}
	for _, tc := range effects {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("r", tc.w, one)}, Supports: hyprSupports})
			if want := head + tc.want + ` })`; len(got) != 1 || got[0] != want || left != nil {
				t.Fatalf("got %q %v\nwant %q", got, left, want)
			}
		})
	}
	matches := []struct {
		name string
		kind conds
		want string
	}{
		{"app id is", one, `class = "\\A(?:a)\\z"`},
		{"title contains", conds{cond(title, contains, "x")}, `title = "\\A(?s:.*)(?:x)(?s:.*)\\z"`},
		{"app id isNot", conds{cond(appID, isNot, "a")}, `class = "negative:\\A(?:(?:a))\\z"`},
		{"app id is and isNot", conds{cond(appID, is, "a"), cond(appID, isNot, "b")}, `class = "\\A(?:a)\\z", initial_class = "negative:\\A(?:(?:b))\\z"`},
		{"title is and isNot", conds{cond(title, is, "a"), cond(title, isNot, "b")}, `title = "\\A(?:a)\\z", initial_title = "negative:\\A(?:(?:b))\\z"`},
		{"xwayland is", conds{cond(xway, is, "")}, `xwayland = true`},
		{"xwayland isNot", conds{cond(xway, isNot, "")}, `xwayland = false`},
		{"xwayland twice, same", conds{cond(xway, is, ""), cond(xway, is, "")}, `xwayland = true`},
	}
	for _, tc := range matches {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, _ := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("r", windowrules.WindowEffects{Float: true}, tc.kind)}, Supports: hyprSupports})
			if want := `hl.window_rule({ name = "axiom-rule-r-0", match = { ` + tc.want + ` }, float = true })`; len(got) != 1 || got[0] != want {
				t.Fatalf("got %q\nwant %q", got, want)
			}
		})
	}
	float := windowrules.WindowEffects{Float: true}
	t.Run("xwayland is and isNot is skipped", func(t *testing.T) {
		t.Parallel()
		got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("r", float, conds{cond(xway, is, ""), cond(xway, isNot, "")})}, Supports: hyprSupports})
		if got != nil || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Skipped: []int{0}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("app condition", func(t *testing.T) {
		t.Parallel()
		apps := func(id string) []string {
			if id == "org.x" {
				return []string{"x", "y"}
			}
			return nil
		}
		got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{
			rule("r", float, conds{cond(windowrules.FieldApp, is, "org.x")}, conds{cond(windowrules.FieldApp, is, "none")}),
		}, Apps: apps, Supports: hyprSupports})
		want := `hl.window_rule({ name = "axiom-rule-r-0", match = { class = "\\A(?:(?:x)|(?:y))\\z" }, float = true })`
		if len(got) != 1 || got[0] != want || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Skipped: []int{1}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("live kind between compiled ones", func(t *testing.T) {
		t.Parallel()
		got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{
			rule("r", float, one, conds{cond(windowrules.FieldProcess, is, "p")}, conds{cond(appID, is, "b")}),
		}, Supports: hyprSupports})
		if len(got) != 2 || !strings.Contains(got[0], `"axiom-rule-r-0"`) || !strings.Contains(got[1], `"axiom-rule-r-2"`) ||
			!reflect.DeepEqual(left, []Unwritten{{Rule: "r", Live: []int{1}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("lower priority first", func(t *testing.T) {
		t.Parallel()
		got, _ := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("hi", float, one), rule("lo", float, one)}, Supports: hyprSupports})
		if len(got) != 2 || !strings.Contains(got[0], "axiom-rule-lo-0") || !strings.Contains(got[1], "axiom-rule-hi-0") {
			t.Fatalf("%q", got)
		}
	})
	t.Run("shell-only rule", func(t *testing.T) {
		t.Parallel()
		got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("r", windowrules.WindowEffects{}, one)}, Supports: hyprSupports})
		if got != nil || left != nil {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("maximize without the flag", func(t *testing.T) {
		t.Parallel()
		got, left := HyprRuleLines(RuleSet{Rules: []windowrules.Rule{rule("r", windowrules.WindowEffects{Maximize: true, Float: true}, one)}, Supports: supports()})
		if len(got) != 1 || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Dropped: []string{"maximize"}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("example", func(t *testing.T) {
		t.Parallel()
		got, left := HyprRuleLines(RuleSet{Rules: exampleRules(), Supports: hyprSupports})
		want := `hl.window_rule({ name = "axiom-rule-games-0", match = { class = "\\A(?s:.*)(?:\\Asteam_app_[0-9]+\\z)(?s:.*)\\z" }, workspace = "name:games silent", fullscreen = true, immediate = true })
hl.window_rule({ name = "axiom-rule-games-1", match = { class = "negative:\\A(?:(?:steam))\\z", title = "\\A(?:Game)\\z" }, workspace = "name:games silent", fullscreen = true, immediate = true })
hl.window_rule({ name = "axiom-rule-pip-0", match = { class = "\\A(?:firefox)\\z", title = "\\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\\z" }, float = true, size = "640 360", pin = true, no_initial_focus = true })`
		if strings.Join(got, "\n") != want || left != nil {
			t.Fatalf("got\n%s\n%v", strings.Join(got, "\n"), left)
		}
	})
}

func niriText(t *testing.T, rules []windowrules.Rule, apps windowrules.AppIDs) (string, []Unwritten) {
	t.Helper()
	nodes, left := NiriRuleNodes(RuleSet{Rules: rules, Apps: apps, Supports: niriSupports})
	return KdlSerialize(nodes, 0), left
}

func TestNiriRuleNodes(t *testing.T) {
	t.Parallel()
	one := conds{cond(appID, is, "a")}
	const m = `    match app-id="\\A(?:a)\\z"` + "\n"
	effects := []struct {
		name string
		w    windowrules.WindowEffects
		want string
	}{
		{"monitor", windowrules.WindowEffects{Monitor: "DP-1"}, `open-on-output "DP-1"`},
		{"workspace name", windowrules.WindowEffects{Workspace: "w"}, `open-on-workspace "w"`},
		{"workspace name follow", windowrules.WindowEffects{Workspace: "w", Follow: true}, `open-on-workspace "w"`},
		{"float", windowrules.WindowEffects{Float: true}, `open-floating true`},
		{"size", windowrules.WindowEffects{Width: 800, Height: 600}, "default-column-width {\n        fixed 800\n    }\n    default-window-height {\n        fixed 600\n    }"},
		{"fullscreen", windowrules.WindowEffects{Fullscreen: true}, `open-fullscreen true`},
		{"maximize", windowrules.WindowEffects{Maximize: true}, `open-maximized-to-edges true`},
		{"opacity", windowrules.WindowEffects{Opacity: 80}, `opacity 0.8`},
		{"opacity 100", windowrules.WindowEffects{Opacity: 100}, `opacity 1.0`},
		{"noBlur", windowrules.WindowEffects{NoBlur: true}, "background-effect {\n        blur false\n    }"},
		{"noFocus", windowrules.WindowEffects{NoFocus: true}, `open-focused false`},
		{"noScreenShare", windowrules.WindowEffects{NoScreenShare: true}, `block-out-from "screencast"`},
	}
	for _, tc := range effects {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, left := niriText(t, []windowrules.Rule{rule("r", tc.w, one)}, nil)
			if want := "window-rule {\n" + m + "    " + tc.want + "\n}"; got != want || left != nil {
				t.Fatalf("got\n%s\n%v\nwant\n%s", got, left, want)
			}
		})
	}
	t.Run("numbered workspace is placed", func(t *testing.T) {
		t.Parallel()
		got, left := niriText(t, []windowrules.Rule{rule("r", windowrules.WindowEffects{Workspace: "3"}, one)}, nil)
		if got != "" || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Placed: []string{"workspace"}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("kinds plain, plain, negated", func(t *testing.T) {
		t.Parallel()
		got, _ := niriText(t, []windowrules.Rule{rule("r", windowrules.WindowEffects{Float: true},
			one, conds{cond(title, is, "t")}, conds{cond(title, is, "u"), cond(appID, isNot, "b")})}, nil)
		want := `window-rule {
    match app-id="\\A(?:a)\\z"
    match title="\\A(?:t)\\z"
    open-floating true
}
window-rule {
    match title="\\A(?:u)\\z"
    exclude app-id="\\A(?:(?:b))\\z"
    open-floating true
}`
		if got != want {
			t.Fatalf("got\n%s", got)
		}
	})
	t.Run("negation only and two negated fields", func(t *testing.T) {
		t.Parallel()
		got, _ := niriText(t, []windowrules.Rule{rule("r", windowrules.WindowEffects{Float: true},
			conds{cond(appID, isNot, "b"), cond(title, isNot, "c")})}, nil)
		want := `window-rule {
    exclude app-id="\\A(?:(?:b))\\z"
    exclude title="\\A(?:(?:c))\\z"
    open-floating true
}`
		if got != want {
			t.Fatalf("got\n%s", got)
		}
	})
	t.Run("xwayland kind is skipped", func(t *testing.T) {
		t.Parallel()
		got, left := niriText(t, []windowrules.Rule{rule("r", windowrules.WindowEffects{Float: true}, conds{cond(xway, is, "")})}, nil)
		if got != "" || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Skipped: []int{0}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("no flag, no way, or nothing to write", func(t *testing.T) {
		t.Parallel()
		got, left := niriText(t, []windowrules.Rule{rule("r", windowrules.WindowEffects{Pin: true, Tearing: true, Special: windowrules.Special{ID: "s"}, Center: true}, one)}, nil)
		if got != "" || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Dropped: []string{"special", "pin", "tearing"}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("supported flags don't write what niri can't", func(t *testing.T) {
		t.Parallel()
		all := supports("pin", "namedSpecial", "ruleTearing")
		nodes, left := NiriRuleNodes(RuleSet{Rules: []windowrules.Rule{rule("r", windowrules.WindowEffects{Pin: true, Tearing: true, Special: windowrules.Special{ID: "s"}}, one)}, Supports: all})
		if got := KdlSerialize(nodes, 0); got != "" || !reflect.DeepEqual(left, []Unwritten{{Rule: "r", Dropped: []string{"special", "pin", "tearing"}}}) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("example", func(t *testing.T) {
		t.Parallel()
		got, left := niriText(t, exampleRules(), nil)
		want := `window-rule {
    match app-id="\\A(?s:.*)(?:\\Asteam_app_[0-9]+\\z)(?s:.*)\\z"
    open-on-workspace "games"
    open-fullscreen true
}
window-rule {
    match title="\\A(?:Game)\\z"
    exclude app-id="\\A(?:(?:steam))\\z"
    open-on-workspace "games"
    open-fullscreen true
}
window-rule {
    match app-id="\\A(?:firefox)\\z" title="\\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\\z"
    open-floating true
    default-column-width {
        fixed 640
    }
    default-window-height {
        fixed 360
    }
    open-focused false
}`
		wantLeft := []Unwritten{{Rule: "pip", Dropped: []string{"pin"}}, {Rule: "games", Dropped: []string{"tearing"}}}
		if got != want || !reflect.DeepEqual(left, wantLeft) {
			t.Fatalf("got\n%s\n%v", got, left)
		}
	})
}

func swayLines(rules []windowrules.Rule, sup map[string]bool, runtime bool) ([]string, []Unwritten) {
	return SwayRuleLines(RuleSet{Rules: rules, Supports: sup}, runtime)
}

func TestSwayRuleLines(t *testing.T) {
	t.Parallel()
	one := conds{cond(appID, is, "a")}
	const both = `[app_id="\A(?:a)\z"]`
	const cls = `[class="\A(?:a)\z"]`
	commands := []struct {
		name string
		w    windowrules.WindowEffects
		want string
	}{
		{"monitor", windowrules.WindowEffects{Monitor: "DP-1"}, `move container to output DP-1`},
		{"workspace number", windowrules.WindowEffects{Workspace: "3"}, `move container to workspace number 3`},
		{"workspace number follow", windowrules.WindowEffects{Workspace: "3", Follow: true}, `move container to workspace number 3, workspace number 3`},
		{"workspace name", windowrules.WindowEffects{Workspace: "my ws"}, `move container to workspace "my ws"`},
		{"workspace name follow", windowrules.WindowEffects{Workspace: "w", Follow: true}, `move container to workspace w, workspace w`},
		{"float", windowrules.WindowEffects{Float: true}, `floating enable`},
		{"size", windowrules.WindowEffects{Width: 640, Height: 360}, `resize set 640 px 360 px`},
		{"fullscreen", windowrules.WindowEffects{Fullscreen: true}, `fullscreen enable`},
		{"opacity", windowrules.WindowEffects{Opacity: 80}, `opacity 0.8`},
		{"noBlur", windowrules.WindowEffects{NoBlur: true}, `blur disable`},
		{"tearing", windowrules.WindowEffects{Tearing: true}, `allow_tearing yes`},
		{"pin and center last", windowrules.WindowEffects{Center: true, Pin: true, Float: true}, `floating enable, sticky enable, move position center`},
	}
	for _, tc := range commands {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, left := swayLines([]windowrules.Rule{rule("r", tc.w, one)}, swayFXSupport, true)
			cmd := tc.want
			if strings.ContainsAny(cmd, `,"`) {
				cmd = SwayBindCommand(cmd, true)
			}
			want := []string{"for_window " + both + " " + cmd, "for_window " + cls + " " + cmd}
			if !reflect.DeepEqual(got, want) || left != nil {
				t.Fatalf("got %q %v\nwant %q", got, left, want)
			}
		})
	}
	flt := windowrules.WindowEffects{Float: true}
	lines := []struct {
		name string
		kind conds
		want []string
	}{
		{"xwayland is", conds{cond(xway, is, "")}, []string{`[shell="xwayland"]`}},
		{"xwayland is with app id", conds{cond(xway, is, ""), cond(appID, is, "a")}, []string{`[class="\A(?:a)\z" shell="xwayland"]`}},
		{"xwayland isNot with app id", conds{cond(xway, isNot, ""), cond(appID, is, "a")}, []string{`[app_id="\A(?:a)\z" shell="xdg_shell"]`}},
		{"title only", conds{cond(title, is, "t")}, []string{`[title="\A(?:t)\z"]`}},
		{"negation alone", conds{cond(appID, isNot, "a")}, []string{`[app_id="\A(?!\A(?:(?:a))\z)"]`, `[class="\A(?!\A(?:(?:a))\z)"]`}},
		{"negation with a positive", conds{cond(title, is, "t"), cond(title, isNot, "u")}, []string{`[title="\A(?=\A(?:t)\z)(?!\A(?:(?:u))\z)"]`}},
	}
	for _, tc := range lines {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, _ := swayLines([]windowrules.Rule{rule("r", flt, tc.kind)}, swaySupports, true)
			var want []string
			for _, l := range tc.want {
				want = append(want, "for_window "+l+" floating enable")
			}
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("got %q\nwant %q", got, want)
			}
		})
	}
	t.Run("noFocus only", func(t *testing.T) {
		t.Parallel()
		got, _ := swayLines([]windowrules.Rule{rule("r", windowrules.WindowEffects{NoFocus: true}, one)}, swaySupports, true)
		if want := []string{"no_focus " + both, "no_focus " + cls}; !reflect.DeepEqual(got, want) {
			t.Fatalf("got %q", got)
		}
	})
	t.Run("placed and dropped", func(t *testing.T) {
		t.Parallel()
		got, left := swayLines([]windowrules.Rule{rule("r", windowrules.WindowEffects{Special: windowrules.Special{ID: "s"}, Maximize: true, NoScreenShare: true, NoBlur: true}, one)}, swaySupports, true)
		want := []Unwritten{{Rule: "r", Placed: []string{"special"}, Dropped: []string{"maximize", "noBlur", "noScreenShare"}}}
		if got != nil || !reflect.DeepEqual(left, want) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("supported flags don't write what sway can't", func(t *testing.T) {
		t.Parallel()
		all := supports("namedSpecial", "pin", "ruleTearing", "ruleXwayland", "ruleMaximize", "ruleNoScreenShare")
		got, left := swayLines([]windowrules.Rule{rule("r", windowrules.WindowEffects{Maximize: true, NoScreenShare: true}, one)}, all, true)
		want := []Unwritten{{Rule: "r", Dropped: []string{"maximize", "noScreenShare"}}}
		if got != nil || !reflect.DeepEqual(left, want) {
			t.Fatalf("%q %v", got, left)
		}
	})
	t.Run("file and runtime", func(t *testing.T) {
		t.Parallel()
		r := []windowrules.Rule{rule("r", windowrules.WindowEffects{Workspace: "a\\b"}, conds{cond(appID, is, `q"$`)})}
		run, _ := swayLines(r, swaySupports, true)
		file, _ := swayLines(r, swaySupports, false)
		if run[0] != `for_window [app_id="\A(?:q\x22\x24)\z"] `+SwayBindCommand(`move container to workspace "a\b"`, true) ||
			file[0] != `for_window [app_id="\\A(?:q\\x22\\x24)\\z"] move container to workspace "a\\b"` {
			t.Fatalf("%q\n%q", run[0], file[0])
		}
	})
	t.Run("example", func(t *testing.T) {
		t.Parallel()
		want := `for_window [app_id="\A(?s:.*)(?:\Asteam_app_[0-9]+\z)(?s:.*)\z"] "move container to workspace games, fullscreen enable, allow_tearing yes"
for_window [class="\A(?s:.*)(?:\Asteam_app_[0-9]+\z)(?s:.*)\z"] "move container to workspace games, fullscreen enable, allow_tearing yes"
for_window [app_id="\A(?!\A(?:(?:steam))\z)" title="\A(?:Game)\z"] "move container to workspace games, fullscreen enable, allow_tearing yes"
for_window [class="\A(?!\A(?:(?:steam))\z)" title="\A(?:Game)\z"] "move container to workspace games, fullscreen enable, allow_tearing yes"
for_window [app_id="\A(?:firefox)\z" title="\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\z"] "floating enable, resize set 640 px 360 px, sticky enable"
no_focus [app_id="\A(?:firefox)\z" title="\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\z"]
for_window [class="\A(?:firefox)\z" title="\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\z"] "floating enable, resize set 640 px 360 px, sticky enable"
no_focus [class="\A(?:firefox)\z" title="\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\z"]`
		got, left := swayLines(exampleRules(), swaySupports, true)
		if strings.Join(got, "\n") != want || left != nil {
			t.Fatalf("got\n%s\n%v", strings.Join(got, "\n"), left)
		}
		// a file's chains stay unquoted and every backslash doubles
		unquoted := strings.NewReplacer(`"move`, "move", `"floating`, "floating", `yes"`, "yes", `enable"`, "enable").Replace(want)
		file, _ := swayLines(exampleRules(), swaySupports, false)
		if strings.Join(file, "\n") != strings.ReplaceAll(unquoted, `\`, `\\`) {
			t.Fatalf("file form:\n%s", strings.Join(file, "\n"))
		}
	})
}

func TestRuleQuoting(t *testing.T) {
	t.Parallel()
	fixture := loadRegexFixture(t)
	var res []string
	for _, p := range fixture.Patterns {
		if p.Regex != "" {
			res = append(res, p.Regex)
		}
	}
	for _, n := range fixture.Negations {
		res = append(res, n.Regex)
	}
	table := []struct{ re, lua, kdl, sway, file string }{
		{`\A(?:a"b\\c)\z`, `"\\A(?:a\"b\\\\c)\\z"`, `"\\A(?:a\"b\\\\c)\\z"`, `\A(?:a\x22b\\c)\z`, `\\A(?:a\\x22b\\\\c)\\z`},
		{`\A(?:a\$b)\z`, `"\\A(?:a\\$b)\\z"`, `"\\A(?:a\\$b)\\z"`, `\A(?:a\x24b)\z`, `\\A(?:a\\x24b)\\z`},
		{`\A(?:[\$x]b)\z`, `"\\A(?:[\\$x]b)\\z"`, `"\\A(?:[\\$x]b)\\z"`, `\A(?:[\x24x]b)\z`, `\\A(?:[\\x24x]b)\\z`},
		{`\A(?:a\x0bb)\z`, `"\\A(?:a\\x0bb)\\z"`, `"\\A(?:a\\x0bb)\\z"`, `\A(?:a\x0bb)\z`, `\\A(?:a\\x0bb)\\z`},
	}
	for _, r := range table {
		if got := LuaString(r.re); got != r.lua {
			t.Errorf("LuaString(%s) = %s, want %s", r.re, got, r.lua)
		}
		if got := KdlString(r.re); got != r.kdl {
			t.Errorf("KdlString(%s) = %s, want %s", r.re, got, r.kdl)
		}
		if got := SwayCriterion(r.re); got != r.sway {
			t.Errorf("SwayCriterion(%s) = %s, want %s", r.re, got, r.sway)
		}
		if got := swayFileEscapes.Replace(SwayCriterion(r.re)); got != r.file {
			t.Errorf("file form of %s = %s, want %s", r.re, got, r.file)
		}
		res = append(res, r.re)
	}
	for _, re := range res {
		L := lua.NewState()
		if err := L.DoString("return " + LuaString(re)); err != nil || L.Get(-1).String() != re {
			t.Errorf("Lua reads %s back as %v (%v)", re, L.Get(-1), err)
		}
		L.Close()
		nodes, err := kdl.Parse(KdlSerialize(jsonx.Arr(node("n", re)), 0))
		if err != nil || len(nodes) != 1 || len(nodes[0].Args) != 1 || nodes[0].Args[0] != re {
			t.Errorf("KDL reads %s back as %v (%v)", re, nodes, err)
		}
		s := SwayCriterion(re)
		if strings.ContainsAny(s, `"$`) {
			t.Errorf("SwayCriterion(%s) = %s has a quote or a $", re, s)
		}
		if back := strings.ReplaceAll(strings.ReplaceAll(s, `\x22`, `"`), `\x24`, `\$`); back != re {
			t.Errorf("SwayCriterion(%s) = %s does not undo to the pattern", re, s)
		}
	}
}

func TestRuleEffects(t *testing.T) {
	t.Parallel()
	w := windowrules.WindowEffects{Tearing: true, Float: true, Width: 1, Height: 2, Opacity: 50}
	if got, want := RuleEffects(w), []string{"float", "size", "opacity", "tearing"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	if got := RuleEffects(windowrules.WindowEffects{}); got != nil {
		t.Fatalf("got %v", got)
	}
}

// regexFixture is tests/fixtures/windowrules/regex.json, the patterns and
// negations the compilers and their validators share
type regexFixture struct {
	Patterns []struct {
		Op, Value, Regex string
	}
	Negations []struct {
		Values []string
		Regex  string
	}
}

func loadRegexFixture(t *testing.T) regexFixture {
	t.Helper()
	var f regexFixture
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "tests/fixtures/windowrules/regex.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &f); err != nil {
		t.Fatal(err)
	}
	return f
}

// The schema greys the effects the capabilities in ruleGates gate
// (x-enabledIf, the page) on the same capability the renderers drop them for
func TestRuleGatesMatchTheSchema(t *testing.T) {
	t.Parallel()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	window := get(get(get(get(get(parsed, "definitions"), "WindowRule"), "properties"), "window"), "properties")
	if window == nil {
		t.Fatal("no WindowRule.window properties")
	}
	// A leaf's gates: the /$supports keys of its x-enabledIf
	gates := func(node any) []string {
		var out []string
		if cond, ok := get(node, "x-enabledIf").(*jsonx.Object); ok {
			for _, key := range cond.Keys() {
				if capability, found := strings.CutPrefix(key, "/$supports."); found {
					if cond.Value(key) != true {
						t.Errorf("%s: want true", key)
					}
					out = append(out, capability)
				}
			}
		}
		return out
	}
	for _, key := range window.(*jsonx.Object).Keys() {
		node := get(window, key)
		leaves := map[string]any{key: node}
		if key == "special" {
			props := get(node, "properties")
			leaves = map[string]any{"special.id": get(props, "id"), "special.silent": get(props, "silent")}
		}
		for name, leaf := range leaves {
			got := gates(leaf)
			if want, gated := ruleGates[key]; gated {
				if len(got) != 1 || got[0] != want {
					t.Errorf("%s: x-enabledIf gates on %v, ruleGates says %q", name, got, want)
				}
			} else if len(got) > 0 {
				t.Errorf("%s: x-enabledIf gates on %v, but ruleGates has no %q", name, got, key)
			}
		}
	}
}
