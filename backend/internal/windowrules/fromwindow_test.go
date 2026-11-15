package windowrules

import (
	"reflect"
	"testing"
)

func TestKindFor(t *testing.T) {
	t.Parallel()
	proc := &ProcessFacts{Name: "steam"}
	for name, tc := range map[string]struct {
		f    Facts
		want Condition
	}{
		"app id":                  {Facts{AppID: "foot", Title: "t", Process: proc}, Condition{FieldAppID, OpIs, "foot"}},
		"steam game":              {Facts{AppID: "steam_app_570"}, Condition{FieldSteamGame, OpIs, "570"}},
		"steam_app_ not a number": {Facts{AppID: "steam_app_x"}, Condition{FieldAppID, OpIs, "steam_app_x"}},
		"steam_app_ alone":        {Facts{AppID: "steam_app_"}, Condition{FieldAppID, OpIs, "steam_app_"}},
		"process":                 {Facts{Title: "t", Process: proc}, Condition{FieldProcess, OpIs, "steam"}},
		"title":                   {Facts{Title: "t"}, Condition{FieldTitle, OpIs, "t"}},
		"nothing":                 {Facts{}, Condition{FieldAppID, OpIs, ""}},
		"regex characters":        {Facts{AppID: "a.b(c)"}, Condition{FieldAppID, OpIs, "a.b(c)"}},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if got := KindFor(tc.f); !reflect.DeepEqual(got, Kind{Conditions: []Condition{tc.want}}) {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
	// An `is` value stays literal: the pattern quotes it
	re, err := KindFor(Facts{AppID: "a.b"}).Conditions[0].Regex()
	if err != nil || re != `\A(?:`+Literal("a.b")+`)\z` {
		t.Errorf("regex %q, %v", re, err)
	}
}
