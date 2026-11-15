package windowrules

import (
	"errors"
	"reflect"
	"testing"
)

func TestLive(t *testing.T) {
	t.Parallel()
	for f, want := range map[Field]bool{
		FieldAppID: false, FieldTitle: false, FieldProcess: true, FieldStartedFrom: true,
		FieldXwayland: false, FieldGame: true, FieldSteamGame: false, FieldApp: false,
	} {
		if got := f.Live(); got != want {
			t.Errorf("%s.Live() = %v, want %v", f, got, want)
		}
	}
	mixed := Kind{Conditions: []Condition{{FieldAppID, OpIs, "x"}, {FieldGame, OpIs, ""}}}
	if !mixed.Live() {
		t.Error("a kind mixing appId and game should be live")
	}
	a := Kind{Conditions: []Condition{{FieldAppID, OpIs, "a"}}}
	b := Kind{Conditions: []Condition{{FieldProcess, OpIs, "b"}}}
	c := Kind{Conditions: []Condition{{FieldTitle, OpIs, "c"}}}
	r := Rule{Kinds: []Kind{a, b, c}}
	if got := r.CompiledKinds(); !reflect.DeepEqual(got, []Kind{a, c}) {
		t.Errorf("CompiledKinds = %v", got)
	}
	if got := r.LiveKinds(); !reflect.DeepEqual(got, []Kind{b}) {
		t.Errorf("LiveKinds = %v", got)
	}
}

func TestLowerNoApp(t *testing.T) {
	t.Parallel()
	_, err := Lower(Kind{[]Condition{{FieldApp, OpIs, "gone.desktop"}}}, func(string) []string { return nil })
	if !errors.Is(err, ErrNoApp) {
		t.Errorf("a missing app: %v", err)
	}
	_, err = Lower(Kind{[]Condition{{FieldAppID, OpMatches, "("}}}, nil)
	if err == nil || errors.Is(err, ErrNoApp) {
		t.Errorf("a bad pattern: %v", err)
	}
}

func TestLower(t *testing.T) {
	t.Parallel()
	apps := func(id string) []string {
		switch id {
		case "ab":
			return []string{"a", "b"}
		case "y":
			return []string{"y"}
		}
		return nil
	}
	for name, tc := range map[string]struct {
		kind Kind
		want Lowered
	}{
		"steamGame": {
			Kind{[]Condition{{FieldSteamGame, OpIs, "570"}}},
			Lowered{Tests: []Test{{FieldAppID, `\A(?:steam_app_570)\z`, false}}},
		},
		"app": {
			Kind{[]Condition{{FieldApp, OpIs, "ab"}}},
			Lowered{Tests: []Test{{FieldAppID, `\A(?:(?:a)|(?:b))\z`, false}}},
		},
		"negations merge after positives": {
			Kind{[]Condition{
				{FieldAppID, OpIsNot, "x"}, {FieldTitle, OpIs, "t"},
				{FieldSteamGame, OpIsNot, "1"}, {FieldApp, OpIsNot, "y"},
			}},
			Lowered{Tests: []Test{
				{FieldTitle, `\A(?:t)\z`, false},
				{FieldAppID, `\A(?:(?:x)|(?:steam_app_1)|(?:y))\z`, true},
			}},
		},
		"title twice": {
			Kind{[]Condition{{FieldTitle, OpIsNot, "a"}, {FieldTitle, OpIsNot, "b"}}},
			Lowered{Tests: []Test{{FieldTitle, `\A(?:(?:a)|(?:b))\z`, true}}},
		},
		"flags": {
			Kind{[]Condition{{FieldXwayland, OpIs, ""}, {FieldGame, OpIsNot, ""}}},
			Lowered{Flags: []Flag{{FieldXwayland, true}, {FieldGame, false}}, Live: true},
		},
	} {
		got, err := Lower(tc.kind, apps)
		if err != nil || !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %+v, %v, want %+v", name, got, err, tc.want)
		}
	}
	app := Kind{[]Condition{{FieldApp, OpIs, "missing"}}}
	if _, err := Lower(app, apps); err == nil {
		t.Error("an unresolved app should fail")
	}
	if _, err := Lower(app, nil); err == nil {
		t.Error("a nil resolver should fail")
	}
}
