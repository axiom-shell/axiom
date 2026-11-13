package windowrules

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestTriggerOn(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		t    Trigger
		m    Moment
		want bool
	}{
		{Trigger{true, WhenOpen}, Moment{}, true},
		{Trigger{true, WhenFocused}, Moment{}, false},
		{Trigger{true, WhenFocused}, Moment{Focused: true}, true},
		{Trigger{true, WhenFocused}, Moment{Fullscreen: true}, false},
		{Trigger{true, WhenFullscreen}, Moment{Focused: true}, false},
		{Trigger{true, WhenFullscreen}, Moment{Fullscreen: true}, true},
		{Trigger{false, WhenOpen}, Moment{Focused: true, Fullscreen: true}, false},
		{Trigger{true, "never"}, Moment{Focused: true, Fullscreen: true}, false},
		{Trigger{true, ""}, Moment{Focused: true, Fullscreen: true}, false},
	} {
		if got := tc.t.On(tc.m); got != tc.want {
			t.Errorf("%+v.On(%+v) = %v, want %v", tc.t, tc.m, got, tc.want)
		}
	}
}

var open = Trigger{true, WhenOpen}

func act(id string, prio int, win, out string, m Moment, s ShellEffects) Active {
	return Active{Rule: Rule{ID: id, Shell: s}, Priority: prio, Window: win, Output: out, Moment: m}
}

func strs(s ...string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func TestHold(t *testing.T) {
	t.Parallel()
	focused := Moment{Focused: true}
	t.Run("none", func(t *testing.T) {
		t.Parallel()
		h := Hold(nil)
		b, _ := json.Marshal(h)
		if strings.Contains(string(b), "null") {
			t.Errorf("null in %s", b)
		}
		if h.PowerProfile != (ProfileHold{}) || len(h.DND) != 0 {
			t.Errorf("%+v", h)
		}
	})
	for name, tc := range map[string]struct {
		active []Active
		check  func(Holds) any
		want   any
	}{
		"dnd, priority order, once": {
			active: []Active{
				act("b", 1, "w1", "", Moment{}, ShellEffects{DND: open}),
				act("a", 0, "w1", "", Moment{}, ShellEffects{DND: open}),
				act("a", 0, "w2", "", Moment{}, ShellEffects{DND: open}),
			},
			check: func(h Holds) any { return h.DND }, want: strs("a", "b"),
		},
		"dnd focused, unfocused window": {
			active: []Active{act("a", 0, "w", "", Moment{}, ShellEffects{DND: Trigger{true, WhenFocused}})},
			check:  func(h Holds) any { return h.DND }, want: strs(),
		},
		"dnd focused, focused window": {
			active: []Active{act("a", 0, "w", "", focused, ShellEffects{DND: Trigger{true, WhenFocused}})},
			check:  func(h Holds) any { return h.DND }, want: strs("a"),
		},
		"keepAwake": {
			active: []Active{act("a", 0, "w", "", Moment{}, ShellEffects{KeepAwake: open})},
			check:  func(h Holds) any { return h.KeepAwake }, want: strs("a"),
		},
		"power profile, highest priority": {
			active: []Active{
				act("low", 3, "w", "", Moment{}, ShellEffects{PowerProfile: PowerProfile{open, "powerSaver"}}),
				act("high", 1, "w", "", Moment{}, ShellEffects{PowerProfile: PowerProfile{open, "performance"}}),
			},
			check: func(h Holds) any { return h.PowerProfile }, want: ProfileHold{"performance", "high"},
		},
		"hideFrom: union of windows, sorted, switched on places": {
			active: []Active{
				act("a", 0, "w2", "", Moment{}, ShellEffects{HideFrom: HideFrom{Trigger: open, Dock: true, Launcher: true}}),
				act("b", 1, "w1", "", Moment{}, ShellEffects{HideFrom: HideFrom{Trigger: open, Dock: true}}),
			},
			check: func(h Holds) any { return h.HideFrom },
			want:  HideFromHold{Dock: strs("w1", "w2"), Switcher: strs(), Workspaces: strs(), Launcher: strs("w2")},
		},
		"outputs, empty dropped": {
			active: []Active{
				act("a", 0, "w1", "HDMI-A-1", Moment{}, ShellEffects{HideBar: open, PauseOSD: open}),
				act("a", 0, "w2", "", Moment{}, ShellEffects{HideBar: open, PauseOSD: open}),
				act("b", 1, "w3", "DP-1", Moment{}, ShellEffects{HideBar: open}),
			},
			check: func(h Holds) any { return [][]string{h.HideBar, h.PauseOSD} },
			want:  [][]string{{"DP-1", "HDMI-A-1"}, {"HDMI-A-1"}},
		},
		"pause binds: these + these": {
			active: []Active{
				act("a", 0, "w", "", Moment{}, ShellEffects{PauseBinds: PauseBinds{open, "these", []string{"x", "y"}}}),
				act("b", 1, "w", "", Moment{}, ShellEffects{PauseBinds: PauseBinds{open, "these", []string{"y", "z"}}}),
			},
			check: func(h Holds) any { return h.PauseBinds },
			want:  BindsHold{Rules: strs("a", "b"), Keep: strs(), These: strs("x", "y", "z")},
		},
		"pause binds: all except keeps its way out": {
			active: []Active{
				act("a", 0, "w", "", focused, ShellEffects{PauseBinds: PauseBinds{Trigger{true, WhenFocused}, "allExcept", []string{"k"}}}),
				act("b", 1, "w", "", focused, ShellEffects{PauseBinds: PauseBinds{Trigger{true, WhenFocused}, "these", []string{"k", "z"}}}),
			},
			check: func(h Holds) any { return h.PauseBinds },
			want:  BindsHold{Rules: strs("a", "b"), AllExcept: true, Keep: strs("k"), These: strs("z")},
		},
		"pause binds: two all except": {
			active: []Active{
				act("a", 0, "w", "", focused, ShellEffects{PauseBinds: PauseBinds{Trigger{true, WhenFocused}, "allExcept", []string{"k1"}}}),
				act("b", 1, "w", "", focused, ShellEffects{PauseBinds: PauseBinds{Trigger{true, WhenFocused}, "allExcept", []string{"k2"}}}),
			},
			check: func(h Holds) any { return h.PauseBinds.Keep }, want: strs("k1", "k2"),
		},
		"a disabled effect adds nothing": {
			active: []Active{act("a", 0, "w", "o", focused, ShellEffects{
				DND: Trigger{false, WhenOpen}, HideBar: Trigger{false, WhenOpen},
				PauseBinds: PauseBinds{Trigger{false, WhenOpen}, "these", []string{"x"}},
			})},
			check: func(h Holds) any { return [][]string{h.DND, h.HideBar, h.PauseBinds.Rules, h.PauseBinds.These} },
			want:  [][]string{{}, {}, {}, {}},
		},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if got := tc.check(Hold(tc.active)); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
	// The result never has a null in it, whatever was held
	b, _ := json.Marshal(Hold([]Active{act("a", 0, "w", "o", focused, ShellEffects{DND: open, HideBar: open})}))
	if strings.Contains(string(b), "null") {
		t.Errorf("null in %s", b)
	}
}

func TestLookOf(t *testing.T) {
	t.Parallel()
	with := func(prio int, win string, w WindowEffects) Active {
		return Active{Rule: Rule{Window: w}, Priority: prio, Window: win}
	}
	got := LookOf([]Active{
		with(2, "w1", WindowEffects{Opacity: 40}),
		with(0, "w1", WindowEffects{Opacity: 70, NoBlur: true}),
		with(1, "w1", WindowEffects{Opacity: 50}),
		with(0, "w0", WindowEffects{NoBlur: true}),
		with(0, "w2", WindowEffects{Float: true}),
	})
	want := Look{Opacity: map[string]int{"w1": 70}, NoBlur: []string{"w0", "w1"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("LookOf = %+v, want %+v", got, want)
	}
	if empty := LookOf(nil); empty.Opacity == nil || empty.NoBlur == nil {
		t.Errorf("empty look has nil parts: %+v", empty)
	}
}

func TestOverrides(t *testing.T) {
	t.Parallel()
	dnd := Holds{DND: []string{"a"}}
	power := Holds{PowerProfile: ProfileHold{Profile: "performance", Rule: "a"}}
	for _, c := range []struct {
		name   string
		effect string
		h      Holds
		want   bool
		got    Overrides
	}{
		{"dnd held", "dnd", dnd, true, Overrides{DND: true}},
		{"dnd not held", "dnd", Holds{}, false, Overrides{}},
		{"power held", "powerProfile", power, true, Overrides{PowerProfile: true}},
		{"power not held", "powerProfile", dnd, false, Overrides{}},
		{"unknown", "keepAwake", Holds{KeepAwake: []string{"a"}}, false, Overrides{}},
	} {
		var o Overrides
		if ok := o.Override(c.effect, c.h); ok != c.want || o != c.got {
			t.Errorf("%s: %v %+v", c.name, ok, o)
		}
	}
}

func TestSettle(t *testing.T) {
	t.Parallel()
	both := Overrides{DND: true, PowerProfile: true}
	p := func(profile, rule string) Holds {
		return Holds{DND: []string{"a"}, PowerProfile: ProfileHold{Profile: profile, Rule: rule}}
	}
	for _, c := range []struct {
		name      string
		prev, now Holds
		want      Overrides
	}{
		{"nothing changed", p("performance", "a"), p("performance", "a"), both},
		{"another rule still holds dnd", Holds{DND: []string{"a", "b"}}, Holds{DND: []string{"b"}}, both},
		{"dnd ends", p("performance", "a"), Holds{PowerProfile: ProfileHold{Profile: "performance", Rule: "a"}}, Overrides{PowerProfile: true}},
		{"another profile", p("performance", "a"), p("power-saver", "a"), Overrides{DND: true}},
		{"another rule", p("performance", "a"), p("performance", "b"), Overrides{DND: true}},
		{"power ends", p("performance", "a"), Holds{DND: []string{"a"}}, Overrides{DND: true}},
	} {
		if got := both.Settle(c.prev, c.now); got != c.want {
			t.Errorf("%s: %+v, want %+v", c.name, got, c.want)
		}
	}
	b, _ := json.Marshal(both)
	if string(b) != `{"dnd":true,"powerProfile":true}` {
		t.Errorf("json %s", b)
	}
}

func TestPause(t *testing.T) {
	t.Parallel()
	bound := strs("a", "b", "c", "d")
	for name, tc := range map[string]struct {
		hold BindsHold
		want Pause
	}{
		"zero":       {BindsHold{}, Pause{Keep: strs(), Paused: strs()}},
		"these":      {BindsHold{Rules: strs("r"), These: strs("d", "x", "b")}, Pause{Keep: strs(), Paused: strs("b", "d")}},
		"all except": {BindsHold{Rules: strs("r"), AllExcept: true, Keep: strs("c", "x")}, Pause{AllExcept: true, Keep: strs("c"), Paused: strs("a", "b", "d")}},
	} {
		got := tc.hold.Pause(bound)
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %+v, want %+v", name, got, tc.want)
		}
		if b, _ := json.Marshal(got); strings.Contains(string(b), "null") {
			t.Errorf("%s: null in %s", name, b)
		}
	}
}
