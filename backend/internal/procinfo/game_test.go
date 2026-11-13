package procinfo

import (
	"reflect"
	"testing"
)

func TestSignals(t *testing.T) {
	t.Parallel()
	type proc struct {
		pid, ppid int
		comm, exe string
		argv      []string
		env       []string
	}
	reaper := proc{10, 1, "reaper", "", []string{"reaper", "SteamLaunch", "--", "game"}, nil}
	reaper2 := proc{10, 9, "reaper", "", []string{"reaper", "SteamLaunch", "--", "game"}, nil}
	cases := []struct {
		name string
		tree []proc // the last is the window
		want []Signal
	}{
		{"steam game", []proc{reaper, {20, 10, "game", "", nil, nil}}, []Signal{SignalSteam}},
		{"game id 570", []proc{{20, 1, "game", "", nil, []string{"SteamAppId=570"}}}, []Signal{SignalSteam}},
		{"game id 0", []proc{{20, 1, "game", "", nil, []string{"SteamAppId=0"}}}, nil},
		{"non-steam shortcut", []proc{{20, 1, "game", "", nil, []string{"SteamAppId=0", "SteamGameId=123"}}}, []Signal{SignalSteam}},
		{"proton", []proc{reaper, {15, 10, "proton", "", nil, nil}, {20, 15, "game.exe", "wine64-preloader", nil, []string{"STEAM_COMPAT_DATA_PATH=/x"}}}, []Signal{SignalSteam, SignalProton, SignalWine}},
		{"steam's own window", []proc{{10, 1, "steam", "", []string{"steam"}, nil}, {20, 10, "steamwebhelper", "", nil, nil}}, nil},
		{"reaper alone", []proc{{10, 1, "reaper", "", []string{"reaper", "x"}, nil}, {20, 10, "game", "", nil, nil}}, nil},
		{"lutris wrapper above", []proc{{10, 1, "lutris-wrapper", "", nil, nil}, {20, 10, "game", "", nil, nil}}, []Signal{SignalLutris}},
		{"lutris ui above", []proc{{10, 1, "lutris", "", nil, nil}, {15, 10, "firefox", "", nil, nil}}, nil},
		{"wine alone", []proc{{20, 1, "notepad.exe", "wine64-preloader", nil, nil}}, nil},
		{"wine above alone", []proc{{10, 1, "x", "wine64-preloader", nil, nil}, {20, 10, "game", "", nil, nil}}, nil},
		{"wine above with launcher", []proc{{5, 1, "lutris-wrapper", "", nil, nil}, {10, 5, "x", "wine64-preloader", nil, nil}, {20, 10, "game", "", nil, nil}}, []Signal{SignalLutris, SignalWine}},
		{"wine with lutris wrapper", []proc{{10, 1, "lutris-wrapper", "", nil, nil}, {20, 10, "x", "wine", nil, nil}}, []Signal{SignalLutris, SignalWine}},
		{"gamescope with lutris wrapper", []proc{{10, 1, "lutris-wrapper", "", nil, nil}, {20, 10, "gamescope", "", nil, nil}}, []Signal{SignalLutris, SignalGamescope}},
		{"proton env alone", []proc{{20, 1, "game", "", nil, []string{"STEAM_COMPAT_DATA_PATH=/x"}}}, []Signal{SignalProton}},
		{"flatpak steam", []proc{{9, 1, "bwrap", "", []string{"bwrap", "--args"}, nil}, reaper2, {20, 10, "game", "", nil, nil}}, []Signal{SignalSteam}},
		{"lutris env", []proc{{20, 1, "game", "", nil, []string{"LUTRIS_GAME_UUID=abc"}}}, []Signal{SignalLutris}},
		{"lutris own", []proc{{20, 1, "lutris", "", nil, nil}}, nil},
		{"legendary above", []proc{{10, 1, "legendary", "", nil, nil}, {20, 10, "game", "", nil, nil}}, []Signal{SignalHeroic}},
		{"gogdl above", []proc{{10, 1, "gogdl", "", nil, nil}, {20, 10, "game", "", nil, nil}}, []Signal{SignalHeroic}},
		{"heroic env", []proc{{20, 1, "game", "", nil, []string{"HEROIC_APP_NAME=x"}}}, []Signal{SignalHeroic}},
		{"heroic ui above", []proc{{10, 1, "heroic", "", nil, nil}, {20, 10, "firefox", "", nil, nil}}, nil},
		{"heroic own", []proc{{20, 1, "heroic", "", nil, nil}}, nil},
		{"umu above", []proc{{10, 1, "umu-run", "", nil, nil}, {20, 10, "game", "", nil, nil}}, []Signal{SignalUmu}},
		{"umu env", []proc{{20, 1, "game", "", nil, []string{"UMU_ID=1"}}}, []Signal{SignalUmu}},
		{"gamescope own alone", []proc{{20, 1, "gamescope", "", nil, nil}}, nil},
		{"gamescope-wl own alone", []proc{{20, 1, "gamescope-wl", "", nil, nil}}, nil},
		{"gamescope above alone", []proc{{10, 1, "gamescope", "", nil, nil}, {20, 10, "game", "", nil, nil}}, nil},
		{"wine exe deleted alone", []proc{{20, 1, "x", "wine-preloader (deleted)", nil, nil}}, nil},
		{"env in a parent only", []proc{{10, 1, "p", "", nil, []string{"SteamAppId=570"}}, {20, 10, "game", "", nil, nil}}, nil},
		{"firefox", []proc{{10, 1, "systemd", "", nil, nil}, {20, 10, "firefox", "", nil, nil}}, nil},
	}
	for _, c := range cases {
		f := newFake(t)
		for _, p := range c.tree {
			f.add(p.pid, p.ppid, uint64(p.pid), p.comm, p.argv, p.exe, p.env...)
		}
		got, ok := f.reader().Lookup(c.tree[len(c.tree)-1].pid)
		if !ok || !reflect.DeepEqual(append([]Signal(nil), got.Signals...), c.want) {
			t.Errorf("%s: %v %v, want %v", c.name, got.Signals, ok, c.want)
		}
	}
	t.Run("foreign launcher", func(t *testing.T) {
		f := newFake(t)
		f.add(10, 1, 1, "lutris-wrapper", nil, "")
		f.add(20, 10, 2, "game", nil, "")
		f.foreign(10)
		if p, _ := f.reader().Lookup(20); len(p.Signals) != 0 {
			t.Fatal(p.Signals)
		}
	})
}

func TestDetect(t *testing.T) {
	t.Parallel()
	proc := &Process{Signals: []Signal{SignalSteam}}
	cases := []struct {
		name, app string
		p         *Process
		want      []Signal
	}{
		{"app id", "steam_app_570", nil, []Signal{SignalSteamApp}},
		{"no digits", "steam_app_", nil, nil},
		{"letters", "steam_app_57x", nil, nil},
		{"case", "Steam_app_1", nil, nil},
		{"bridge", "steam_app_570", &Process{Bridge: true, Signals: []Signal{}}, []Signal{SignalSteamApp}},
		{"order", "steam_app_1", proc, []Signal{SignalSteamApp, SignalSteam}},
		{"nothing", "firefox", &Process{Signals: []Signal{}}, nil},
	}
	for _, c := range cases {
		if got := Detect(c.app, c.p); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
}
