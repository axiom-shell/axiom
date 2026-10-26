package idle

import (
	"reflect"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// defaults are the schema's Idle defaults (enabled)
func defaults() Settings {
	return Settings{
		Enabled: true, DimTimeout: 150 * time.Second, DimMode: "to", DimLevel: 30, DimBy: 50,
		LockTimeout: 300 * time.Second, ScreenOffTimeout: 330 * time.Second,
		LockBeforeSleep: true, ScreenOnAfterSleep: true, RespectInhibitors: true,
	}
}

func kinds(ls []Listener) []Kind {
	var out []Kind
	for _, l := range ls {
		out = append(out, l.OnTimeout.Kind)
	}
	return out
}

func TestPlan(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		edit  func(*Settings)
		kinds []Kind
		check func(t *testing.T, ls []Listener)
	}{
		{"defaults: dim, lock, screen off; no suspend", func(*Settings) {}, []Kind{Dim, Lock, ScreenOff}, func(t *testing.T, ls []Listener) {
			if ls[0].OnTimeout != (Action{Kind: Dim, Mode: "to", Percent: 30}) || ls[0].OnResume.Kind != Undim {
				t.Errorf("dim %+v", ls[0])
			}
			if ls[2].OnResume.Kind != ScreenOn || ls[1].OnResume.Kind != None {
				t.Errorf("resumes %+v", ls)
			}
		}},
		{"dim by a share", func(s *Settings) { s.DimMode, s.DimBy = "by", 40 }, []Kind{Dim, Lock, ScreenOff}, func(t *testing.T, ls []Listener) {
			if ls[0].OnTimeout != (Action{Kind: Dim, Mode: "by", Percent: 40}) {
				t.Errorf("dim %+v", ls[0].OnTimeout)
			}
		}},
		{"every step off", func(s *Settings) { s.DimTimeout, s.LockTimeout, s.ScreenOffTimeout = 0, 0, 0 }, nil, nil},
		{"timeout order, ties in step order", func(s *Settings) {
			s.DimTimeout, s.LockTimeout, s.ScreenOffTimeout, s.SuspendTimeout = 600*time.Second, 60*time.Second, 60*time.Second, 900*time.Second
		}, []Kind{Lock, ScreenOff, Dim, Suspend}, nil},
		{"own listeners: enabled, timed and running something", func(s *Settings) {
			s.DimTimeout, s.LockTimeout, s.ScreenOffTimeout = 0, 0, 0
			s.Items = []Item{
				{Timeout: 10 * time.Second, OnTimeout: " notify-send idle ", Enabled: true},
				{Timeout: 20 * time.Second, OnTimeout: "off", Enabled: false},
				{Timeout: 30 * time.Second, OnTimeout: "  ", OnResume: "x", Enabled: true},
				{Timeout: 0, OnTimeout: "never", Enabled: true},
			}
		}, []Kind{Command}, func(t *testing.T, ls []Listener) {
			if ls[0].OnTimeout.Line != "notify-send idle" || ls[0].OnResume.Kind != None {
				t.Errorf("own %+v", ls[0])
			}
		}},
		{"own listeners come after the steps, whatever their time", func(s *Settings) {
			s.Items = []Item{{Timeout: time.Second, OnTimeout: "a", OnResume: " b ", Enabled: true}}
		}, []Kind{Dim, Lock, ScreenOff, Command}, func(t *testing.T, ls []Listener) {
			if ls[3].OnResume != (Action{Kind: Command, Line: "b"}) {
				t.Errorf("resume %+v", ls[3].OnResume)
			}
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			s := defaults()
			c.edit(&s)
			ls := Plan(s)
			if got := kinds(ls); !reflect.DeepEqual(got, c.kinds) {
				t.Errorf("got %v, want %v", got, c.kinds)
			}
			if c.check != nil && len(ls) == len(c.kinds) {
				c.check(t, ls)
			}
		})
	}
}

func TestSettingsFrom(t *testing.T) {
	t.Parallel()
	v, err := jsonx.Unmarshal([]byte(`{"enabled": true, "dim": {"timeout": 150000, "mode": "by", "level": 30, "by": 50},
		"lock": {"timeout": 300000}, "screenOff": {"timeout": 330000}, "suspend": {"timeout": 0},
		"lockBeforeSleep": true, "screenOnAfterSleep": false, "respectInhibitors": true,
		"items": [{"id": "a", "timeout": 600000, "onTimeout": "x", "onResume": "", "enabled": true}]}`))
	if err != nil {
		t.Fatal(err)
	}
	s := SettingsFrom(v.(*jsonx.Object))
	want := Settings{
		Enabled: true, DimTimeout: 150 * time.Second, DimMode: "by", DimLevel: 30, DimBy: 50,
		LockTimeout: 300 * time.Second, ScreenOffTimeout: 330 * time.Second,
		LockBeforeSleep: true, RespectInhibitors: true,
		Items: []Item{{Timeout: 600 * time.Second, OnTimeout: "x", Enabled: true}},
	}
	if !reflect.DeepEqual(s, want) {
		t.Errorf("got  %+v\nwant %+v", s, want)
	}
	if got := SettingsFrom(nil); got.Enabled {
		t.Error("no section is enabled")
	}
}
