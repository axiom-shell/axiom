package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Tailscale.interval's schema bounds (config/schema/sections/Tailscale.yaml):
// a widget's interval saved before its minimum was raised to 1 s is
// clamped into them
const (
	tailscaleMinInterval = 1000
	tailscaleMaxInterval = 60000
)

// v79: Tailscale's poll interval is the Tailscale section's, shared by
// every widget and module, instead of each bar widget's: the shortest one
// found moves there (unless the section has its own) and the widgets'
// keys go. The widget's popout is its own now, so the old menu popout's
// default (off, no menu) is dropped rather than turning the new one off.
func v79(cfg *jsonx.Object) []string {
	var props []*jsonx.Object
	for _, w := range barWidgets(cfg, "Tailscale") {
		if p, _ := w.Value("properties").(*jsonx.Object); p != nil {
			props = append(props, p)
		}
	}
	var changes []string
	shortest, found, removed, popouts := 0.0, false, 0, 0
	for _, p := range props {
		if v, ok := p.Value("interval").(float64); ok && (!found || v < shortest) {
			shortest, found = v, true
		}
		if p.Delete("interval") {
			removed++
		}
		if popout, _ := p.Value("popout").(*jsonx.Object); popout != nil {
			if menu, _ := popout.Value("menu").(string); popout.Value("enabled") == false && menu == "" {
				popout.Delete("enabled")
				popouts++
			}
		}
	}
	if found {
		shortest = min(max(shortest, tailscaleMinInterval), tailscaleMaxInterval)
		section, _ := cfg.Value("Tailscale").(*jsonx.Object)
		if section == nil && !cfg.Has("Tailscale") {
			section = jsonx.NewObject()
			cfg.Set("Tailscale", section)
		}
		if section != nil && !section.Has("interval") {
			section.Set("interval", shortest)
			changes = append(changes, fmt.Sprintf("Tailscale.interval set to %s ms, the shortest Tailscale bar widget's interval", jsonx.FormatNumber(shortest)))
		}
	}
	if removed > 0 {
		changes = append(changes, fmt.Sprintf("interval removed from %d Tailscale bar widget(s): Tailscale → Check interval is shared by all", removed))
	}
	if popouts > 0 {
		changes = append(changes, fmt.Sprintf("%d Tailscale bar widget(s) now show their own popout (off by default before, when it could only open an edge menu)", popouts))
	}
	return changes
}

// barWidgets are the widgets of the given type on every bar
// (Bars.items[].widgets.<section>[]), skipping whatever isn't that shape.
func barWidgets(cfg *jsonx.Object, kind string) []*jsonx.Object {
	bars := object(cfg, "Bars")
	if bars == nil {
		return nil
	}
	items, _ := bars.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	var out []*jsonx.Object
	for _, bar := range items.Items {
		b, _ := bar.(*jsonx.Object)
		if b == nil {
			continue
		}
		sections, _ := b.Value("widgets").(*jsonx.Object)
		if sections == nil {
			continue
		}
		for _, key := range sections.Keys() {
			list, _ := sections.Value(key).(*jsonx.Array)
			if list == nil {
				continue
			}
			for _, item := range list.Items {
				if w, _ := item.(*jsonx.Object); w != nil && w.Value("type") == kind {
					out = append(out, w)
				}
			}
		}
	}
	return out
}
