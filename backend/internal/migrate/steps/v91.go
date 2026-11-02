package steps

import (
	"fmt"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// osdCardOnly are the status types that were only ever a card: v91 moves
// them from an OSD's status icons to its own cards list.
var osdCardOnly = []string{"monitor", "screenshot", "message"}

// v91: an OSD's cards get their own object. `statuses.cards` and
// `statuses.cardTimeout` become `cards.enabled` and `cards.timeout`; the
// card-only types (osdCardOnly) leave `statuses.items` for `cards.items`
// (a quiet one is dropped: quiet already sent it to a notification);
// `media` (Now playing) becomes `media` in that list, its options
// `cards.onTrackChange` / `onPlayPause`. Messages now show only on an OSD
// that picks them: an OSD listing them keeps them, and with none listing
// them the first enabled one, where they went, gets them.
func v91(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	target := messageTarget(list)
	moved := 0
	for i, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil || entry.Has("cards") {
			continue
		}
		cards := jsonx.NewObject()
		statuses, _ := entry.Value("statuses").(*jsonx.Object)
		var quiet []any
		picked := []any{}
		if statuses != nil {
			if v, ok := statuses.Get("cards"); ok {
				cards.Set("enabled", v)
				statuses.Delete("cards")
			}
			if v, ok := statuses.Get("cardTimeout"); ok {
				cards.Set("timeout", v)
				statuses.Delete("cardTimeout")
			}
			if q, _ := statuses.Value("quiet").(*jsonx.Array); q != nil {
				quiet = slices.Clone(q.Items)
				q.Items = slices.DeleteFunc(q.Items, func(v any) bool { name, _ := v.(string); return slices.Contains(osdCardOnly, name) })
			}
			if shown, _ := statuses.Value("items").(*jsonx.Array); shown != nil {
				kept := []any{}
				for _, v := range shown.Items {
					name, _ := v.(string)
					if !slices.Contains(osdCardOnly, name) {
						kept = append(kept, v)
					} else if !slices.Contains(quiet, v) {
						picked = append(picked, v)
					}
				}
				shown.Items = kept
			}
		}
		if i == target {
			picked = append(picked, "message")
		}
		if media, _ := entry.Value("media").(*jsonx.Object); media != nil {
			if media.Value("enabled") == true {
				picked = append(picked, "media")
			}
			for _, key := range []string{"onTrackChange", "onPlayPause"} {
				if v, ok := media.Get(key); ok {
					cards.Set(key, v)
				}
			}
			entry.Delete("media")
		}
		cards.Set("items", &jsonx.Array{Items: picked})
		entry.Set("cards", cards)
		moved++
	}
	if moved == 0 {
		return nil
	}
	return []string{fmt.Sprintf("The cards of %d OSD(s) got their own settings: Monitors, Screenshots, Messages and Now playing are picked under Detail cards, and messages show only on an OSD that picks them", moved)}
}

// messageTarget is the index of the OSD that gets messages because no
// OSD lists them (the first enabled one, where they went); -1 when one
// lists them, or none is enabled.
func messageTarget(list *jsonx.Array) int {
	first := -1
	for i, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil || entry.Value("enabled") == false {
			continue
		}
		if first < 0 {
			first = i
		}
		if statuses, _ := entry.Value("statuses").(*jsonx.Object); statuses != nil {
			if shown, _ := statuses.Value("items").(*jsonx.Array); shown != nil && slices.Contains(shown.Items, any("message")) {
				return -1
			}
		}
	}
	return first
}
