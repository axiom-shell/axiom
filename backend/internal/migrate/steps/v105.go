package steps

import (
	"fmt"
	"math"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// moduleHosts are the sections whose layouts hold modules (Overlay and
// Menus items' layouts, Desktop's modules, the lock screen's and the
// greeter's layouts).
var moduleHosts = []string{"Overlay", "Menus", "Desktop", "Lockscreen", "Greeter"}

// v105 is the config audit's renames, moves and re-defaults:
//   - Bars.items[].location became edge;
//   - the Network widget's showName became showDevice, the Login module's
//     showAvatar showPicture, Bluetooth's lowBattery / criticalBattery
//     lowThreshold / criticalThreshold, the Updates widget's manyThreshold
//     / manyColor warnThreshold / warnColor;
//   - the Updates widget's and module's check interval became one
//     Updates.interval (the smallest one set off its default; none, the
//     default stays);
//   - WindowBehaviour.noWarps became warpCursor, inverted;
//   - the Workspaces widget's textColor became foregroundColor and its
//     activeWorkspaceIcons keep/hide true/false; its head (`lead`) is gone:
//     an icon head keeps its leadIcon, any other has none, and
//     showActiveIcon with it;
//   - the Time widget's head none became auto;
//   - an OSD system's tiles (Battery, Audio), keys (LockKeys) and kinds
//     (Privacy) became shows;
//   - the Media widget's idleText "No player" (its old default) became
//     empty, which says it translated;
//   - a bar widget's (and a custom widget's) appearance.width 0 became null
//     (Auto);
//   - Interface.radius became Appearance.shape.innerRadius,
//     WindowLook.surfaceBlur Appearance.surface.blur and
//     Compositor.sway.specialWorkspaces Workspaces.specialWorkspaces;
//   - a per-app notification rule's timeout 0 (Auto already) became null;
//   - values at settings that now step (idle timeouts, intervals, Pomodoro
//     lengths, …) were rounded to the step.
//
// Each part acts on the old shape only, so a second run changes nothing.
func v105(cfg *jsonx.Object) []string {
	var changes []string
	note := func(n int, what string) {
		if n > 0 {
			changes = append(changes, fmt.Sprintf("%d %s", n, what))
		}
	}
	bars := cfg.Value("Bars")
	widgets := func(typ string, fn func(props *jsonx.Object) bool) int {
		return eachTyped(bars, typ, fn)
	}
	modules := func(typ string, fn func(props *jsonx.Object) bool) int {
		n := 0
		for _, host := range moduleHosts {
			n += eachTyped(cfg.Value(host), typ, fn)
		}
		return n
	}

	if bars, _ := bars.(*jsonx.Object); bars != nil {
		if items, _ := bars.Value("items").(*jsonx.Array); items != nil {
			n := 0
			for _, item := range items.Items {
				if bar, _ := item.(*jsonx.Object); bar != nil && renameInPlace(bar, "location", "edge") {
					n++
				}
			}
			note(n, "bar(s): location became edge")
		}
	}

	note(widgets("Network", func(p *jsonx.Object) bool { return renameInPlace(p, "showName", "showDevice") }), "Network widget(s): showName became showDevice")
	note(modules("Login", func(p *jsonx.Object) bool { return renameInPlace(p, "showAvatar", "showPicture") }), "Login module(s): showAvatar became showPicture")
	if bt := object(cfg, "Bluetooth"); bt != nil {
		a, b := renameInPlace(bt, "lowBattery", "lowThreshold"), renameInPlace(bt, "criticalBattery", "criticalThreshold")
		if a || b {
			changes = append(changes, "Bluetooth: lowBattery and criticalBattery became lowThreshold and criticalThreshold")
		}
	}
	note(widgets("Updates", func(p *jsonx.Object) bool {
		a, b := renameInPlace(p, "manyThreshold", "warnThreshold"), renameInPlace(p, "manyColor", "warnColor")
		return a || b
	}), "Updates widget(s): manyThreshold and manyColor became warnThreshold and warnColor")
	changes = append(changes, updatesInterval(cfg, widgets, modules)...)

	if wb := object(cfg, "WindowBehaviour"); wb != nil {
		if no, ok := wb.Value("noWarps").(bool); ok {
			if !wb.Has("warpCursor") {
				wb.Set("warpCursor", !no)
			}
			wb.Delete("noWarps")
			changes = append(changes, "WindowBehaviour.noWarps became warpCursor (inverted)")
		}
	}

	note(widgets("Workspaces", workspacesWidget), "Workspaces widget(s): textColor, activeWorkspaceIcons and the head changed")
	note(widgets("Time", func(p *jsonx.Object) bool {
		if p.Value("lead") != "none" {
			return false
		}
		p.Set("lead", "auto")
		return true
	}), "Time widget(s): head none became auto")
	changes = append(changes, osdShows(cfg)...)
	note(widgets("Media", func(p *jsonx.Object) bool {
		if p.Value("idleText") != "No player" {
			return false
		}
		p.Set("idleText", "")
		return true
	}), "Media widget(s): idleText No player became empty")

	autoWidth := func(appearance any) bool {
		a, _ := appearance.(*jsonx.Object)
		if a == nil {
			return false
		}
		if w, ok := a.Value("width").(float64); ok && w == 0 {
			a.Set("width", nil)
			return true
		}
		return false
	}
	n := eachProps(bars, func(p *jsonx.Object) bool { return autoWidth(p.Value("appearance")) })
	if defs := object(cfg, "CustomWidgets"); defs != nil {
		if items, _ := defs.Value("items").(*jsonx.Array); items != nil {
			for _, item := range items.Items {
				if def, _ := item.(*jsonx.Object); def != nil && autoWidth(def.Value("bar")) {
					n++
				}
			}
		}
	}
	note(n, "widget(s): appearance.width 0 became Auto")

	changes = append(changes, moves(cfg)...)

	if notif := object(cfg, "Notifications"); notif != nil {
		if apps, _ := notif.Value("apps").(*jsonx.Array); apps != nil {
			n := 0
			for _, item := range apps.Items {
				if rule, _ := item.(*jsonx.Object); rule != nil {
					if t, ok := rule.Value("timeout").(float64); ok && t == 0 {
						rule.Set("timeout", nil)
						n++
					}
				}
			}
			note(n, "per-app notification rule(s): timeout 0 became Auto")
		}
	}

	note(roundSteps(cfg, widgets), "value(s) rounded to their new step")
	return changes
}

// renameInPlace renames key `from` of o to `to`, in its place; false when o
// has no `from`. Where `to` is set already, that stays and `from` is just
// dropped.
func renameInPlace(o *jsonx.Object, from, to string) bool {
	if !o.Has(from) {
		return false
	}
	if o.Has(to) {
		o.Delete(from)
		return true
	}
	keys := o.Keys()
	values := make([]any, len(keys))
	for i, k := range keys {
		values[i], _ = o.Get(k)
		o.Delete(k)
	}
	for i, k := range keys {
		if k == from {
			k = to
		}
		o.Set(k, values[i])
	}
	return true
}

// eachTyped runs fn on the `properties` of every item of v (an object or
// list, at any depth, group widgets' too) whose `type` is typ; how many
// it said it changed.
func eachTyped(v any, typ string, fn func(props *jsonx.Object) bool) int {
	n := 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil && t.Value("type") == typ && fn(props) {
				n++
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
	walk(v)
	return n
}

// eachProps is eachTyped for every type.
func eachProps(v any, fn func(props *jsonx.Object) bool) int {
	n := 0
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, _ := t.Value("properties").(*jsonx.Object); props != nil && jsonx.ToString(t.Value("type")) != "" && fn(props) {
				n++
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
	walk(v)
	return n
}

// updatesInterval moves the Updates widgets' and modules' `interval` to
// Updates.interval: the smallest one off its host's default (30 min for a
// widget, 60 for a module); none, the section's default (30 min) stays.
func updatesInterval(cfg *jsonx.Object, widgets, modules func(string, func(*jsonx.Object) bool) int) []string {
	smallest := math.Inf(1)
	take := func(def float64) func(*jsonx.Object) bool {
		return func(p *jsonx.Object) bool {
			v, ok := p.Get("interval")
			if !ok {
				return false
			}
			if f, isNum := v.(float64); isNum && f != def && f < smallest {
				smallest = f
			}
			p.Delete("interval")
			return true
		}
	}
	n := widgets("Updates", take(1800000)) + modules("Updates", take(3600000))
	if n == 0 {
		return nil
	}
	changes := []string{fmt.Sprintf("%d Updates widget(s) and module(s): interval moved to Updates.interval", n)}
	if !math.IsInf(smallest, 1) {
		section := object(cfg, "Updates")
		if section == nil {
			section = jsonx.NewObject()
			cfg.Set("Updates", section)
		}
		if !section.Has("interval") {
			section.Set("interval", smallest)
		}
	}
	return changes
}

// workspacesWidget applies the Workspaces widget's changes to its
// properties: textColor, activeWorkspaceIcons, and the head.
func workspacesWidget(p *jsonx.Object) bool {
	changed := renameInPlace(p, "textColor", "foregroundColor")
	switch p.Value("activeWorkspaceIcons") {
	case "keep":
		p.Set("activeWorkspaceIcons", true)
		changed = true
	case "hide":
		p.Set("activeWorkspaceIcons", false)
		changed = true
	}
	if lead, ok := p.Get("lead"); ok {
		// An icon head keeps its icon (the old default, grid_view, where it
		// had none set); any other had none
		if lead == "icon" {
			if !p.Has("leadIcon") {
				p.Set("leadIcon", "grid_view")
			}
		} else {
			p.Set("leadIcon", "")
		}
		p.Delete("lead")
		changed = true
	}
	if p.Delete("showActiveIcon") {
		changed = true
	}
	return changed
}

// osdShows renames the pick lists of an OSD's systems to `shows`.
func osdShows(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	items, _ := osd.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	old := map[string]string{"Battery": "tiles", "Audio": "tiles", "LockKeys": "keys", "Privacy": "kinds"}
	n := 0
	for _, item := range items.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil {
			continue
		}
		systems, _ := entry.Value("systems").(*jsonx.Array)
		if systems == nil {
			continue
		}
		for _, s := range systems.Items {
			system, _ := s.(*jsonx.Object)
			if system == nil {
				continue
			}
			if key, ok := old[jsonx.ToString(system.Value("type"))]; ok && renameInPlace(system, key, "shows") {
				n++
			}
		}
	}
	if n == 0 {
		return nil
	}
	return []string{fmt.Sprintf("%d OSD system(s): tiles, keys or kinds became shows", n)}
}

// moves carries the three settings that changed section.
func moves(cfg *jsonx.Object) []string {
	var changes []string
	// ensure is the object at path in cfg, made (with its parents) when
	// missing; nil where a part is something else.
	ensure := func(path ...string) *jsonx.Object {
		o := cfg
		for _, k := range path {
			if v, ok := o.Get(k); ok {
				next, _ := v.(*jsonx.Object)
				if next == nil {
					return nil
				}
				o = next
				continue
			}
			next := jsonx.NewObject()
			o.Set(k, next)
			o = next
		}
		return o
	}
	if iface := object(cfg, "Interface"); iface != nil && iface.Has("radius") {
		radius, _ := iface.Get("radius")
		iface.Delete("radius")
		// null follows the main radius, as the new setting's does
		if radius != nil {
			if shape := ensure("Appearance", "shape"); shape != nil && !shape.Has("innerRadius") {
				shape.Set("innerRadius", radius)
			}
		}
		changes = append(changes, "Interface.radius moved to Appearance.shape.innerRadius")
	}
	if look := object(cfg, "WindowLook"); look != nil {
		if blur, ok := look.Value("surfaceBlur").(*jsonx.Object); ok {
			look.Delete("surfaceBlur")
			if surface := ensure("Appearance", "surface"); surface != nil && !surface.Has("blur") {
				surface.Set("blur", blur)
			}
			changes = append(changes, "WindowLook.surfaceBlur moved to Appearance.surface.blur")
		}
	}
	if sway := object(cfg, "Compositor", "sway"); sway != nil {
		if mode, ok := sway.Value("specialWorkspaces").(string); ok {
			sway.Delete("specialWorkspaces")
			if ws := ensure("Workspaces"); ws != nil && !ws.Has("specialWorkspaces") {
				ws.Set("specialWorkspaces", mode)
			}
			changes = append(changes, "Compositor.sway.specialWorkspaces moved to Workspaces.specialWorkspaces")
		}
	}
	return changes
}

// stepped is a setting that now takes only multiples of a unit (ms): the
// path from its section, and the unit.
type stepped struct {
	path []string
	unit float64
}

// roundTo rounds v to the nearest multiple of unit, never a positive
// value to 0 (which would mean never); whether it changed.
func roundTo(o *jsonx.Object, key string, unit float64) bool {
	v, ok := o.Value(key).(float64)
	if !ok || v <= 0 || math.IsInf(v, 0) || math.IsNaN(v) {
		return false
	}
	n := math.Floor(v/unit + 0.5)
	if n < 1 {
		n = 1
	}
	if r := n * unit; r != v {
		o.Set(key, r)
		return true
	}
	return false
}

// roundSteps rounds the values at settings that gained a step; how many it
// changed.
func roundSteps(cfg *jsonx.Object, widgets func(string, func(*jsonx.Object) bool) int) int {
	n := 0
	for _, s := range []stepped{
		{[]string{"WindowBehaviour", "cursorHideTimeout"}, 1000},
		{[]string{"Idle", "dim", "timeout"}, 1000},
		{[]string{"Idle", "lock", "timeout"}, 1000},
		{[]string{"Idle", "screenOff", "timeout"}, 1000},
		{[]string{"Idle", "suspend", "timeout"}, 1000},
		{[]string{"Appearance", "wallpaper", "rotation", "interval"}, 60000},
		{[]string{"Pomodoro", "work"}, 60000},
		{[]string{"Pomodoro", "shortBreak"}, 60000},
		{[]string{"Pomodoro", "longBreak"}, 60000},
		{[]string{"ClaudeUsage", "interval"}, 60000},
	} {
		if parent := object(cfg, s.path[:len(s.path)-1]...); parent != nil && roundTo(parent, s.path[len(s.path)-1], s.unit) {
			n++
		}
	}
	if idle := object(cfg, "Idle"); idle != nil {
		if items, _ := idle.Value("items").(*jsonx.Array); items != nil {
			for _, item := range items.Items {
				if rule, _ := item.(*jsonx.Object); rule != nil && roundTo(rule, "timeout", 1000) {
					n++
				}
			}
		}
	}
	n += widgets("NextEvent", func(p *jsonx.Object) bool { return roundTo(p, "lookahead", 60000) })
	n += widgets("Markets", func(p *jsonx.Object) bool { return roundTo(p, "rotateInterval", 1000) })
	return n
}
