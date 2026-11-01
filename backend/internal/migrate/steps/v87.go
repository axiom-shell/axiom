package steps

import (
	"fmt"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// osdLevels are the item types v86 drew as bars.
var osdLevels = map[string]bool{"master": true, "other": true, "app": true, "microphone": true, "brightness": true}

// osdBarKeys are an OSD's keys that only lay out its bars.
var osdBarKeys = []string{"orientation", "alongEdge", "showPercent"}

// v87: an OSD's one list of items split into its parts: `bars` (the
// levels, with the keys that lay them out), `statuses` (the status types
// shown as icons, those that don't open the OSD also in `quiet`; lock
// keys one type per key) and `media` (the now playing card). A status's
// own icon goes: a status's icon is what it shows. The three take the
// list's place among the entry's keys.
func v87(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	count, icons := 0, 0
	for i, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil {
			continue
		}
		if _, done := entry.Value("bars").(*jsonx.Object); done {
			continue
		}
		items, _ := entry.Value("items").(*jsonx.Array)
		if items == nil {
			// Its items on the default: only the layout keys move
			if out := nestBarKeys(entry); out != nil {
				list.Items[i] = out
				count++
			}
			continue
		}
		bars := jsonx.NewObject()
		for _, k := range osdBarKeys {
			if v, ok := entry.Get(k); ok {
				bars.Set(k, v)
			}
		}
		levels := jsonx.Arr()
		shown, quiet := jsonx.Arr(), jsonx.Arr()
		seen := map[string]bool{}
		var media *jsonx.Object
		addStatus := func(kind string, opens bool) {
			if seen[kind] {
				return
			}
			seen[kind] = true
			shown.Append(kind)
			if !opens {
				quiet.Append(kind)
			}
		}
		for _, raw := range items.Items {
			it, _ := raw.(*jsonx.Object)
			if it == nil {
				continue
			}
			kind, _ := it.Value("type").(string)
			opens := it.Value("showOsd") != false
			switch {
			case osdLevels[kind]:
				levels.Append(it)
			case kind == "media":
				media = jsonx.Obj("enabled", true)
				for _, k := range []string{"onTrackChange", "onPlayPause"} {
					if v, ok := it.Get(k); ok {
						media.Set(k, v)
					}
				}
			case kind == "lockKeys":
				// The schema's defaults: Caps and Num Lock on, Scroll Lock off
				for _, key := range [][3]any{{"caps", "capsLock", true}, {"num", "numLock", true}, {"scroll", "scrollLock", false}} {
					on, ok := it.Value(key[0].(string)).(bool)
					if !ok {
						on = key[2].(bool)
					}
					if on {
						addStatus(key[1].(string), opens)
					}
				}
			case kind != "":
				addStatus(kind, opens)
			default:
				continue
			}
			if icon, _ := it.Value("icon").(string); icon != "" && !osdLevels[kind] && kind != "message" {
				icons++
			}
		}
		bars.Set("items", levels)
		statuses := jsonx.Obj("items", shown, "quiet", quiet)
		out := jsonx.NewObject()
		for _, k := range entry.Keys() {
			v, _ := entry.Get(k)
			switch {
			case k == "items":
				out.Set("bars", bars)
				out.Set("statuses", statuses)
				if media != nil {
					out.Set("media", media)
				}
			case k == "bars" || k == "statuses" || k == "media":
				// A v85 bars list left beside items, or a stray: replaced
			case slices.Contains(osdBarKeys, k):
			default:
				out.Set(k, v)
			}
		}
		list.Items[i] = out
		count++
	}
	if count == 0 {
		return nil
	}
	changes := []string{fmt.Sprintf("OSD items split into bars, status icons and now playing in %d OSD(s)", count)}
	if icons > 0 {
		changes = append(changes, fmt.Sprintf("%d status icon(s) set by hand dropped: a status shows its own icon", icons))
	}
	return changes
}

// nestBarKeys is entry with its bar layout keys under `bars`, in the
// first one's place, for an OSD that never set its items (they come from
// the default); nil when it has none.
func nestBarKeys(entry *jsonx.Object) *jsonx.Object {
	bars := jsonx.NewObject()
	out := jsonx.NewObject()
	for _, k := range entry.Keys() {
		v, _ := entry.Get(k)
		if !slices.Contains(osdBarKeys, k) {
			out.Set(k, v)
			continue
		}
		if bars.Len() == 0 {
			out.Set("bars", bars)
		}
		bars.Set(k, v)
	}
	if bars.Len() == 0 {
		return nil
	}
	return out
}
