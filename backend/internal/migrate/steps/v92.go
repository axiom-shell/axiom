package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v92: a per-app notification rule's two switches, `toasts` and
// `history`, become one `level`: both on is alert, toasts off silent (kept
// quietly, off the badge), history off toast (toasts, never kept), both
// off off (blocked). A switch missing is its default, on.
func v92(cfg *jsonx.Object) []string {
	n := object(cfg, "Notifications")
	if n == nil {
		return nil
	}
	apps, _ := n.Value("apps").(*jsonx.Array)
	if apps == nil {
		return nil
	}
	moved := 0
	for _, item := range apps.Items {
		rule, _ := item.(*jsonx.Object)
		if rule == nil || (!rule.Has("toasts") && !rule.Has("history")) {
			continue
		}
		toasts, history := on(rule, "toasts"), on(rule, "history")
		level := "alert"
		switch {
		case !toasts && !history:
			level = "off"
		case !toasts:
			level = "silent"
		case !history:
			level = "toast"
		}
		rule.Delete("toasts")
		rule.Delete("history")
		if !rule.Has("level") {
			rule.Set("level", level)
		}
		moved++
	}
	if moved == 0 {
		return nil
	}
	return []string{fmt.Sprintf("Notifications.apps: %d rule(s)' toasts and history became level", moved)}
}

// on reads a switch of o: true unless it's false.
func on(o *jsonx.Object, key string) bool {
	v, ok := o.Value(key).(bool)
	return !ok || v
}
