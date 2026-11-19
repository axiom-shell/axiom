package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v113 moves the Module size of each layout that draws modules on a surface
// of its own (an edge menu's `layout`, a Desktop item, `Lockscreen.layout`,
// `Greeter.layout`) from `moduleScale` into its `sizing` group, as its
// Card size: cards and content grew together by it, which is what the
// group's link does by default. A value of 100 was the default and is just
// removed. A `sizing` already beside it wins; a `moduleScale` that isn't a
// number is left alone.
func v113(cfg *jsonx.Object) []string {
	var changes []string
	// An item of Menus.items holds its layout, an item of Desktop.items is one
	for _, section := range []struct {
		key      string
		inLayout bool
	}{{"Menus", true}, {"Desktop", false}} {
		holder := object(cfg, section.key)
		if holder == nil {
			continue
		}
		items, _ := holder.Value("items").(*jsonx.Array)
		if items == nil {
			continue
		}
		for _, entry := range items.Items {
			item, _ := entry.(*jsonx.Object)
			if item == nil {
				continue
			}
			layout := item
			if section.inLayout {
				layout, _ = item.Value("layout").(*jsonx.Object)
			}
			if v113Layout(layout) {
				id, _ := item.Value("id").(string)
				changes = append(changes, fmt.Sprintf("%s item %q: moduleScale moved to sizing.cardSize", section.key, id))
			}
		}
	}
	for _, key := range []string{"Lockscreen", "Greeter"} {
		if v113Layout(object(cfg, key, "layout")) {
			changes = append(changes, key+".layout.moduleScale moved to sizing.cardSize")
		}
	}
	return changes
}

// v113Layout moves one layout's moduleScale, reporting whether it had one
func v113Layout(layout *jsonx.Object) bool {
	if layout == nil {
		return false
	}
	scale, isNumber := layout.Value("moduleScale").(float64)
	if !isNumber {
		return false
	}
	layout.Delete("moduleScale")
	if scale != 100 && !layout.Has("sizing") {
		layout.Set("sizing", jsonx.Obj("cardSize", scale))
	}
	return true
}
