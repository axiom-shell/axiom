package steps

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v96: the settings overhaul.
//
//   - Clocks follow one 12/24-hour setting (DateTime.hourFormat): each
//     clock's `use24Hour` became `hourFormat`, "default" (follow it) where
//     it was its type's old default, else "12" or "24" as it was. The old
//     defaults: the bar Time widget 12-hour, the Clock, ClockCalendar and
//     World clocks modules and Calendar's event times 24-hour.
//   - Apps.terminal, Apps.fileManager and Apps.browser moved into
//     Apps.commands (a custom command per default app role, in place of
//     the default app the mimeapps lists name), set where they were: the
//     old default terminal, "kitty", is dropped, so the default terminal
//     is the one the system says (kitty, where it was).
func v96(cfg *jsonx.Object) []string {
	var changes []string
	clocks := 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil {
				if old, ok := oldHourDefaults[jsonx.ToString(t.Value("type"))]; ok && hourFormat(props, old) {
					clocks++
				}
			}
			for _, k := range t.Keys() {
				walk(t.Value(k))
			}
		case *jsonx.Array:
			for _, item := range t.Items {
				walk(item)
			}
		}
	}
	walk(cfg)
	if clocks > 0 {
		changes = append(changes, fmt.Sprintf("%d clock(s): use24Hour became hourFormat (default follows Date & time where it was the old default)", clocks))
	}
	if cal := object(cfg, "Calendar"); cal != nil && hourFormat(cal, true) {
		changes = append(changes, "Calendar.use24Hour became Calendar.hourFormat")
	}
	if apps := object(cfg, "Apps"); apps != nil {
		changes = append(changes, appCommands(apps)...)
	}
	return changes
}

// appCommands moves Apps' terminal, fileManager and browser into
// Apps.commands, the ones set (and not the old default terminal).
func appCommands(apps *jsonx.Object) []string {
	var changes []string
	var commands *jsonx.Object
	for _, role := range []string{"terminal", "fileManager", "browser"} {
		if !apps.Has(role) {
			continue
		}
		v := strings.TrimSpace(jsonx.ToString(apps.Value(role)))
		apps.Delete(role)
		if role == "terminal" && v == "kitty" {
			changes = append(changes, `Apps.terminal "kitty" (the old default) dropped: the default terminal starts`)
			continue
		}
		if v == "" {
			continue
		}
		if commands == nil {
			if commands, _ = apps.Value("commands").(*jsonx.Object); commands == nil {
				commands = jsonx.NewObject()
				apps.Set("commands", commands)
			}
		}
		commands.Set(role, v)
		changes = append(changes, fmt.Sprintf("Apps.%s became Apps.commands.%s", role, role))
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
