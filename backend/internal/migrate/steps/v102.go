package steps

import (
	"fmt"
	"regexp"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v102: every bar of an OSD's Audio (its `bars`) has a stable id, unique
// in its list, so an App bar's key is `app:<its id>` (no longer its
// index) and an OSD's `barOrder` can name it. A bar without one, or
// with one an earlier bar of its list has or that isn't an id, gets its kind (`master`,
// `app`, …; `bar` for none), else its kind with -2, -3 …; ids it has
// already are kept.
func v102(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	stamped := 0
	for _, entry := range list.Items {
		e, _ := entry.(*jsonx.Object)
		if e == nil {
			continue
		}
		systems, _ := e.Value("systems").(*jsonx.Array)
		if systems == nil {
			continue
		}
		for _, item := range systems.Items {
			o, _ := item.(*jsonx.Object)
			if o == nil || jsonx.ToString(o.Value("type")) != "Audio" {
				continue
			}
			if bars, _ := o.Value("bars").(*jsonx.Array); bars != nil {
				stamped += stampBarIDs(bars)
			}
		}
	}
	if stamped == 0 {
		return nil
	}
	return []string{fmt.Sprintf("%d OSD Audio bar(s) got an id", stamped)}
}

// itemIDPattern is ItemId's pattern, frozen here as a step's view of the
// schema
var itemIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

// stampBarIDs gives every bar of bars without an id of its own (none, or
// one an earlier bar has, or one that isn't an id) a free one; how many it gave.
func stampBarIDs(bars *jsonx.Array) int {
	// The ids the bars keep: each one's first holder
	taken := map[string]bool{}
	keeps := make([]bool, len(bars.Items))
	for i, item := range bars.Items {
		bar, _ := item.(*jsonx.Object)
		if bar == nil {
			continue
		}
		if id, _ := bar.Value("id").(string); itemIDPattern.MatchString(id) && !taken[id] {
			taken[id] = true
			keeps[i] = true
		}
	}
	stamped := 0
	for i, item := range bars.Items {
		bar, _ := item.(*jsonx.Object)
		if bar == nil || keeps[i] {
			continue
		}
		base, _ := bar.Value("type").(string)
		if !itemIDPattern.MatchString(base) {
			base = "bar"
		}
		bar.Set("id", freeID(base, taken))
		stamped++
	}
	return stamped
}
