package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v103: an edge menu's `mode` (floating | integrated | submenu) became
// `placement` (edge | strip | free): where the menu lives, apart from
// what opens it. A menu without a mode is left to the default (edge); one
// with a mode that isn't a known string, or with a placement already, is
// left alone (the mode is pruned as an unknown key).
func v103(cfg *jsonx.Object) []string {
	menus := object(cfg, "EdgeMenus")
	if menus == nil {
		return nil
	}
	items, _ := menus.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	placements := map[string]string{"floating": "edge", "integrated": "strip", "submenu": "free"}
	moved := 0
	for _, item := range items.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil || entry.Has("placement") {
			continue
		}
		mode, _ := entry.Value("mode").(string)
		placement, ok := placements[mode]
		if !ok {
			continue
		}
		entry.Set("placement", placement)
		entry.Delete("mode")
		moved++
	}
	if moved == 0 {
		return nil
	}
	return []string{fmt.Sprintf("%d edge menu(s): mode became placement (floating → edge, integrated → strip, submenu → free)", moved)}
}
