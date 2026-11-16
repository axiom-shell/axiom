package steps

import (
	"fmt"
	"strings"
	"testing"
)

// w111 puts a definition body in CustomWidgets.items[0]
func w111(body string) string {
	return `{"CustomWidgets":{"items":[{"id":"w"` + body + `}]}}`
}

func a111(id, name, command string) string {
	return fmt.Sprintf(`{"id":%q,"name":%q,"kind":"command","command":%q,"wait":false}`, id, name, command)
}

func r111(words ...[2]string) string {
	var rules []string
	for _, w := range words {
		rules = append(rules, fmt.Sprintf(`{"test":"is","value":%q,"color":%q}`, w[0], w[1]))
	}
	return "[" + strings.Join(rules, ",") + "]"
}

func s111(key string, words ...[2]string) string {
	return fmt.Sprintf(`{"enabled":true,"key":%q,"rules":%s}`, key, r111(words...))
}

func TestV111RewritesReleasedCustomWidgets(t *testing.T) {
	t.Parallel()
	builtIn := [][2]string{{"ok", "success"}, {"good", "success"}, {"warn", "warning"}, {"critical", "error"},
		{"error", "error"}, {"urgent", "error"}, {"info", "info"}, {"active", "accent"}}
	user := [][2]string{{"high", "base08"}, {"warning", "base0E"}}
	tenWords, tenIn := [][2]string{}, []string{}
	for i := 1; i <= 10; i++ {
		tenWords = append(tenWords, [2]string{fmt.Sprintf("k%d", i), "base08"})
		tenIn = append(tenIn, fmt.Sprintf(`"k%d":"base08"`, i))
	}
	capped := append(append([][2]string{}, tenWords...),
		[2]string{"ok", "success"}, [2]string{"good", "success"}, [2]string{"warning", "warning"},
		[2]string{"warn", "warning"}, [2]string{"critical", "error"}, [2]string{"error", "error"})
	five := [][2]string{{"error", "error"}, {"warning", "warning"}, {"success", "success"}, {"info", "info"}, {"accent", "accent"}}

	runStepCases(t, 111, []stepCase{
		{"bar commands",
			w111(`,"actions":{"click":"pavucontrol","scrollUp":"pamixer -i 5","refreshAfter":true}`),
			w111(`,"actions":{"refreshAfter":true,"items":[` + a111("click", "Click", "pavucontrol") + `,` + a111("scrollUp", "Scroll up", "pamixer -i 5") + `]},"bar":{"run":{"click":"click","scrollUp":"scrollUp"},"popout":true}`), true},
		{"same bar command twice",
			w111(`,"actions":{"click":"x","middleClick":"x"}`),
			w111(`,"actions":{"items":[` + a111("click", "Click", "x") + `]},"bar":{"run":{"click":"click","middleClick":"click"},"popout":true}`), true},
		{"v81 shape",
			w111(`,"actions":{"click":""},"module":{"elements":[{"type":"TextBlock","id":"t","bind":{"text":"text"},"options":{"monospace":true}}]}`),
			w111(`,"actions":{"items":[]},"module":{"elements":[{"type":"TextBlock","id":"t","bind":{"text":"{text}"},"options":{"monospace":true}}]},"bar":{"popout":true}`), true},
		{"bindings",
			w111(`,"module":{"elements":[{"type":"Text","id":"t","bind":{"a":"cpu","b":"data.temp","c":"{text}%","d":"100","e":"","f":"-2.5","g":"a:b"}}]}`),
			w111(`,"module":{"elements":[{"type":"Text","id":"t","bind":{"a":"{cpu}","b":"{data.temp}","c":"{text}%","d":"100","e":"","f":"-2.5","g":"a:b"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"element commands",
			w111(`,"module":{"elements":[{"type":"Toggle","id":"wifi","actions":{"on":"nmcli radio wifi on","off":"nmcli radio wifi off"}},{"type":"Bar","id":"vol","actions":{"change":"pamixer --set-volume {value}"}},{"type":"Text","id":"t","actions":{"click":"x"}}]}`),
			w111(`,"module":{"elements":[{"type":"Toggle","id":"wifi","run":{"on":"wifi-on","off":"wifi-off"}},{"type":"Bar","id":"vol","run":{"change":"vol"}},{"type":"Text","id":"t"}]},"bar":{"popout":true},"actions":{"items":[` +
				a111("wifi-on", "wifi on", "nmcli radio wifi on") + `,` + a111("wifi-off", "wifi off", "nmcli radio wifi off") + `,` + a111("vol", "vol", "pamixer --set-volume {value}") + `]}`), true},
		{"element reuses a bar action",
			w111(`,"actions":{"click":"x"},"module":{"elements":[{"type":"Button","id":"b","actions":{"click":"x"}}]}`),
			w111(`,"actions":{"items":[` + a111("click", "Click", "x") + `]},"module":{"elements":[{"type":"Button","id":"b","run":{"click":"click"}}]},"bar":{"run":{"click":"click"},"popout":true}`), true},
		{"id collision",
			w111(`,"actions":{"click":"x"},"module":{"elements":[{"type":"List","id":"click","actions":{"click":"y"}}]}`),
			w111(`,"actions":{"items":[` + a111("click", "Click", "x") + `,` + a111("click-2", "click", "y") + `]},"module":{"elements":[{"type":"List","id":"click","run":{"click":"click-2"}}]},"bar":{"run":{"click":"click"},"popout":true}`), true},
		{"Button label and {value}",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","options":{"label":"Play","icon":"play_arrow"},"actions":{"click":"playerctl {value}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","options":{},"bind":{"label":"Play","icon":"play_arrow"},"run":{"click":"b"},"args":{"click":"Play"}}]},"bar":{"popout":true},"actions":{"items":[` + a111("b", "b", "playerctl {value}") + `]}`), true},
		{"Button value becomes its argument",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"Go","value":"{a} b"},"actions":{"click":"kby {value}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"{Go}"},"run":{"click":"b"},"args":{"click":"{a} b"}}]},"bar":{"popout":true},"actions":{"items":[` + a111("b", "b", "kby {value}") + `]}`), true},
		{"Button bare-word value stays a path",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"value":"track"},"actions":{"click":"kby {value}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{},"run":{"click":"b"},"args":{"click":"{track}"}}]},"bar":{"popout":true},"actions":{"items":[` + a111("b", "b", "kby {value}") + `]}`), true},
		{"Button value, command without {value}",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"value":"x"},"actions":{"click":"kby next"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{},"run":{"click":"b"}}]},"bar":{"popout":true},"actions":{"items":[` + a111("b", "b", "kby next") + `]}`), true},
		{"Button value, no command",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"value":"x"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button bound label",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"title"},"options":{"label":"X"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"{title}"},"options":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button fallback",
			w111(`,"actions":{"click":"x"},"module":{"elements":[{"type":"Button","id":"b"}]}`),
			w111(`,"actions":{"items":[` + a111("click", "Click", "x") + `]},"module":{"elements":[{"type":"Button","id":"b","run":{"click":"click"}}]},"bar":{"run":{"click":"click"},"popout":true}`), true},
		{"List {value}",
			w111(`,"module":{"elements":[{"type":"List","id":"l","actions":{"click":"xdg-open {value}"}}]}`),
			w111(`,"module":{"elements":[{"type":"List","id":"l","run":{"click":"l"},"options":{"row":{"id":"{text}"}}}]},"bar":{"popout":true},"actions":{"items":[` + a111("l", "l", "xdg-open {value}") + `]}`), true},
		{"Toggle label",
			w111(`,"module":{"elements":[{"type":"Toggle","id":"t","options":{"label":"Wi-Fi"}}]}`),
			w111(`,"module":{"elements":[{"type":"Toggle","id":"t","options":{},"bind":{"label":"Wi-Fi"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button enabled, one path",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"Go","enabled":"unlocked"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"{Go}"},"enabledWhen":{"test":"on","key":"unlocked"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button enabled, braced path",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"enabled":"{a.b}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{},"enabledWhen":{"test":"on","key":"a.b"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button enabled, not a value",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"enabled":"{a}{b}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button enabled, typed text",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"enabled":"a:b"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"Button enabled, empty",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{"enabled":""}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","bind":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"enabled on another kind stays",
			w111(`,"module":{"elements":[{"type":"Toggle","id":"t","bind":{"enabled":"{a}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Toggle","id":"t","bind":{"enabled":"{a}"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"states",
			w111(`,"states":{"high":"base08","warning":"base0E","empty":""},"module":{"elements":[{"type":"Text","id":"t","options":{"stateColor":true}},{"type":"Status","id":"s"},{"type":"Ring","id":"r","options":{"color":"base0D"}}]}`),
			w111(`,"module":{"elements":[{"type":"Text","id":"t","options":{"colorStates":` + s111("state", append(append([][2]string{}, user...), builtIn...)...) + `}},{"type":"Status","id":"s","options":{"colorStates":` + s111("state", user...) + `}},{"type":"Ring","id":"r","options":{"color":"base0D"}}]},"bar":{"colorStates":` + s111("state", user...) + `,"popout":true},"actions":{"items":[]}`), true},
		{"Color by state, no states",
			w111(`,"module":{"elements":[{"type":"Text","id":"t","options":{"stateColor":true}},{"type":"TextBlock","id":"b","options":{"stateColor":false}}]}`),
			w111(`,"module":{"elements":[{"type":"Text","id":"t","options":{"colorStates":` + s111("color", five...) + `}},{"type":"TextBlock","id":"b","options":{}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"16-rule cap",
			w111(`,"states":{` + strings.Join(tenIn, ",") + `},"module":{"elements":[{"type":"Text","id":"t","options":{"stateColor":true}}]}`),
			w111(`,"module":{"elements":[{"type":"Text","id":"t","options":{"colorStates":` + s111("state", capped...) + `}}]},"bar":{"colorStates":` + s111("state", tenWords...) + `,"popout":true},"actions":{"items":[]}`), true},
		{"already migrated",
			w111(`,"actions":{"items":[]},"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"Play"}}]}`),
			w111(`,"actions":{"items":[]},"module":{"elements":[{"type":"Button","id":"b","bind":{"label":"Play"}}]}`), false},
		{"nothing to do",
			w111(`,"module":{"elements":[{"type":"Text","id":"t","bind":{"text":"{text}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Text","id":"t","bind":{"text":"{text}"}}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"no section", `{"General":{}}`, `{"General":{}}`, false},
		{"a section of another shape", `{"CustomWidgets":3}`, `{"CustomWidgets":3}`, false},
		{"items not a list", `{"CustomWidgets":{"items":{}}}`, `{"CustomWidgets":{"items":{}}}`, false},
		{"an item that is not an object", `{"CustomWidgets":{"items":["x",3]}}`, `{"CustomWidgets":{"items":["x",3]}}`, false},
		{"actions not an object", w111(`,"actions":"x","states":{"a":"b"}`), w111(`,"actions":"x","states":{"a":"b"}`), false},
		{"odd elements and binds",
			w111(`,"module":{"elements":[5,{"type":"Text","id":"t","bind":[]},{"type":"Button","id":"b","bind":"x","options":3}]}`),
			w111(`,"module":{"elements":[5,{"type":"Text","id":"t","bind":[]},{"type":"Button","id":"b","bind":"x","options":3}]},"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"states not an object", w111(`,"states":[]`), w111(`` + `,"bar":{"popout":true},"actions":{"items":[]}`), true},
		{"bar popout kept as it was",
			w111(`,"bar":{"popout":false},"module":{"elements":[{"type":"Text","id":"t"}]}`),
			w111(`,"bar":{"popout":false},"module":{"elements":[{"type":"Text","id":"t"}]}`), false},
		{"Button label with a space is not quoted",
			w111(`,"module":{"elements":[{"type":"Button","id":"b","options":{"label":"Play pause"},"actions":{"click":"playerctl {value}"}}]}`),
			w111(`,"module":{"elements":[{"type":"Button","id":"b","options":{},"bind":{"label":"Play pause"},"run":{"click":"b"},"args":{"click":"Play pause"}}]},"bar":{"popout":true},"actions":{"items":[` + a111("b", "b", "playerctl {value}") + `]}`), true},
	})
}
