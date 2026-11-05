package steps

import (
	"fmt"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// inputSourceBinds are the default binds stepping through the input
// sources (added in v95), as id, key and action.
var inputSourceBinds = [][3]string{
	{"super-ctrl-space", "SUPER + CTRL + space", "inputSourceNext"},
	{"super-ctrl-shift-space", "SUPER + CTRL + SHIFT + space", "inputSourcePrev"},
}

// v95: the input source binds joined the defaults: fcitx5's own hotkey
// reaches it only while a text field has focus, a compositor bind
// everywhere. Each is added unless the config has a bind with its id, its
// key or its action already.
func v95(cfg *jsonx.Object) []string {
	keybinds := object(cfg, "Keybinds")
	if keybinds == nil {
		return nil
	}
	binds, _ := keybinds.Value("binds").(*jsonx.Array)
	if binds == nil {
		return nil
	}
	var added []string
	for _, b := range inputSourceBinds {
		taken := false
		for _, item := range binds.Items {
			bind, _ := item.(*jsonx.Object)
			if bind == nil {
				continue
			}
			key, _ := bind.Value("key").(string)
			taken = taken || bind.Value("id") == b[0] || bind.Value("action") == b[2] || keyChord(key) == keyChord(b[1])
		}
		if taken {
			continue
		}
		binds.Append(jsonx.Obj("id", b[0], "key", b[1], "action", b[2], "argument", "", "call", "toggle", "compositor", "hyprland",
			"repeating", false, "locked", true, "release", false, "paused", false, "description", ""))
		added = append(added, b[1])
	}
	if len(added) == 0 {
		return nil
	}
	return []string{fmt.Sprintf("Input source binds added: %s (next and previous input source)", strings.Join(added, ", "))}
}

// keyChord is a bind's key as its sorted, upper-cased parts, so
// "CTRL + SUPER + space" and "SUPER + CTRL + SPACE" compare equal.
func keyChord(key string) string {
	parts := strings.Split(strings.ToUpper(key), "+")
	for i, p := range parts {
		parts[i] = strings.TrimSpace(p)
	}
	slices.Sort(parts)
	return strings.Join(parts, "+")
}
