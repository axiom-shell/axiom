package windowrules

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func switchesOn(steam, games bool) Switches {
	return Switches{SteamFloat: steam, GamesSpecial: GamesSpecial{Enabled: games, Special: Special{ID: "x", Silent: true}}}
}

func ids(rules []Rule) []string {
	out := []string{}
	for _, r := range rules {
		out = append(out, r.ID)
	}
	return out
}

func TestBuiltins(t *testing.T) {
	t.Parallel()
	missing := []Issue{{Path: "switches.gamesSpecial.special.id", Code: "specialMissing"}}
	for name, tc := range map[string]struct {
		s      Switches
		issues []Issue
		want   []string
	}{
		"none on":              {switchesOn(false, false), nil, []string{}},
		"steam":                {switchesOn(true, false), nil, []string{"_steamFloat"}},
		"games":                {switchesOn(false, true), nil, []string{"_gamesSpecial"}},
		"both, table order":    {switchesOn(true, true), nil, []string{"_steamFloat", "_gamesSpecial"}},
		"games with an issue":  {switchesOn(true, true), missing, []string{"_steamFloat"}},
		"a user rule's issues": {switchesOn(true, false), []Issue{{Rule: "a", Path: "id"}}, []string{"_steamFloat"}},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if got := ids(Builtins(tc.s, tc.issues)); !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
	steam := Builtins(switchesOn(true, false), nil)[0]
	if !steam.Enabled || !steam.Window.Float || steam.Name != "Float Steam's small windows" || len(steam.Kinds) != 1 || len(steam.Kinds[0].Conditions) != 4 {
		t.Errorf("steam rule %+v", steam)
	}
	games := Builtins(switchesOn(false, true), nil)[0]
	if games.Window.Special != (Special{ID: "x", Silent: true}) || len(games.Kinds) != 2 ||
		games.Kinds[0].Conditions[0].Field != FieldAppID || games.Kinds[0].Conditions[0].Op != OpMatches ||
		games.Kinds[1].Conditions[0].Field != FieldGame || games.Kinds[1].Conditions[0].Op != OpIs {
		t.Errorf("games rule %+v", games)
	}
}

func TestBuiltinsAreValid(t *testing.T) {
	t.Parallel()
	s := switchesOn(true, true)
	s.GamesSpecial.Special = Special{ID: "games"}
	rules := Builtins(s, nil)
	if len(rules) != 2 {
		t.Fatalf("rules %v", ids(rules))
	}
	// The reserved ids are no rule of the user's: check the rules under others
	renamed := append([]Rule(nil), rules...)
	for i := range renamed {
		renamed[i].ID = "r" + string(rune('a'+i))
	}
	if issues := Validate(Config{Rules: renamed}, Context{}); len(issues) != 0 {
		t.Errorf("issues %+v", issues)
	}
	for _, r := range rules {
		for ki, k := range r.Kinds {
			if _, err := Lower(k, nil); err != nil {
				t.Errorf("%s kind %d: %v", r.ID, ki, err)
			}
			if live := r.ID == "_gamesSpecial" && ki == 1; k.Live() != live {
				t.Errorf("%s kind %d: live %v", r.ID, ki, k.Live())
			}
		}
	}
}

func TestBuiltinRule(t *testing.T) {
	t.Parallel()
	s := switchesOn(true, true)
	for _, key := range []string{"steamFloat", "gamesSpecial"} {
		o, ok := BuiltinRule(key, s)
		if !ok {
			t.Fatalf("%s: no rule", key)
		}
		o.Set("id", "copy")
		got := parseRule(o)
		var want Rule
		for _, b := range Builtins(s, nil) {
			if b.ID == "_"+key {
				want = b
			}
		}
		if !reflect.DeepEqual(got.Kinds, want.Kinds) || got.Window != want.Window || got.Icon == "" {
			t.Errorf("%s: copy %+v, switch %+v", key, got, want)
		}
		again, _ := BuiltinRule(key, s)
		if again == o || jsonx.Equal(again, o) {
			t.Errorf("%s: a shared or mutated tree", key)
		}
	}
	if _, ok := BuiltinRule("x", s); ok {
		t.Error("unknown key found")
	}
}

func TestEffective(t *testing.T) {
	t.Parallel()
	good := func(id string) Rule {
		return Rule{ID: id, Enabled: true, Kinds: []Kind{kind(cond(FieldAppID, OpIs, id))}}
	}
	off := good("off")
	off.Enabled = false
	bad := good("bad")
	c := Config{Rules: []Rule{good("a"), off, bad, good("b")}, Switches: switchesOn(true, true)}
	issues := []Issue{{Rule: "bad", Path: "windows"}}
	want := []string{"a", "b", "_steamFloat", "_gamesSpecial"}
	if got := ids(Effective(c, issues)); !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestSteamFloatMatches(t *testing.T) {
	t.Parallel()
	m := NewMatcher(Builtins(switchesOn(true, false), nil), nil, true)
	for name, tc := range map[string]struct {
		f    Facts
		want []int
	}{
		"friends":     {Facts{AppID: "steam", Title: "Friends List"}, []int{0}},
		"settings":    {Facts{AppID: "steam", Title: "Steam Settings"}, []int{0}},
		"main":        {Facts{AppID: "steam", Title: "Steam"}, nil},
		"big picture": {Facts{AppID: "steam", Title: "Steam Big Picture Mode"}, nil},
		"no title":    {Facts{AppID: "steam"}, nil},
		"web helper":  {Facts{AppID: "steamwebhelper", Title: "Friends List"}, nil},
		"other app":   {Facts{AppID: "foot", Title: "Friends List"}, nil},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if got := m.Match(tc.f); !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}
