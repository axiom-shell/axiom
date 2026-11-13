package windowrules

import (
	"reflect"
	"testing"
)

func cond(f Field, op Op, v string) Condition { return Condition{Field: f, Op: op, Value: v} }

func kind(cs ...Condition) Kind { return Kind{Conditions: cs} }

func TestMatch(t *testing.T) {
	t.Parallel()
	apps := func(id string) []string {
		if id == "org.gnome.Calculator.desktop" {
			return []string{"org.gnome.Calculator"}
		}
		return nil
	}
	known := &ProcessFacts{Name: "steam", Ancestors: []string{"bash", "kitty"}}
	for name, tc := range map[string]struct {
		kinds    []Kind
		xwayland bool // what the compositor can tell
		f        Facts
		want     []int
	}{
		"appId is":             {kinds: []Kind{kind(cond(FieldAppID, OpIs, "foot"))}, xwayland: true, f: Facts{AppID: "foot"}, want: []int{0}},
		"appId is, other":      {kinds: []Kind{kind(cond(FieldAppID, OpIs, "foot"))}, f: Facts{AppID: "foot2"}},
		"appId contains":       {kinds: []Kind{kind(cond(FieldAppID, OpContains, "oo"))}, f: Facts{AppID: "foot"}, want: []int{0}},
		"appId matches":        {kinds: []Kind{kind(cond(FieldAppID, OpMatches, "^f.*t$"))}, f: Facts{AppID: "foot"}, want: []int{0}},
		"appId matches, miss":  {kinds: []Kind{kind(cond(FieldAppID, OpMatches, "^x"))}, f: Facts{AppID: "foot"}},
		"appId isn't":          {kinds: []Kind{kind(cond(FieldAppID, OpIsNot, "foot"))}, f: Facts{AppID: "kitty"}, want: []int{0}},
		"appId isn't, is":      {kinds: []Kind{kind(cond(FieldAppID, OpIsNot, "foot"))}, f: Facts{AppID: "foot"}},
		"title contains":       {kinds: []Kind{kind(cond(FieldTitle, OpContains, "Mozilla"))}, f: Facts{Title: "Home - Mozilla Firefox"}, want: []int{0}},
		"title is, miss":       {kinds: []Kind{kind(cond(FieldTitle, OpIs, "Mozilla"))}, f: Facts{Title: "Home - Mozilla Firefox"}},
		"two kinds, second":    {kinds: []Kind{kind(cond(FieldAppID, OpIs, "a")), kind(cond(FieldTitle, OpIs, "t"))}, f: Facts{AppID: "b", Title: "t"}, want: []int{0}},
		"one kind, both parts": {kinds: []Kind{kind(cond(FieldAppID, OpIs, "a"), cond(FieldTitle, OpIs, "t"))}, f: Facts{AppID: "a", Title: "u"}},
		"process is":           {kinds: []Kind{kind(cond(FieldProcess, OpIs, "steam"))}, f: Facts{Process: known}, want: []int{0}},
		"process is, unknown":  {kinds: []Kind{kind(cond(FieldProcess, OpIs, "steam"))}, f: Facts{}},
		"process isn't, known": {kinds: []Kind{kind(cond(FieldProcess, OpIsNot, "firefox"))}, f: Facts{Process: known}, want: []int{0}},
		"process isn't, unknown (Q1-A)": {
			kinds: []Kind{kind(cond(FieldProcess, OpIsNot, "firefox"))}, f: Facts{AppID: "x"}},
		"startedFrom any":            {kinds: []Kind{kind(cond(FieldStartedFrom, OpIs, "kitty"))}, f: Facts{Process: known}, want: []int{0}},
		"startedFrom, none":          {kinds: []Kind{kind(cond(FieldStartedFrom, OpIs, "zsh"))}, f: Facts{Process: known}},
		"startedFrom isn't, none":    {kinds: []Kind{kind(cond(FieldStartedFrom, OpIsNot, "zsh"))}, f: Facts{Process: known}, want: []int{0}},
		"startedFrom isn't, one":     {kinds: []Kind{kind(cond(FieldStartedFrom, OpIsNot, "kitty"))}, f: Facts{Process: known}},
		"startedFrom isn't, unknown": {kinds: []Kind{kind(cond(FieldStartedFrom, OpIsNot, "kitty"))}, f: Facts{}},
		"startedFrom, unknown":       {kinds: []Kind{kind(cond(FieldStartedFrom, OpIs, "kitty"))}, f: Facts{}},
		"xwayland is":                {kinds: []Kind{kind(cond(FieldXwayland, OpIs, ""))}, xwayland: true, f: Facts{XWayland: true}, want: []int{0}},
		"xwayland is, native":        {kinds: []Kind{kind(cond(FieldXwayland, OpIs, ""))}, xwayland: true, f: Facts{}},
		"xwayland isn't":             {kinds: []Kind{kind(cond(FieldXwayland, OpIsNot, ""))}, xwayland: true, f: Facts{}, want: []int{0}},
		"xwayland isn't, x11":        {kinds: []Kind{kind(cond(FieldXwayland, OpIsNot, ""))}, xwayland: true, f: Facts{XWayland: true}},
		"xwayland unknown, is":       {kinds: []Kind{kind(cond(FieldXwayland, OpIs, ""))}, f: Facts{XWayland: true}},
		"xwayland unknown, isn't":    {kinds: []Kind{kind(cond(FieldXwayland, OpIsNot, ""))}, f: Facts{}},
		"game is":                    {kinds: []Kind{kind(cond(FieldGame, OpIs, ""))}, f: Facts{Game: true}, want: []int{0}},
		"game is, not":               {kinds: []Kind{kind(cond(FieldGame, OpIs, ""))}, f: Facts{}},
		"game isn't":                 {kinds: []Kind{kind(cond(FieldGame, OpIsNot, ""))}, f: Facts{}, want: []int{0}},
		"game isn't, game":           {kinds: []Kind{kind(cond(FieldGame, OpIsNot, ""))}, f: Facts{Game: true}},
		"steamGame":                  {kinds: []Kind{kind(cond(FieldSteamGame, OpIs, "570"))}, f: Facts{AppID: "steam_app_570"}, want: []int{0}},
		"steamGame, other":           {kinds: []Kind{kind(cond(FieldSteamGame, OpIs, "570"))}, f: Facts{AppID: "steam_app_5700"}},
		"app":                        {kinds: []Kind{kind(cond(FieldApp, OpIs, "org.gnome.Calculator.desktop"))}, f: Facts{AppID: "org.gnome.Calculator"}, want: []int{0}},
		"app, not installed": {
			kinds: []Kind{kind(cond(FieldApp, OpIs, "gone.desktop")), kind(cond(FieldAppID, OpIs, "x"))},
			f:     Facts{AppID: "x"}, want: []int{0}},
		"app, not installed alone": {kinds: []Kind{kind(cond(FieldApp, OpIs, "gone.desktop"))}, f: Facts{AppID: "gone"}},
		"bad pattern, hand-built":  {kinds: []Kind{kind(cond(FieldAppID, OpMatches, "("))}, f: Facts{AppID: "("}},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			m := NewMatcher([]Rule{{ID: "r", Kinds: tc.kinds}}, apps, tc.xwayland)
			if got := m.Match(tc.f); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("Match = %v, want %v", got, tc.want)
			}
		})
	}
	// With no resolver an app kind matches nothing, the rule's other kind still does
	m := NewMatcher([]Rule{{Kinds: []Kind{kind(cond(FieldApp, OpIs, "a.desktop")), kind(cond(FieldAppID, OpIs, "x"))}}}, nil, true)
	if got := m.Match(Facts{AppID: "a"}); got != nil {
		t.Errorf("app with nil AppIDs matched: %v", got)
	}
	if got := m.Match(Facts{AppID: "x"}); !reflect.DeepEqual(got, []int{0}) {
		t.Errorf("the other kind: %v", got)
	}
	// Indices follow the rules' order
	m = NewMatcher([]Rule{
		{Kinds: []Kind{kind(cond(FieldAppID, OpIs, "a"))}},
		{Kinds: []Kind{kind(cond(FieldAppID, OpIs, "b"))}},
		{Kinds: []Kind{kind(cond(FieldAppID, OpContains, "a"))}},
	}, nil, true)
	if got := m.Match(Facts{AppID: "a"}); !reflect.DeepEqual(got, []int{0, 2}) {
		t.Errorf("indices = %v", got)
	}
}
