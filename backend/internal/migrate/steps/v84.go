package steps

import "github.com/axiom-shell/axiom/backend/internal/jsonx"

// v84: Notifications.position (a corner) became an edge and a place along
// it, as the OSD's, dock's and launcher's are, held off the edge as the
// corner toasts were (detached); its per-side gaps became one gap, the
// corner's side one when they weren't even (the old default, 12, becomes
// the new one, Auto).
func v84(cfg *jsonx.Object) []string {
	n := object(cfg, "Notifications")
	if n == nil {
		return nil
	}
	corner, isCorner := n.Value("position").(string)
	gaps, _ := n.Value("gaps").(*jsonx.Object)
	if !isCorner && gaps == nil {
		return nil
	}
	// The old default, left out of a file written by hand
	if !n.Has("position") {
		corner, isCorner = "topLeft", true
	}
	var changes []string
	if isCorner {
		places := map[string][2]any{
			"topLeft":     {"top", 0.0},
			"topRight":    {"top", 100.0},
			"bottomLeft":  {"bottom", 0.0},
			"bottomRight": {"bottom", 100.0},
		}
		place, known := places[corner]
		if !known {
			place = places["topLeft"]
		}
		n.Set("edge", place[0])
		n.Set("position", place[1])
		n.Set("detached", true)
		changes = append(changes, "Notifications.position ("+corner+") became Notifications.edge, position and detached")
	}
	if gaps != nil {
		key := "all"
		if gaps.Value("even") == false {
			key = "left"
			if corner == "topRight" || corner == "bottomRight" {
				key = "right"
			}
		}
		if gap, isNum := gaps.Value(key).(float64); isNum && gap != 12 {
			n.Set("gap", gap)
		}
		n.Delete("gaps")
		changes = append(changes, "Notifications.gaps became one gap")
	}
	return changes
}
