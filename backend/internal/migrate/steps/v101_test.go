package steps

import (
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The old default parts (v100's OSDEntry defaults), written out
const (
	v101OldBars     = `{"items":[{"type":"other","icon":"music_note","showOsd":true},{"type":"master","icon":"","showOsd":true}]}`
	v101OldStatuses = `{"row":"notable","items":["capsLock","numLock","keyboardLayout","microphone","audio","dnd","caffeine","nightLight","recording","drive"],"quiet":[]}`
	v101OldAudio    = `{"type":"Audio","bars":[{"type":"other","icon":"music_note","showOsd":true},{"type":"master","icon":"","showOsd":true}]`
)

func TestV101MakesTheOSDsPartsOneListOfSystems(t *testing.T) {
	t.Parallel()
	runStepCases(t, 101, []stepCase{
		{"the default, written out, becomes the new default",
			`{"OSD":{"items":[{"id":"main","bars":` + v101OldBars + `,"statuses":` + v101OldStatuses + `,"cards":{"enabled":true,"timeout":4000,"items":["message"]}}]}}`,
			`{"OSD":{"items":[{"id":"main","row":"notable","cardsEnabled":true,"cardTimeout":4000,"systems":[` + v101OldAudio + `,"tiles":["audio","microphone"]},{"type":"LockKeys","keys":["capsLock","numLock"]},{"type":"KeyboardLayout"},{"type":"Dnd"},{"type":"Caffeine"},{"type":"NightLight"},{"type":"Recording"},{"type":"Drives"},{"type":"Message"}]}]}}`, true},
		{"the default left to the defaults stays so",
			`{"OSD":{"items":[{"id":"main","screen":{"mode":"inherit"}}]}}`,
			`{"OSD":{"items":[{"id":"main","screen":{"mode":"inherit"}}]}}`, false},
		{"a custom OSD: layout, interleaved bars, subsets, quiet, cards, unknown types",
			`{"OSD":{"items":[{"id":"b","edge":"left","bars":{"orientation":"horizontal","alongEdge":true,"items":[{"type":"master","icon":"","showOsd":true},{"type":"brightness","allMonitors":true,"icon":"sun","showOsd":false},{"type":"app","apps":["spotify"],"icon":"","showOsd":true},{"type":"bogus"}]},` +
				`"statuses":{"row":"all","items":["micUse","scrollLock","camera","battery","capsLock","vpn","old"],"quiet":["scrollLock","capsLock","camera"]},"cards":{"enabled":false,"timeout":6000,"items":["media","monitor"],"onTrackChange":false,"onPlayPause":true}}]}}`,
			`{"OSD":{"items":[{"id":"b","edge":"left","barLayout":{"orientation":"horizontal","alongEdge":true},"row":"all","cardsEnabled":false,"cardTimeout":6000,"systems":[` +
				`{"type":"Audio","bars":[{"type":"master","icon":"","showOsd":true},{"type":"app","apps":["spotify"],"icon":"","showOsd":true}],"tiles":[]},` +
				`{"type":"Brightness","allMonitors":true,"icon":"sun","quiet":true},{"type":"Privacy","kinds":["camera","micUse"]},{"type":"LockKeys","keys":["capsLock","scrollLock"],"quiet":true},` +
				`{"type":"Battery","tiles":["battery"]},{"type":"Vpn"},{"type":"Media","onTrackChange":false,"onPlayPause":true},{"type":"Monitors"}]}]}}`, true},
		{"missing parts were their old defaults",
			`{"OSD":{"items":[{"id":"c","statuses":{"items":["dnd"]}}]}}`,
			`{"OSD":{"items":[{"id":"c","systems":[` + v101OldAudio + `,"tiles":[]},{"type":"Dnd"},{"type":"Message"}]}]}}`, true},
		{"quiet event types stay quiet",
			`{"OSD":{"items":[{"id":"d","bars":{"items":[]},"statuses":{"items":["drive","battery","charger"],"quiet":["drive","battery"]},"cards":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"d","systems":[{"type":"Drives","quiet":true},{"type":"Battery","tiles":["charger","battery"]}]}]}}`, true},
		{"audio icons alone get no bars",
			`{"OSD":{"items":[{"id":"e","bars":{"items":[]},"statuses":{"items":["audio"],"quiet":["audio"]},"cards":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"e","systems":[{"type":"Audio","tiles":["audio"],"bars":[],"quiet":true}]}]}}`, true},
		{"a quiet audio icon beside an opening bar isn't quiet",
			`{"OSD":{"items":[{"id":"f","bars":{"items":[{"type":"master","showOsd":true}]},"statuses":{"items":["audio"],"quiet":["audio"]},"cards":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"f","systems":[{"type":"Audio","bars":[{"type":"master","showOsd":true}],"tiles":["audio"]}]}]}}`, true},
		{"a second bar of a kind but App is left out, its showOsd with it",
			`{"OSD":{"items":[{"id":"h","bars":{"items":[{"type":"master","showOsd":true},{"type":"master","showOsd":false},{"type":"app","apps":["a"],"showOsd":true},{"type":"app","apps":["b"],"showOsd":true}]},"statuses":{"items":[]},"cards":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"h","systems":[{"type":"Audio","bars":[{"type":"master","showOsd":true},{"type":"app","apps":["a"],"showOsd":true},{"type":"app","apps":["b"],"showOsd":true}],"tiles":[]}]}]}}`, true},
		{"cards only: a card-only OSD",
			`{"OSD":{"items":[{"id":"g","bars":{"items":[]},"statuses":{"items":[]},"cards":{"items":["screenshot","message"]}}]}}`,
			`{"OSD":{"items":[{"id":"g","systems":[{"type":"Screenshot"},{"type":"Message"}]}]}}`, true},
		{"already migrated",
			`{"OSD":{"items":[{"id":"a","row":"all","systems":[{"type":"Dnd"}]}]}}`,
			`{"OSD":{"items":[{"id":"a","row":"all","systems":[{"type":"Dnd"}]}]}}`, false},
		{"no OSD section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}

func TestV101SaysWhatItDropped(t *testing.T) {
	t.Parallel()
	v, err := jsonx.Unmarshal([]byte(`{"OSD":{"items":[{"id":"x","bars":{"items":[{"type":"brightness"},{"type":"brightness"},{"type":"master"},{"type":"master"},{"type":"bogus"}]},"statuses":{"items":["old"]},"cards":{"items":[]}}]}}`))
	if err != nil {
		t.Fatal(err)
	}
	changes := v101(v.(*jsonx.Object))
	if len(changes) != 2 {
		t.Fatalf("changes %v", changes)
	}
	for _, want := range []string{"OSD x", "a second brightness bar", "a second master bar", `"bogus"`, `"old"`} {
		if !strings.Contains(changes[1], want) {
			t.Errorf("%q lacks %q", changes[1], want)
		}
	}
}

func TestV101SaysWhichQuietTypesNowOpenIt(t *testing.T) {
	t.Parallel()
	v, err := jsonx.Unmarshal([]byte(`{"OSD":{"items":[{"id":"b","bars":{"items":[{"type":"master","showOsd":true}]},"statuses":{"items":["capsLock","numLock","scrollLock","audio","camera","micUse","dnd"],"quiet":["capsLock","scrollLock","audio","camera","micUse","dnd"]},"cards":{"items":[]}}]}}`))
	if err != nil {
		t.Fatal(err)
	}
	changes := v101(v.(*jsonx.Object))
	want := []string{
		"OSD b: audio now opens the OSD (Audio is one item)",
		"OSD b: capsLock, scrollLock now open the OSD (LockKeys is one item)",
	}
	if len(changes) != 1+len(want) {
		t.Fatalf("changes %q", changes)
	}
	for i, w := range want {
		if changes[1+i] != w {
			t.Errorf("note %d: %q, want %q", i, changes[1+i], w)
		}
	}
	// Privacy and Dnd took only quiet types: quiet items, nothing to say
	for _, c := range changes {
		if strings.Contains(c, "Privacy") || strings.Contains(c, "Dnd") {
			t.Errorf("a wholly quiet item said: %q", c)
		}
	}
}
