package steps

import "testing"

func TestV91GivesTheOSDsCardsTheirOwnSettings(t *testing.T) {
	t.Parallel()
	runStepCases(t, 91, []stepCase{
		{"switch, timeout and the card-only types move",
			`{"OSD":{"items":[{"id":"a","statuses":{"row":"all","cards":false,"cardTimeout":6000,"items":["capsLock","monitor","drive","screenshot"],"quiet":["drive"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"row":"all","items":["capsLock","drive"],"quiet":["drive"]},"cards":{"enabled":false,"timeout":6000,"items":["monitor","screenshot","message"]}}]}}`, true},
		{"a quiet card-only type is dropped",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["monitor","message"],"quiet":["monitor","message"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":[],"quiet":[]},"cards":{"items":[]}}]}}`, true},
		{"now playing joins the list with its options",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":[]},"media":{"enabled":true,"onTrackChange":false,"onPlayPause":true}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":[]},"cards":{"onTrackChange":false,"onPlayPause":true,"items":["message","media"]}}]}}`, true},
		{"now playing off keeps its options",
			`{"OSD":{"items":[{"id":"a","media":{"enabled":false,"onPlayPause":true}}]}}`,
			`{"OSD":{"items":[{"id":"a","cards":{"onPlayPause":true,"items":["message"]}}]}}`, true},
		{"messages stay where listed, the first enabled one gets none",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["dnd"]}},{"id":"b","statuses":{"items":["message"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["dnd"]},"cards":{"items":[]}},{"id":"b","statuses":{"items":[]},"cards":{"items":["message"]}}]}}`, true},
		{"listed nowhere: the first enabled one gets messages",
			`{"OSD":{"items":[{"id":"a","enabled":false},{"id":"b"}]}}`,
			`{"OSD":{"items":[{"id":"a","enabled":false,"cards":{"items":[]}},{"id":"b","cards":{"items":["message"]}}]}}`, true},
		{"listed nowhere but quiet on the first: none gets messages",
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["dnd"],"quiet":["message"]}}]}}`,
			`{"OSD":{"items":[{"id":"a","statuses":{"items":["dnd"],"quiet":[]},"cards":{"items":[]}}]}}`, true},
		{"already migrated",
			`{"OSD":{"items":[{"id":"a","cards":{"items":[]}}]}}`,
			`{"OSD":{"items":[{"id":"a","cards":{"items":[]}}]}}`, false},
		{"no OSD section", `{"Bars":{}}`, `{"Bars":{}}`, false},
	})
}
