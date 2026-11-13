package steps

import (
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func TestV106DropsColorText(t *testing.T) {
	t.Parallel()
	runStepCases(t, 106, []stepCase{
		{"a bar widget and a custom widget",
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","colorText":true,"width":null}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","colorText":false,"popout":true}}]}}`,
			`{"Bars":{"items":[{"id":"main","left":[{"type":"Battery","id":"b","properties":{"appearance":{"style":"icon","width":null}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text","popout":true}}]}}`, true},
		{"a widget in a group",
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Clock","properties":{"appearance":{"colorText":true}}}]}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Clock","properties":{"appearance":{}}}]}}]}]}}`, true},
		{"already migrated", `{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Battery","properties":{"appearance":{"style":"icon"}}}]}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"text"}}]}}`, false},
		{"odd shapes", `{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`,
			`{"X":[{"properties":{"appearance":"colorText"}},{"properties":[1]}],"CustomWidgets":{"items":["x",{"bar":3}]}}`, false},
		{"nothing", `{"General":{}}`, `{"General":{}}`, false},
	})
}

func TestV106SystemStatsBoxes(t *testing.T) {
	t.Parallel()
	runStepCases(t, 106, []stepCase{
		{"each in a bar section",
			`{"Bars":{"items":[{"left":[{"type":"SystemStats","properties":{"boxes":"each","showCpu":true}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"SystemStats","properties":{"showCpu":true}}]}]}}`, true},
		{"one in a group",
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"SystemStats","properties":{"boxes":"one"}}]}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"SystemStats","properties":{}}]}}]}]}}`, true},
		{"other widgets keep theirs",
			`{"Bars":{"items":[{"left":[{"type":"LockKeys","properties":{"boxes":"each"}},{"type":"Privacy","properties":{"boxes":"each"}},{"type":"Markets","properties":{"boxes":"each"}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"LockKeys","properties":{"boxes":"each"}},{"type":"Privacy","properties":{"boxes":"each"}},{"type":"Markets","properties":{"boxes":"each"}}]}]}}`, false},
		{"no boxes key",
			`{"Bars":{"items":[{"left":[{"type":"SystemStats","properties":{"showCpu":true}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"SystemStats","properties":{"showCpu":true}}]}]}}`, false},
	})
}

// A config of version 104 goes through main's v105 and then v106: the
// config audit's renames and the dropped colorText compose, and a second
// run reports nothing.
func TestV105ThenV106FromV104(t *testing.T) {
	t.Parallel()
	in := `{"format":2,"version":104,"Bars":{"items":[{"id":"top","location":"left","widgets":{"left":[{"type":"Updates","properties":{"manyColor":"base08","appearance":{"style":"label","colorText":true,"width":0}}},{"type":"Workspaces","properties":{"lead":"position","textColor":"base06"}}]}}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"label","colorText":true,"width":0}}]}}`
	want := `{"format":2,"version":109,"Bars":{"items":[{"id":"top","edge":"left","widgets":{"left":[{"type":"Updates","properties":{"warnColor":"base08","appearance":{"style":"label","width":null}}},{"type":"Workspaces","properties":{"foregroundColor":"base06","leadIcon":""}}]}}]},"CustomWidgets":{"items":[{"id":"c","bar":{"style":"label","width":null}}]}}`
	v, err := jsonx.Unmarshal([]byte(in))
	if err != nil {
		t.Fatal(err)
	}
	cfg := v.(*jsonx.Object)
	changes, migrated := Migrate(cfg)
	if !migrated {
		t.Error("not migrated")
	}
	if got := string(jsonx.MarshalCompact(cfg)); got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
	joined := strings.Join(changes, "\n")
	for _, part := range []string{"location became edge", "appearance.colorText dropped"} {
		if !strings.Contains(joined, part) {
			t.Errorf("changes lack %q: %v", part, changes)
		}
	}
	if again, migrated := Migrate(cfg); migrated || len(again) > 0 {
		t.Errorf("a second run: %v (migrated %v)", again, migrated)
	}
}
