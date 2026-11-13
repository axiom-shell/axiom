package windowrules

import (
	"reflect"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

var realSchema = sync.OnceValues(func() (*schema.Schema, error) {
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		return nil, err
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		return nil, err
	}
	return schema.New(parsed), nil
})

// section fills a partial WindowRules section with the real schema's defaults.
func section(t *testing.T, partial string) (any, *schema.Schema, any) {
	t.Helper()
	s, err := realSchema()
	if err != nil {
		t.Fatal(err)
	}
	props, _ := s.Root().(*jsonx.Object).Value("properties").(*jsonx.Object)
	node := props.Value("WindowRules")
	v, err := jsonx.Unmarshal([]byte(partial))
	if err != nil {
		t.Fatal(err)
	}
	filled, _ := config.ApplyDefaults(s, v, true, node)
	return filled, s, node
}

func TestParse(t *testing.T) {
	t.Parallel()
	empty, _, _ := section(t, `{}`)
	want := Config{}
	want.Switches.GamesSpecial.Special.ID = "games"
	if got := Parse(empty); !reflect.DeepEqual(got, want) {
		t.Errorf("defaults: got %+v, want %+v", got, want)
	}

	full, s, node := section(t, `{"rules": [{
		"id": "r1", "name": "N", "icon": "star", "enabled": false,
		"windows": [{"conditions": [{"field": "title", "op": "contains", "value": "v"}]}, {"conditions": []}],
		"window": {"float": true, "size": {"width": 800, "height": 600}, "center": true, "workspace": "3", "follow": true,
			"special": {"id": "sp", "silent": true}, "monitor": "DP-1", "fullscreen": true, "maximize": true,
			"pin": true, "opacity": 50, "noBlur": true, "noFocus": true, "noScreenShare": true, "tearing": true},
		"shell": {
			"dnd": {"enabled": true, "when": "fullscreen"},
			"keepAwake": {"enabled": true, "when": "focused"},
			"powerProfile": {"enabled": true, "profile": "powerSaver", "when": "focused"},
			"hideFrom": {"enabled": true, "dock": true, "switcher": true, "workspaces": true, "launcher": true, "when": "fullscreen"},
			"pauseBinds": {"enabled": true, "mode": "allExcept", "binds": ["a", "b"], "when": "fullscreen"},
			"pauseOsd": {"enabled": true, "when": "open"},
			"hideBar": {"enabled": true, "when": "open"}}}],
		"switches": {"steamFloat": true, "gamesSpecial": {"enabled": true, "special": {"id": "g", "silent": true}}}}`)
	if errs := config.ValidationErrors(s, full, node); len(errs) > 0 {
		t.Fatalf("the section doesn't validate: %v", errs)
	}
	wantFull := Config{
		Rules: []Rule{{
			ID: "r1", Name: "N", Icon: "star", Enabled: false,
			Kinds: []Kind{{Conditions: []Condition{{FieldTitle, OpContains, "v"}}}, {}},
			Window: WindowEffects{
				Float: true, Width: 800, Height: 600, Center: true, Workspace: "3", Follow: true,
				Special: Special{"sp", true}, Monitor: "DP-1", Fullscreen: true, Maximize: true,
				Pin: true, Opacity: 50, NoBlur: true, NoFocus: true, NoScreenShare: true, Tearing: true,
			},
			Shell: ShellEffects{
				DND:          Trigger{true, WhenFullscreen},
				KeepAwake:    Trigger{true, WhenFocused},
				PowerProfile: PowerProfile{Trigger{true, WhenFocused}, "powerSaver"},
				HideFrom:     HideFrom{Trigger{true, WhenFullscreen}, true, true, true, true},
				PauseBinds:   PauseBinds{Trigger{true, WhenFullscreen}, "allExcept", []string{"a", "b"}},
				PauseOSD:     Trigger{true, WhenOpen},
				HideBar:      Trigger{true, WhenOpen},
			},
		}},
		Switches: Switches{SteamFloat: true, GamesSpecial: GamesSpecial{true, Special{"g", true}}},
	}
	if got := Parse(full); !reflect.DeepEqual(got, wantFull) {
		t.Errorf("full: got\n%+v\nwant\n%+v", got, wantFull)
	}
}

func TestContextOf(t *testing.T) {
	t.Parallel()
	kb, err := jsonx.Unmarshal([]byte(`{"binds": [{"id": "a", "key": "x"}, 5, {"key": "x"}, {"id": "b", "key": "y", "paused": true}, {"id": "c", "key": ""}]}`))
	if err != nil {
		t.Fatal(err)
	}
	want := Context{BindIDs: []string{"a", "b", "c"}, Unbound: []string{"b", "c"}}
	if got := ContextOf(kb); !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v", got)
	}
	if got := ContextOf(nil); got.BindIDs != nil || got.Unbound != nil {
		t.Errorf("nil: got %+v", got)
	}
}
