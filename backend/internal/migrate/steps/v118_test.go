package steps

import "testing"

func TestV118MovesPopoutOnlyKeysIntoPopoutProperties(t *testing.T) {
	t.Parallel()
	w := func(typ, props string) string {
		return `{"Bars":{"items":[{"id":"b","widgets":[{"type":"` + typ + `","properties":` + props + `}]}]}}`
	}
	runStepCases(t, 118, []stepCase{
		{"Network popoutVpn false", w("Network", `{"popoutVpn":false}`),
			w("Network", `{"popout":{"properties":{"showVpn":false}}}`), true},
		{"Network popout kept", w("Network", `{"popout":{"enabled":true,"menu":""},"popoutVpn":false}`),
			w("Network", `{"popout":{"enabled":true,"menu":"","properties":{"showVpn":false}}}`), true},
		{"Network target wins", w("Network", `{"popout":{"properties":{"showVpn":true}},"popoutVpn":false}`),
			w("Network", `{"popout":{"properties":{"showVpn":true}}}`), true},
		{"Network without popoutVpn", w("Network", `{"showDevice":true}`),
			w("Network", `{"showDevice":true}`), false},
		{"Network popout not an object", w("Network", `{"popout":"x","popoutVpn":false}`),
			w("Network", `{"popout":"x","popoutVpn":false}`), false},
		{"Network popout.properties not an object", w("Network", `{"popout":{"properties":[]},"popoutVpn":false}`),
			w("Network", `{"popout":{"properties":[]},"popoutVpn":false}`), false},
		{"a Network widget inside a group", `{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Network","properties":{"popoutVpn":true}}]}}]}]}}`,
			`{"Bars":{"items":[{"left":[{"type":"Group","properties":{"widgets":[{"type":"Network","properties":{"popout":{"properties":{"showVpn":true}}}}]}}]}]}}`, true},
		{"IdleInhibitor presets", w("IdleInhibitor", `{"showLabel":true,"presets":["10m"]}`),
			w("IdleInhibitor", `{"showLabel":true,"popout":{"properties":{"presets":["10m"]}}}`), true},
		{"IdleInhibitor target wins", w("IdleInhibitor", `{"popout":{"properties":{"presets":["1h"]}},"presets":["10m"]}`),
			w("IdleInhibitor", `{"popout":{"properties":{"presets":["1h"]}}}`), true},
		{"a WifiNetworks and a Caffeine module unchanged", `{"Overlay":{"items":[{"id":"p","layout":[{"type":"WifiNetworks","properties":{"showVpn":false}},{"type":"Caffeine","properties":{"presets":["5m"]}}]}]}}`,
			`{"Overlay":{"items":[{"id":"p","layout":[{"type":"WifiNetworks","properties":{"showVpn":false}},{"type":"Caffeine","properties":{"presets":["5m"]}}]}]}}`, false},
		{"a Bluetooth widget's stray popoutVpn unchanged", w("Bluetooth", `{"popoutVpn":false}`),
			w("Bluetooth", `{"popoutVpn":false}`), false},
	})
}
