package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v99: the toasts' `gap` and a per-app rule's `timeout` store Automatic as
// null (x-auto's null value), no longer -1, so their minimum is 0.
func v99(cfg *jsonx.Object) []string {
	notifications := object(cfg, "Notifications")
	if notifications == nil {
		return nil
	}
	var changes []string
	if negative(notifications.Value("gap")) {
		notifications.Set("gap", nil)
		changes = append(changes, "Notifications.gap: Automatic is null, no longer -1")
	}
	apps, _ := notifications.Value("apps").(*jsonx.Array)
	if apps == nil {
		return changes
	}
	rules := 0
	for _, item := range apps.Items {
		rule, _ := item.(*jsonx.Object)
		if rule != nil && negative(rule.Value("timeout")) {
			rule.Set("timeout", nil)
			rules++
		}
	}
	if rules > 0 {
		changes = append(changes, fmt.Sprintf("%d notification app rule(s): Automatic timeout is null, no longer -1", rules))
	}
	return changes
}

// negative says v is a number below 0 (the old Automatic sentinel).
func negative(v any) bool {
	n, ok := v.(float64)
	return ok && n < 0
}
