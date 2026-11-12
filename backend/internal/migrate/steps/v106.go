package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v106: the per-widget "Colour the text by state" option went: a bar
// widget's `properties.appearance.colorText` (wherever the widget sits,
// matched by the `properties.appearance` object) and a custom widget's
// `bar.colorText` (`CustomWidgets.items[]`) are dropped. A SystemStats
// widget's `boxes` goes too: it always draws one box.
func v106(cfg *jsonx.Object) []string {
	widgets, custom := 0, 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil {
				if app, _ := props.Value("appearance").(*jsonx.Object); app != nil && app.Has("colorText") {
					app.Delete("colorText")
					widgets++
				}
			}
			for _, k := range t.Keys() {
				walk(t.Value(k))
			}
		case *jsonx.Array:
			for _, item := range t.Items {
				walk(item)
			}
		}
	}
	walk(cfg)
	var items *jsonx.Array
	if cw := object(cfg, "CustomWidgets"); cw != nil {
		items, _ = cw.Value("items").(*jsonx.Array)
	}
	if items != nil {
		for _, item := range items.Items {
			entry, _ := item.(*jsonx.Object)
			if entry == nil {
				continue
			}
			if bar, _ := entry.Value("bar").(*jsonx.Object); bar != nil && bar.Has("colorText") {
				bar.Delete("colorText")
				custom++
			}
		}
	}
	boxes := eachTyped(cfg.Value("Bars"), "SystemStats", func(p *jsonx.Object) bool {
		if !p.Has("boxes") {
			return false
		}
		p.Delete("boxes")
		return true
	})
	var changes []string
	if widgets > 0 {
		changes = append(changes, fmt.Sprintf("%d bar widget(s): appearance.colorText dropped", widgets))
	}
	if custom > 0 {
		changes = append(changes, fmt.Sprintf("%d custom widget(s): bar.colorText dropped", custom))
	}
	if boxes > 0 {
		changes = append(changes, fmt.Sprintf("%d SystemStats widget(s): boxes dropped (always one box)", boxes))
	}
	return changes
}
