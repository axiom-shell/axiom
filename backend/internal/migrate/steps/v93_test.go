package steps

import "testing"

func TestV93RemakesTheBarSettings(t *testing.T) {
	t.Parallel()
	bar := func(fields string) string { return `{"Bars":{"items":[{"id":"a",` + fields + `}]}}` }
	runStepCases(t, 93, []stepCase{
		// The old default bar's keys, renamed in place
		{"every old key", bar(`"background":"solid","widgetSize":26,"padding":4,"spacing":4,"widgetPadding":10,"widgetSpacing":4,"floatGap":-1,"pillPadding":4,"pillMerge":12,"lockCenter":true`),
			bar(`"surface":"bar","thickness":26,"edgePadding":4,"widgetGap":4,"innerPadding":10,"innerGap":4,"floatingGap":null,"lockCenter":true,"floating":false`), true},
		// background → surface + floating; missing lockCenter stays off
		{"pills", bar(`"background":"pills"`), bar(`"surface":"pills","floating":false,"lockCenter":false`), true},
		{"transparent", bar(`"background":"transparent"`), bar(`"surface":"none","floating":false,"lockCenter":false`), true},
		{"floating", bar(`"background":"floating"`), bar(`"surface":"bar","floating":true,"lockCenter":false`), true},
		{"floating pills", bar(`"background":"floatingPills"`), bar(`"surface":"pills","floating":true,"lockCenter":false`), true},
		{"an unknown background", bar(`"background":"glass"`), bar(`"surface":"bar","floating":false,"lockCenter":false`), true},
		{"no background (solid)", bar(`"location":"top"`), bar(`"location":"top","surface":"bar","floating":false,"lockCenter":false`), true},
		// floatGap: a number kept, Automatic (-1) or junk null
		{"a float gap", bar(`"surface":"bar","floatGap":8`), bar(`"surface":"bar","floatingGap":8`), true},
		{"a float gap of another shape", bar(`"surface":"bar","floatGap":"x"`), bar(`"surface":"bar","floatingGap":null`), true},
		// Inner sizes keep their pixels at the bar's thickness, and so does the text
		{"thickness 40", bar(`"background":"solid","widgetSize":40,"widgetPadding":10,"widgetSpacing":4`),
			bar(`"surface":"bar","thickness":40,"innerPadding":7,"innerGap":3,"floating":false,"lockCenter":false,"style":{"textScale":65}`), true},
		{"inner sizes clamped", bar(`"surface":"bar","widgetSize":10,"widgetPadding":40,"widgetSpacing":20`), bar(`"surface":"bar","thickness":10,"innerPadding":40,"innerGap":20`), true},
		{"a null style at thickness 40", bar(`"widgetSize":40,"style":null`), bar(`"thickness":40,"style":{"textScale":65},"surface":"bar","floating":false,"lockCenter":false`), true},
		{"a style of another shape", bar(`"widgetSize":40,"style":3`), bar(`"thickness":40,"style":3,"surface":"bar","floating":false,"lockCenter":false`), true},
		// Font sizes: the shared one against Appearance's, each bar's against the shared scale
		{"shared and own font sizes", `{"Appearance":{"font":{"size":14}},"Bars":{"style":{"fontSize":16,"widgetStyle":"plain"},"items":[{"id":"a","style":{"fontSize":null}},{"id":"b","style":{"fontSize":12}},{"id":"c","widgetSize":52}]}}`,
			`{"Appearance":{"font":{"size":14}},"Bars":{"style":{"textScale":114,"widgetStyle":"plain"},"items":[{"id":"a","style":{},"surface":"bar","floating":false,"lockCenter":false},{"id":"b","style":{"textScale":86},"surface":"bar","floating":false,"lockCenter":false},{"id":"c","thickness":52,"surface":"bar","floating":false,"lockCenter":false,"style":{"textScale":57}}]}}`, true},
		{"a null shared font size", `{"Bars":{"style":{"fontSize":null,"shadow":{}}}}`, `{"Bars":{"style":{"shadow":{}}}}`, true},
		{"another base font size", `{"Appearance":{"font":{"size":16}},"Bars":{"style":{"fontSize":16},"items":[{"id":"a","surface":"bar"}]}}`, `{"Appearance":{"font":{"size":16}},"Bars":{"style":{"textScale":100},"items":[{"id":"a","surface":"bar"}]}}`, true},
		{"scale clamped", `{"Bars":{"style":{"fontSize":32},"items":[{"id":"a","widgetSize":10}]}}`, `{"Bars":{"style":{"textScale":200},"items":[{"id":"a","thickness":10,"surface":"bar","floating":false,"lockCenter":false}]}}`, true},
		// The center sections join the sides after a Spacer
		{"center sections", bar(`"surface":"bar","widgets":{"left":[{"id":"x","type":"Time"}],"leftCenter":[{"id":"spacer","type":"Media"}],"center":[],"rightCenter":[{"id":"y","type":"Battery"}],"right":[{"id":"z","type":"Volume"}]}`),
			bar(`"surface":"bar","widgets":{"left":[{"id":"x","type":"Time"},{"id":"spacer-2","type":"Spacer"},{"id":"spacer","type":"Media"}],"center":[],"right":[{"id":"y","type":"Battery"},{"id":"spacer-3","type":"Spacer"},{"id":"z","type":"Volume"}]}`), true},
		{"center sections without sides", bar(`"surface":"bar","widgets":{"leftCenter":[{"id":"x","type":"Time"}],"rightCenter":[]}`), bar(`"surface":"bar","widgets":{"left":[{"id":"spacer","type":"Spacer"},{"id":"x","type":"Time"}]}`), true},
		{"center sections of another shape", bar(`"surface":"bar","widgets":{"left":[],"leftCenter":3,"rightCenter":null}`), bar(`"surface":"bar","widgets":{"left":[]}`), true},
		// Space separators become spacers; other separators stay
		{"space separators", bar(`"surface":"bar","widgets":{"left":[{"id":"s","type":"Separator","visible":false,"properties":{"style":"space","size":20,"color":"base03"},"layout":{"priority":2}},{"id":"t","type":"Separator","properties":{"style":"space"}},{"id":"u","type":"Separator","properties":{"style":"line"}}]}`),
			bar(`"surface":"bar","widgets":{"left":[{"id":"s","type":"Spacer","visible":false,"properties":{"minGap":20},"layout":{"priority":2}},{"id":"t","type":"Spacer","properties":{"minGap":12}},{"id":"u","type":"Separator","properties":{"style":"line"}}]}`), true},
		// Layout sizes: a maxSize on Window and Media, else gone
		{"layout sizes", bar(`"surface":"bar","widgets":{"left":[{"id":"w","type":"Window","layout":{"size":300,"minSize":80}},{"id":"m","type":"Media","layout":{"size":200,"maxSize":250}},{"id":"c","type":"Time","layout":{"size":90}},{"id":"b","type":"Battery","layout":{"minSize":40,"priority":5}},{"id":"v","type":"Volume","layout":{}}]}`),
			bar(`"surface":"bar","widgets":{"left":[{"id":"w","type":"Window","layout":{"maxSize":300,"minSize":80}},{"id":"m","type":"Media","layout":{"maxSize":250}},{"id":"c","type":"Time"},{"id":"b","type":"Battery","layout":{"priority":5}},{"id":"v","type":"Volume","layout":{}}]}`), true},
		// Both keys there: the new one wins
		{"old and new keys", bar(`"background":"pills","surface":"bar","widgetSize":30,"thickness":40,"floatGap":4,"floatingGap":null`), bar(`"surface":"bar","thickness":40,"floatingGap":null`), true},
		{"already migrated", bar(`"surface":"pills","floating":true,"thickness":30,"widgets":{"left":[{"id":"s","type":"Spacer","properties":{"minGap":0}}]}`),
			bar(`"surface":"pills","floating":true,"thickness":30,"widgets":{"left":[{"id":"s","type":"Spacer","properties":{"minGap":0}}]}`), false},
		{"items of another shape", `{"Bars":{"items":[3,null,{"id":"a","surface":"bar","widgets":{"left":[1,"x"]}}]}}`, `{"Bars":{"items":[3,null,{"id":"a","surface":"bar","widgets":{"left":[1,"x"]}}]}}`, false},
		{"items not a list", `{"Bars":{"items":{}}}`, `{"Bars":{"items":{}}}`, false},
		{"no Bars", `{"General":{}}`, `{"General":{}}`, false},
	})
}
