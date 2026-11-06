package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v99: one catalogue of actions (the keybind table's ids) behind the
// QuickActions tiles and the Button widget, so their own names for an
// action become the table's: a QuickActions module's `caffeine` and `dnd`
// tiles became `idleInhibit` and `toggleDnd`; a Button's `appLauncher` and
// `workspaceOverlay` actions became `launcher` and `workspaceOverview`.
func v99(cfg *jsonx.Object) []string {
	tiles, buttons := 0, 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil {
				switch jsonx.ToString(t.Value("type")) {
				case "QuickActions":
					if renameTiles(props) {
						tiles++
					}
				case "Button":
					if renamed, ok := buttonActions[jsonx.ToString(props.Value("action"))]; ok {
						props.Set("action", renamed)
						buttons++
					}
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
	var changes []string
	if tiles > 0 {
		changes = append(changes, fmt.Sprintf("%d quick actions module(s): caffeine and dnd tiles became idleInhibit and toggleDnd", tiles))
	}
	if buttons > 0 {
		changes = append(changes, fmt.Sprintf("%d button widget(s): appLauncher and workspaceOverlay actions became launcher and workspaceOverview", buttons))
	}
	return changes
}

// The tiles and button actions renamed, old to new: frozen here, as a
// step's view of the schema
var (
	tileActions   = map[string]string{"caffeine": "idleInhibit", "dnd": "toggleDnd"}
	buttonActions = map[string]string{"appLauncher": "launcher", "workspaceOverlay": "workspaceOverview"}
)

// renameTiles renames a QuickActions module's old tiles in its `actions`;
// whether it renamed any.
func renameTiles(props *jsonx.Object) bool {
	list, _ := props.Value("actions").(*jsonx.Array)
	if list == nil {
		return false
	}
	renamed := false
	for i, item := range list.Items {
		old, _ := item.(string)
		if name, ok := tileActions[old]; ok {
			list.Items[i] = name
			renamed = true
		}
	}
	return renamed
}
