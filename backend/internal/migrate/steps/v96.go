package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v96: the settings overhaul.
//
//   - Clocks follow one 12/24-hour setting (DateTime.hourFormat): each
//     clock's `use24Hour` became `hourFormat`, "default" (follow it) where
//     it was its type's old default, else "12" or "24" as it was. The old
//     defaults: the bar Time widget 12-hour, the Clock, ClockCalendar and
//     World clocks modules and Calendar's event times 24-hour.
//   - Apps.terminal, Apps.fileManager and Apps.browser are commands in
//     place of the default apps (mimeapps.list), empty by default: the old
//     default terminal, "kitty", became empty, so the default terminal is
//     the one the system says (kitty, where it was).
func v96(cfg *jsonx.Object) []string {
	var changes []string
	clocks := 0
	var walk func(v any, inBar bool)
	walk = func(v any, inBar bool) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil {
				if old, ok := oldHourDefaults[jsonx.ToString(t.Value("type"))]; ok && hourFormat(props, old) {
					clocks++
				}
			}
			for _, k := range t.Keys() {
				walk(t.Value(k), inBar)
			}
		case *jsonx.Array:
			for _, item := range t.Items {
				walk(item, inBar)
			}
		}
	}
	walk(cfg, false)
	if clocks > 0 {
		changes = append(changes, fmt.Sprintf("%d clock(s): use24Hour became hourFormat (default follows Date & time where it was the old default)", clocks))
	}
	if cal := object(cfg, "Calendar"); cal != nil && hourFormat(cal, true) {
		changes = append(changes, "Calendar.use24Hour became Calendar.hourFormat")
	}
	if apps := object(cfg, "Apps"); apps != nil && apps.Value("terminal") == "kitty" {
		apps.Set("terminal", "")
		changes = append(changes, `Apps.terminal "kitty" (the old default) became empty: the default terminal starts`)
	}
	return changes
}

// oldHourDefaults are the clock types' use24Hour defaults as of v95, by
// type: frozen here, as a step's view of the schema
var oldHourDefaults = map[string]bool{"Time": false, "Clock": true, "ClockCalendar": true, "WorldClocks": true}

// hourFormat turns o's use24Hour into hourFormat in its place: "default"
// for the old default, else "12" / "24"; whether o had one.
func hourFormat(o *jsonx.Object, oldDefault bool) bool {
	if !o.Has("use24Hour") {
		return false
	}
	v, isBool := o.Value("use24Hour").(bool)
	format := "default"
	if isBool && v != oldDefault {
		format = map[bool]string{true: "24", false: "12"}[v]
	}
	renamed := renameKey(o, "use24Hour", "hourFormat")
	*o = *renamed
	o.Set("hourFormat", format)
	return true
}
