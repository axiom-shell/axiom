package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v97: every detached surface is placed as the launcher is, a `distance`
// across the free screen from its edge (0 where the automatic gap put
// it), so an OSD's, a dock's and an edge menu's `gap` (px from the frame
// lines) is dropped: a fixed px gap has no percentage to become.
func v97(cfg *jsonx.Object) []string {
	var changes []string
	for _, list := range [][2]string{{"OSD", "OSD"}, {"Dock", "dock"}, {"EdgeMenus", "edge menu"}} {
		section := object(cfg, list[0])
		if section == nil {
			continue
		}
		items, _ := section.Value("items").(*jsonx.Array)
		if items == nil {
			continue
		}
		dropped := 0
		for _, item := range items.Items {
			entry, _ := item.(*jsonx.Object)
			if entry == nil || !entry.Has("gap") {
				continue
			}
			entry.Delete("gap")
			dropped++
		}
		if dropped > 0 {
			changes = append(changes, fmt.Sprintf("%d %s(s): gap dropped (detached surfaces are placed by distance, 0 where the automatic gap put them)", dropped, list[1]))
		}
	}
	return changes
}
