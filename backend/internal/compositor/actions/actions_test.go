package actions

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func table(t *testing.T) *Table {
	t.Helper()
	tab, err := parse()
	if err != nil {
		t.Fatal(err)
	}
	return tab
}

// The commands that call axiom: the binary's (`axiom ipc`, `axiom lock`,
// `axiom restart`), not qs's from before it
func TestIPCAction(t *testing.T) {
	t.Parallel()
	tab := table(t)
	cases := map[string]string{
		"axiom ipc appLauncher toggle":            `{"action":"launcher","call":"toggle"}`,
		"'/usr/bin/axiom' ipc appLauncher toggle": `{"action":"launcher","call":"toggle"}`,
		"axiom ipc overlay hide":                  `{"action":"overlay","call":"close"}`,
		"axiom ipc workspaces nth 3 go":           `{"action":"workspaceNth","argument":"3"}`,
		"axiom ipc edgeMenu show 'left'":          `{"action":"edgeMenu","call":"open","argument":"left"}`,
		"qs -c axiom ipc call appLauncher toggle": "null",
		"axiom lock":                             `{"action":"lock"}`,
		"axiom ipc lockscreen lock":              `{"action":"lock"}`,
		"'/usr/bin/axiom' restart":               `{"action":"restartShell"}`,
		"axiom run":                              "null",
		"axiomatic ipc appLauncher toggle":       "null",
		"axiom ipc somethingNew it":              "null",
		"axiom ipc wifi enable":                  `{"action":"wifi","call":"open"}`,
		"axiom ipc darkMode disable":             `{"action":"darkMode","call":"close"}`,
		"axiom ipc workspaceOverlay show":        `{"action":"workspaceOverview","call":"open"}`,
		"axiom ipc stopwatch timer 10m":          `{"action":"timerStart","argument":"10m"}`,
		"axiom ipc appLauncher clipboard":        `{"action":"clipboard"}`,
		"axiom ipc edgeMenu pin left":            "null",
		"axiom ipc nightLight status":            "null",
		"axiom ipc stopwatch timer '10m tea'":    `{"action":"timerStart","argument":"10m tea"}`,
		`axiom ipc appLauncher search "foo bar"`: `{"action":"launcherSearch","argument":"foo bar"}`,
	}
	for command, want := range cases {
		got := "null"
		if entry := tab.IPCAction(command); entry != nil {
			got = string(jsonx.MarshalCompact(entry))
		}
		if got != want {
			t.Errorf("%q: got %s, want %s", command, got, want)
		}
	}
	if !tab.Repeating["volumeUp"] || tab.Repeating["toggleMute"] {
		t.Errorf("repeating: %v", tab.Repeating)
	}
}

func TestMediaAction(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+":         "volumeUp",
		"wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 0.1-": "volumeDown",
		"wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0": "volumeUp",
		"wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle":        "toggleMute",
		"wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle":      "toggleMicMute",
		"pactl set-sink-volume @DEFAULT_SINK@ +5%":          "volumeUp",
		"pactl set-sink-volume @DEFAULT_SINK@ -5%":          "volumeDown",
		"pactl set-source-mute @DEFAULT_SOURCE@ toggle":     "toggleMicMute",
		"brightnessctl -e4 -n2 set 5%+":                     "brightnessUp",
		"brightnessctl set +10%":                            "brightnessUp",
		"brightnessctl set 5%-":                             "brightnessDown",
		"playerctl play-pause":                              "mediaPlayPause",
		"playerctl   next":                                  "mediaNext",
		"wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%":         "",
		"foot": "",
		"":     "",
	}
	for command, want := range cases {
		if got := MediaAction(command); got != want {
			t.Errorf("%q: got %q, want %q", command, got, want)
		}
	}
}
