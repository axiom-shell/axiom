package steps

import "testing"

func TestV90TurnsDrivesAnnounceIntoNotify(t *testing.T) {
	t.Parallel()
	runStepCases(t, 90, []stepCase{
		{"on the OSD", `{"Drives":{"announce":"osd","onInsert":"ask"}}`, `{"Drives":{"onInsert":"ask","notify":true}}`, true},
		{"as notifications", `{"Drives":{"announce":"notification"}}`, `{"Drives":{"notify":true}}`, true},
		{"off", `{"Drives":{"announce":"off"}}`, `{"Drives":{"notify":false}}`, true},
		{"notify already set", `{"Drives":{"announce":"off","notify":true}}`, `{"Drives":{"notify":true}}`, true},
		{"already migrated", `{"Drives":{"notify":false}}`, `{"Drives":{"notify":false}}`, false},
		{"an unknown value", `{"Drives":{"announce":"loud"}}`, `{"Drives":{"announce":"loud"}}`, false},
		{"no Drives", `{"OSD":{}}`, `{"OSD":{}}`, false},
	})
}
