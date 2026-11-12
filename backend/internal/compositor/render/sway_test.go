package render

import (
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A user's floating_modifier holds its mod's mouse buttons, so axiom's drag
// and resize binds on them are skipped, and taking axiom's back puts the
// user's (or sway's none) back.
func TestSwayFloatingModifier(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	drag := func(mod string) *jsonx.Array {
		return jsonx.Arr(jsonx.Obj("key", mod+" + mouse:272", "action", "mouseDrag"),
			jsonx.Obj("key", mod+" + mouse:273", "action", "mouseResize"))
	}
	cases := []struct {
		name, config, mod string
		skipped           int
		restore           string
	}{
		{"none of the user's", "bindsym Mod4+Return exec foot", "SUPER", 0, "floating_modifier none"},
		{"same mod", "set $mod Mod4\nfloating_modifier $mod normal", "SUPER", 2, ""},
		{"another mod", "floating_modifier Mod1 inverse", "SUPER", 0, "floating_modifier Mod1 inverse"},
		{"the last line", "floating_modifier Mod1\nfloating_modifier Mod5 normal", "SUPER", 0, "floating_modifier Mod5 normal"},
		{"turned off", "floating_modifier none", "SUPER", 0, "floating_modifier none"},
		{"in a mode", "mode resize {\n floating_modifier Mod4\n}", "SUPER", 0, "floating_modifier none"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			entries := SwayConfigBinds(c.config)
			plan := RuntimeBinds(drag(c.mod), entries)
			if got := len(items(plan.Value("skipped"))); got != c.skipped {
				t.Fatalf("skipped %d, want %d", got, c.skipped)
			}
			unbind := tab.SwayUnbindLines(plan.Value("apply"), nil, entries)
			last := ""
			if len(unbind) > 0 && !slices.Contains([]string{"unbindsym", "unbindcode"}, firstWord.FindString(unbind[len(unbind)-1])) {
				last = unbind[len(unbind)-1]
			}
			if last != c.restore {
				t.Errorf("unbind ends %q, want %q (%q)", last, c.restore, unbind)
			}
		})
	}
}

// user/'s include in the managed and released configs: only the folder
// quoted, so a space in it splits nothing and the glob still expands
func TestSwayUserIncludeQuotesOnlyTheFolder(t *testing.T) {
	t.Parallel()
	want := "\ninclude \"/my home/.config/sway/user/\"*\n"
	for name, text := range map[string]string{
		"managed":  SwayManagedText("", jsonx.Obj("userDir", "/my home/.config/sway/user")),
		"released": SwayReleasedText("/my home/.config/sway/user", "exec axiom run"),
	} {
		if !strings.Contains(text, want) {
			t.Errorf("%s: no %q in\n%s", name, want, text)
		}
	}
	if got := SwayIncludePath("/plain/user", "*"); got != "/plain/user/*" {
		t.Errorf("a plain folder: %s", got)
	}
}

// A bind's argument goes into its IPC call as written: a $' or $& in it is
// no replacement pattern, on sway and Hyprland alike
func TestBindArgumentIsLiteral(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	bind := jsonx.Obj("key", "SUPER + S", "action", "launcherSearch", "argument", "US$'s $& rate")
	ctx := jsonx.Obj("shellCommand", "axiom")
	want := `axiom ipc appLauncher search 'US$'\''s $& rate'`
	if got := tab.SwayCommand(bind, ctx); got != swayExec(want) {
		t.Errorf("sway: %s", got)
	}
	if got := tab.BindLua(bind, ctx); !strings.Contains(got, LuaString(want)) {
		t.Errorf("hyprland: %s", got)
	}
	if got := tab.DefaultLabel(bind); got != "Launcher: US$'s $& rate" {
		t.Errorf("label: %s", got)
	}
}

// sway's outer gaps add to the inner ones: outer - inner leaves the edge
// at the outer gap, negative where the inner gaps are wider.
func TestSwayLookGapsEdge(t *testing.T) {
	t.Parallel()
	look := jsonx.Obj("gaps", jsonx.Obj("inner", float64(10), "outer", float64(4)))
	got := strings.Join(SwayLookLines(look, true), "; ")
	if want := "gaps inner 10; gaps outer -6; gaps inner all set 10; gaps outer all set -6"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// SwayUnbinds are SwayUnbindLines' lines, each with the key it frees.
func TestSwayUnbindsMatchUnbindLines(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	ctx := jsonx.Obj("shellCommand", "axiom")
	binds := jsonx.Arr(
		jsonx.Obj("key", "SUPER + S", "action", "launcherSearch", "argument", "x"),
		jsonx.Obj("key", "SUPER + Return", "action", "closeWindow"),
		jsonx.Obj("key", "SUPER + D", "action", "closeWindow", "release", true),
		jsonx.Obj("key", "SUPER + mouse:272", "action", "mouseDrag"),
		jsonx.Obj("key", "SUPER + mouse:273", "action", "mouseResize"),
	)
	entries := SwayConfigBinds("floating_modifier Mod1 inverse")
	got := tab.SwayUnbinds(binds, ctx, entries)
	lines := tab.SwayUnbindLines(binds, ctx, entries)
	if len(got) != len(lines) || len(got) < 5 {
		t.Fatalf("%d unbinds, %d lines: %v", len(got), len(lines), got)
	}
	keys := map[string]bool{}
	for _, b := range binds.Items {
		keys[KeyID(get(b, "key"))] = true
	}
	for i, u := range got {
		if u.Line != lines[i] {
			t.Errorf("line %d = %q, want %q", i, u.Line, lines[i])
		}
		if i < len(got)-1 && !keys[u.Key] {
			t.Errorf("%q frees key %q, not one of the binds'", u.Line, u.Key)
		}
	}
	if last := got[len(got)-1]; last.Key != "" || last.Line != "floating_modifier Mod1 inverse" {
		t.Errorf("last = %+v, want the floating restore", last)
	}
}

func TestSwayFloatingRestore(t *testing.T) {
	t.Parallel()
	if got := SwayFloatingRestore(SwayConfigBinds("bindsym Mod4+x exec true")); got != "floating_modifier none" {
		t.Errorf("none: %q", got)
	}
	if got := SwayFloatingRestore(SwayConfigBinds("floating_modifier Mod1\nfloating_modifier Mod5 normal")); got != "floating_modifier Mod5 normal" {
		t.Errorf("last wins: %q", got)
	}
}
