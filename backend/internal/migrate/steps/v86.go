package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v86: an OSD's bars became its items, as it now also shows lock keys,
// the keyboard layout, toggles and the track playing. The key keeps its
// place among the entry's keys. An OSD still showing the old default
// (Other apps, then System volume) gets the new default's statuses after
// them, as a config that never set its bars would.
func v86(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	count, extended := 0, 0
	for i, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil || !entry.Has("bars") || entry.Has("items") {
			continue
		}
		renamed := renameKey(entry, "bars", "items")
		if items, _ := renamed.Value("items").(*jsonx.Array); items != nil && isOldDefault(items) {
			for _, kind := range []string{"lockKeys", "keyboardLayout", "micMute", "outputDevice"} {
				items.Append(jsonx.Obj("type", kind, "icon", "", "showOsd", true))
			}
			extended++
		}
		list.Items[i] = renamed
		count++
	}
	if count == 0 {
		return nil
	}
	changes := []string{fmt.Sprintf("OSD bars became OSD items in %d OSD(s)", count)}
	if extended > 0 {
		changes = append(changes, fmt.Sprintf("%d OSD(s) on the default bars also show lock keys, the keyboard layout, the microphone muted and the output device switched", extended))
	}
	return changes
}

// isOldDefault says whether items are the bars v85's default had: Other
// apps with a note icon, then System volume, each opening the OSD.
func isOldDefault(items *jsonx.Array) bool {
	want := [][2]string{{"other", "music_note"}, {"master", ""}}
	if items.Len() != len(want) {
		return false
	}
	for i, item := range items.Items {
		o, _ := item.(*jsonx.Object)
		if o == nil || o.Value("type") != want[i][0] || o.Value("icon") != want[i][1] || o.Value("showOsd") != true {
			return false
		}
		if apps, _ := o.Value("apps").(*jsonx.Array); apps != nil && apps.Len() > 0 {
			return false
		}
	}
	return true
}

// renameKey is o with key from renamed to, in the same place.
func renameKey(o *jsonx.Object, from, to string) *jsonx.Object {
	out := jsonx.NewObject()
	for _, k := range o.Keys() {
		v, _ := o.Get(k)
		if k == from {
			k = to
		}
		out.Set(k, v)
	}
	return out
}
