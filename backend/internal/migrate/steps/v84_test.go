package steps

import "testing"

func TestV84PlacesNotificationsOnAnEdge(t *testing.T) {
	t.Parallel()
	runStepCases(t, 84, []stepCase{
		{"top right, even gaps",
			`{"Notifications":{"position":"topRight","gaps":{"even":true,"all":18,"left":12,"right":12},"timeout":5000}}`,
			`{"Notifications":{"position":100,"timeout":5000,"edge":"top","detached":true,"gap":18}}`, true},
		{"bottom left, uneven gaps take the side's",
			`{"Notifications":{"position":"bottomLeft","gaps":{"even":false,"all":12,"left":30,"right":5}}}`,
			`{"Notifications":{"position":0,"edge":"bottom","detached":true,"gap":30}}`, true},
		{"bottom right, uneven",
			`{"Notifications":{"position":"bottomRight","gaps":{"even":false,"right":40}}}`,
			`{"Notifications":{"position":100,"edge":"bottom","detached":true,"gap":40}}`, true},
		{"the old default gap becomes Auto",
			`{"Notifications":{"position":"topLeft","gaps":{"even":true,"all":12}}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"no gaps",
			`{"Notifications":{"position":"topLeft"}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"an unknown corner goes top left",
			`{"Notifications":{"position":"middle"}}`,
			`{"Notifications":{"position":0,"edge":"top","detached":true}}`, true},
		{"gaps without a corner had the default one",
			`{"Notifications":{"gaps":{"even":false,"left":30,"right":5}}}`,
			`{"Notifications":{"edge":"top","position":0,"detached":true,"gap":30}}`, true},
		{"already migrated",
			`{"Notifications":{"edge":"right","position":50,"detached":false}}`,
			`{"Notifications":{"edge":"right","position":50,"detached":false}}`, false},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
	})
}
