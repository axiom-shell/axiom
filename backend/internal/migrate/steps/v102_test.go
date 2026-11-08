package steps

import "testing"

func TestV102StampsAudioBarIDs(t *testing.T) {
	t.Parallel()
	runStepCases(t, 102, []stepCase{
		{"the default's bars, and two OSDs keep their own ids apart",
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"type":"other","icon":"music_note"},{"type":"master"}]},{"type":"Dnd"}]},{"id":"b","systems":[{"type":"Audio","bars":[{"type":"master"}]}]}]}}`,
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"type":"other","icon":"music_note","id":"other"},{"type":"master","id":"master"}]},{"type":"Dnd"}]},{"id":"b","systems":[{"type":"Audio","bars":[{"type":"master","id":"master"}]}]}]}}`, true},
		{"App bars count up, beside ids already there",
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"type":"app","apps":["a"]},{"id":"app","type":"app"},{"type":"app"}]}]}]}}`,
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"type":"app","apps":["a"],"id":"app-2"},{"id":"app","type":"app"},{"type":"app","id":"app-3"}]}]}]}}`, true},
		{"a repeated, empty or odd id is replaced; an odd kind is a bar",
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"id":"x","type":"master"},{"id":"x","type":"other"},{"id":"","type":"microphone"},{"id":3,"type":"app"},{"id":"a b","type":"?"},{"type":7},"odd"]}]}]}}`,
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"id":"x","type":"master"},{"id":"other","type":"other"},{"id":"microphone","type":"microphone"},{"id":"app","type":"app"},{"id":"bar","type":"?"},{"type":7,"id":"bar-2"},"odd"]}]}]}}`, true},
		{"already stamped",
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"id":"master","type":"master"},{"id":"app","type":"app"}]}]}]}}`,
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"Audio","bars":[{"id":"master","type":"master"},{"id":"app","type":"app"}]}]}]}}`, false},
		{"another system's list, an Audio without bars, odd shapes",
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"LockKeys","bars":[{"type":"master"}]},{"type":"Audio"},{"type":"Audio","bars":3},5]},{"id":"b","systems":{}},7]}}`,
			`{"OSD":{"items":[{"id":"main","systems":[{"type":"LockKeys","bars":[{"type":"master"}]},{"type":"Audio"},{"type":"Audio","bars":3},5]},{"id":"b","systems":{}},7]}}`, false},
		{"no OSD section", `{"General":{}}`, `{"General":{}}`, false},
		{"an OSD section of another shape", `{"OSD":{"items":3}}`, `{"OSD":{"items":3}}`, false},
	})
}
