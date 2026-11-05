package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v98: the hover triggers have one fixed depth, and their length always
// matches the surface's own along its edge, so `trigger` (`size`,
// `length`) is dropped from Popouts, every bar, dock and edge menu; and an
// edge menu's own `padding` goes, edge menus using Popouts.padding.
func v98(cfg *jsonx.Object) []string {
	var changes []string
	if popouts := object(cfg, "Popouts"); popouts != nil && popouts.Has("trigger") {
		popouts.Delete("trigger")
		changes = append(changes, "Popouts.trigger dropped (the hover strip has a fixed size)")
	}
	for _, list := range [][2]string{{"Bars", "bar"}, {"Dock", "dock"}, {"EdgeMenus", "edge menu"}} {
		section := object(cfg, list[0])
		if section == nil {
			continue
		}
		items, _ := section.Value("items").(*jsonx.Array)
		if items == nil {
			continue
		}
		triggers, paddings := 0, 0
		for _, item := range items.Items {
			entry, _ := item.(*jsonx.Object)
			if entry == nil {
				continue
			}
			if entry.Has("trigger") {
				entry.Delete("trigger")
				triggers++
			}
			if list[0] == "EdgeMenus" && entry.Has("padding") {
				entry.Delete("padding")
				paddings++
			}
		}
		if triggers > 0 {
			changes = append(changes, fmt.Sprintf("%d %s(s): trigger dropped (the hover strip has a fixed size and its surface's length)", triggers, list[1]))
		}
		if paddings > 0 {
			changes = append(changes, fmt.Sprintf("%d edge menu(s): padding dropped (edge menus use Popouts.padding)", paddings))
		}
	}
	return changes
}
