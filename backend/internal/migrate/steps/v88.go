package steps

import (
	"fmt"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// cornerUnsafe are the actions a hot corner can no longer run: each loses
// state or moves a window with no sign, and a corner fires on a stray
// pointer.
var cornerUnsafe = []string{"clearNotifications", "moveWindowStep", "moveWindowStepSilent", "moveWindowNth", "moveWindowNthSilent", "stopwatchReset", "timerReset", "pomodoroStop"}

// osdOldStatuses is the default status icons before v88, which v87 wrote
// into every OSD it split; osdAddedStatuses joined them, the toggles a
// bind or hot corner switches with no other sign.
var (
	osdOldStatuses   = []string{"capsLock", "numLock", "keyboardLayout", "microphone", "audio"}
	osdAddedStatuses = []string{"dnd", "caffeine", "nightLight", "recording"}
)

// v88: hot corners running one of cornerUnsafe go, and so does the old
// default bind logging out at once (SUPER + SHIFT + Escape, left as it
// came): SUPER + Escape's power menu logs out after asking. An OSD still
// on the old default status icons gets the new default's.
func v88(cfg *jsonx.Object) []string {
	changes := dropInstantLogout(cfg)
	changes = append(changes, dropUnsafeCorners(cfg)...)
	return append(changes, addToggleStatuses(cfg)...)
}

// addToggleStatuses gives each OSD whose status icons are osdOldStatuses
// (in that order) osdAddedStatuses too.
func addToggleStatuses(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	count := 0
	for _, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil {
			continue
		}
		statuses, _ := entry.Value("statuses").(*jsonx.Object)
		if statuses == nil {
			continue
		}
		shown, _ := statuses.Value("items").(*jsonx.Array)
		if shown == nil || len(shown.Items) != len(osdOldStatuses) {
			continue
		}
		same := true
		for i, v := range shown.Items {
			same = same && v == osdOldStatuses[i]
		}
		if !same {
			continue
		}
		for _, name := range osdAddedStatuses {
			shown.Append(name)
		}
		count++
	}
	if count == 0 {
		return nil
	}
	return []string{fmt.Sprintf("Do not disturb, caffeine, night light and screen recording added to the status icons of %d OSD(s) on the old default", count)}
}

// dropInstantLogout removes the old default exitSession bind, when its
// key and action are still the default's.
func dropInstantLogout(cfg *jsonx.Object) []string {
	keybinds := object(cfg, "Keybinds")
	if keybinds == nil {
		return nil
	}
	binds, _ := keybinds.Value("binds").(*jsonx.Array)
	if binds == nil {
		return nil
	}
	for i, item := range binds.Items {
		bind, _ := item.(*jsonx.Object)
		if bind == nil || bind.Value("id") != "super-shift-escape" || bind.Value("key") != "SUPER + SHIFT + Escape" || bind.Value("action") != "exitSession" {
			continue
		}
		binds.Items = slices.Delete(binds.Items, i, i+1)
		return []string{"The default SUPER + SHIFT + Escape bind, which logged out at once, removed: SUPER + Escape's power menu logs out after asking"}
	}
	return nil
}

// dropUnsafeCorners removes the hot corners running one of cornerUnsafe.
func dropUnsafeCorners(cfg *jsonx.Object) []string {
	corners := object(cfg, "HotCorners")
	if corners == nil {
		return nil
	}
	items, _ := corners.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	var dropped []string
	kept := items.Items[:0:0]
	for _, item := range items.Items {
		if corner, _ := item.(*jsonx.Object); corner != nil {
			if action, _ := corner.Value("action").(string); slices.Contains(cornerUnsafe, action) {
				dropped = append(dropped, action)
				continue
			}
		}
		kept = append(kept, item)
	}
	if len(dropped) == 0 {
		return nil
	}
	items.Items = kept
	return []string{fmt.Sprintf("%d hot corner(s) removed: a corner can no longer run %s", len(dropped), strings.Join(dropped, ", "))}
}
