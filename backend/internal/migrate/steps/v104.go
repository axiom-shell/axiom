package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v104: edge menus became menus (edge, strip and free ones alike): the
// section `EdgeMenus` became `Menus`, in the same place, and the action
// that opens one, `edgeMenu`, became `menu`: in the keybinds and their
// saved presets, the hot corners, and every Button widget, wherever it
// sits (matched by type). A config with both sections keeps the old one's
// menus (a `Menus` before this version is an unknown key).
func v104(cfg *jsonx.Object) []string {
	var changes []string
	if cfg.Has("EdgeMenus") {
		moved := jsonx.NewObject()
		for _, k := range cfg.Keys() {
			v, _ := cfg.Get(k)
			switch k {
			case "Menus":
				continue
			case "EdgeMenus":
				k = "Menus"
			}
			moved.Set(k, v)
		}
		for _, k := range cfg.Keys() {
			cfg.Delete(k)
		}
		for _, k := range moved.Keys() {
			v, _ := moved.Get(k)
			cfg.Set(k, v)
		}
		changes = append(changes, "EdgeMenus became Menus")
	}
	binds := 0
	renameAll := func(list any) {
		items, _ := list.(*jsonx.Array)
		if items == nil {
			return
		}
		for _, item := range items.Items {
			if renameMenuAction(item) {
				binds++
			}
		}
	}
	if keybinds := object(cfg, "Keybinds"); keybinds != nil {
		renameAll(keybinds.Value("binds"))
		if presets, _ := keybinds.Value("presets").(*jsonx.Array); presets != nil {
			for _, preset := range presets.Items {
				if p, _ := preset.(*jsonx.Object); p != nil {
					renameAll(p.Value("binds"))
				}
			}
		}
	}
	if corners := object(cfg, "HotCorners"); corners != nil {
		renameAll(corners.Value("items"))
	}
	if binds > 0 {
		changes = append(changes, fmt.Sprintf("%d keybind(s) and hot corner(s): the edgeMenu action became menu", binds))
	}
	buttons := 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil && jsonx.ToString(t.Value("type")) == "Button" && renameMenuAction(props) {
				buttons++
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
	if buttons > 0 {
		changes = append(changes, fmt.Sprintf("%d button widget(s): the edgeMenu action became menu", buttons))
	}
	return changes
}

// renameMenuAction sets an object's `action` edgeMenu to menu; whether it
// did.
func renameMenuAction(v any) bool {
	o, _ := v.(*jsonx.Object)
	if o == nil || o.Value("action") != "edgeMenu" {
		return false
	}
	o.Set("action", "menu")
	return true
}
