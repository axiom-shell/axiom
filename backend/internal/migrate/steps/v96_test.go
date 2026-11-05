package steps

import "testing"

func TestV96ClocksFollowDateAndTime(t *testing.T) {
	t.Parallel()
	runStepCases(t, 96, []stepCase{
		{"a bar clock at its old default", `{"Bars":{"items":[{"widgets":{"right":[{"id":"t","type":"Time","properties":{"use24Hour":false,"showDate":true}}]}}]}}`,
			`{"Bars":{"items":[{"widgets":{"right":[{"id":"t","type":"Time","properties":{"hourFormat":"default","showDate":true}}]}}]}}`, true},
		{"a bar clock set to 24-hour", `{"Bars":{"items":[{"widgets":{"right":[{"id":"t","type":"Time","properties":{"use24Hour":true}}]}}]}}`,
			`{"Bars":{"items":[{"widgets":{"right":[{"id":"t","type":"Time","properties":{"hourFormat":"24"}}]}}]}}`, true},
		{"modules anywhere", `{"Desktop":{"modules":[{"type":"Clock","properties":{"use24Hour":true}},{"type":"WorldClocks","properties":{"use24Hour":false}}]},"Lockscreen":{"layout":{"modules":[{"type":"ClockCalendar","properties":{"use24Hour":true,"showSeconds":true}}]}}}`,
			`{"Desktop":{"modules":[{"type":"Clock","properties":{"hourFormat":"default"}},{"type":"WorldClocks","properties":{"hourFormat":"12"}}]},"Lockscreen":{"layout":{"modules":[{"type":"ClockCalendar","properties":{"hourFormat":"default","showSeconds":true}}]}}}`, true},
		{"a clock that never set it", `{"Desktop":{"modules":[{"type":"Clock","properties":{"style":"digital"}}]}}`, `{"Desktop":{"modules":[{"type":"Clock","properties":{"style":"digital"}}]}}`, false},
		{"another type keeps its key", `{"Desktop":{"modules":[{"type":"Agenda","properties":{"use24Hour":true}}]}}`, `{"Desktop":{"modules":[{"type":"Agenda","properties":{"use24Hour":true}}]}}`, false},
		{"Calendar", `{"Calendar":{"use24Hour":false,"maxDots":3}}`, `{"Calendar":{"hourFormat":"12","maxDots":3}}`, true},
		{"Calendar at its default", `{"Calendar":{"use24Hour":true}}`, `{"Calendar":{"hourFormat":"default"}}`, true},
	})
}

func TestV96TerminalFollowsTheSystem(t *testing.T) {
	t.Parallel()
	runStepCases(t, 96, []stepCase{
		{"the old default", `{"Apps":{"terminal":"kitty","browser":""}}`, `{"Apps":{"terminal":"","browser":""}}`, true},
		{"one of the user's", `{"Apps":{"terminal":"foot"}}`, `{"Apps":{"terminal":"foot"}}`, false},
		{"kitty with options", `{"Apps":{"terminal":"kitty --single-instance"}}`, `{"Apps":{"terminal":"kitty --single-instance"}}`, false},
		{"no Apps", `{"General":{}}`, `{"General":{}}`, false},
	})
}
