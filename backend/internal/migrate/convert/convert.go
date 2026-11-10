// Package convert turns a format-1 config at its last version (75, as the
// legacy migrations leave it) into format 2 at version 76: the unified
// shape of docs/dev/core/config-manager.md. It runs once per file; the format-2
// pipeline (defaults, pruning, validation) follows it. Pure: no I/O.
package convert

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The format and version a converted config gets
const (
	Format  = 2
	Version = 76
)

// Result is a converted config and what was done (English, for the log).
type Result struct {
	Config  *jsonx.Object
	Changes []string
}

// ToV2 converts in (format 1, version 75) to format 2. in isn't changed.
func ToV2(in *jsonx.Object) Result {
	c := &converter{cfg: jsonx.Clone(in).(*jsonx.Object)}
	c.run()
	return Result{Config: c.cfg, Changes: c.changes}
}

type converter struct {
	cfg     *jsonx.Object
	changes []string
}

func (c *converter) note(format string, args ...any) {
	c.changes = append(c.changes, fmt.Sprintf(format, args...))
}

func (c *converter) run() {
	cfg := c.cfg
	cfg.Delete("format")
	cfg.Set("format", float64(Format))
	cfg.Set("version", float64(Version))

	c.general()
	c.launcher()
	c.notifications()
	c.idle()
	c.calendar()
	c.simpleUnits()
	c.ids()
	c.appearance()
	c.interfaceSection()
	c.popouts()
	c.collections()
	c.bars()
	c.edgeMenus()
	c.desktop()
	c.screenLayouts()
	c.compositor()
	c.input()
	c.windowLook()
	c.overlayViews()
	c.order()
	c.note("converted to config format 2 (version %d)", Version)
}

// --------------------------------------------------------------- helpers

// section is cfg[name] as an object (nil when missing or not one).
func (c *converter) section(name string) *jsonx.Object {
	o, _ := c.cfg.Value(name).(*jsonx.Object)
	return o
}

func obj(v any) *jsonx.Object {
	o, _ := v.(*jsonx.Object)
	return o
}

func arr(v any) *jsonx.Array {
	a, _ := v.(*jsonx.Array)
	return a
}

// take removes key from o and returns its value.
func take(o *jsonx.Object, key string) (any, bool) {
	if o == nil {
		return nil, false
	}
	v, ok := o.Get(key)
	if ok {
		o.Delete(key)
	}
	return v, ok
}

// group moves o's keys into o[name] (made where the first of them was):
// pairs of old key, new key; values are carried as they are, and a
// missing key is left out.
func group(o *jsonx.Object, name string, pairs ...string) *jsonx.Object {
	if o == nil {
		return nil
	}
	g := jsonx.NewObject()
	at := -1
	keys := o.Keys()
	for i := 0; i < len(pairs); i += 2 {
		for j, k := range keys {
			if k == pairs[i] && (at < 0 || j < at) {
				at = j
			}
		}
	}
	for i := 0; i < len(pairs); i += 2 {
		if v, ok := take(o, pairs[i]); ok {
			g.Set(pairs[i+1], v)
		}
	}
	if g.Len() > 0 {
		insertAt(o, name, g, at)
	}
	return g
}

// insertAt sets key to v at position at of o's keys (the end when at < 0
// or past it), keeping the other keys' order.
func insertAt(o *jsonx.Object, key string, v any, at int) {
	keys := o.Keys()
	if at < 0 || at >= len(keys) {
		o.Set(key, v)
		return
	}
	rest := make([][2]any, 0, len(keys)-at)
	for _, k := range keys[at:] {
		if k == key {
			continue
		}
		rest = append(rest, [2]any{k, o.Value(k)})
		o.Delete(k)
	}
	o.Set(key, v)
	for _, kv := range rest {
		o.Set(kv[0].(string), kv[1])
	}
}

// rename renames o's key in place.
func rename(o *jsonx.Object, from, to string) {
	if o == nil || !o.Has(from) {
		return
	}
	keys := o.Keys()
	at := -1
	for i, k := range keys {
		if k == from {
			at = i
		}
	}
	v, _ := take(o, from)
	insertAt(o, to, v, at)
}

// scale multiplies a number by factor (durations to ms), leaving anything
// else as it is.
func scale(o *jsonx.Object, key string, factor float64) {
	if o == nil {
		return
	}
	if n, ok := o.Value(key).(float64); ok {
		o.Set(key, math.Round(n*factor))
	}
}

func lowerFirst(o *jsonx.Object, key string) {
	if o == nil {
		return
	}
	if s, ok := o.Value(key).(string); ok && s != "" {
		o.Set(key, strings.ToLower(s[:1])+s[1:])
	}
}

func items(o *jsonx.Object, key string) []*jsonx.Object {
	a := arr(o.Value(key))
	if a == nil {
		return nil
	}
	var out []*jsonx.Object
	for _, v := range a.Items {
		if ob := obj(v); ob != nil {
			out = append(out, ob)
		}
	}
	return out
}

// screen is a ScreenTarget.
func screen(mode string, names ...string) *jsonx.Object {
	list := jsonx.Arr()
	for _, n := range names {
		list.Append(n)
	}
	return jsonx.Obj("mode", mode, "names", list)
}

// monitorScreen is the target a format-1 monitor name meant: "" the
// primary monitor, "*" every one, else that one.
func monitorScreen(v any) *jsonx.Object {
	name, _ := v.(string)
	switch name {
	case "":
		return screen("primary")
	case "*":
		return screen("all")
	}
	return screen("named", name)
}

// --------------------------------------------------------------- sections

func (c *converter) general() {
	g := c.section("General")
	if g == nil {
		return
	}
	if v, ok := g.Get("monitors"); ok {
		mode, _ := v.(string)
		rename(g, "monitors", "screen")
		g.Set("screen", jsonx.Obj("mode", mode))
	}
	// A section's own monitors: "general" is the inherit of a ScreenTarget
	for _, name := range []string{"Launcher", "PowerMenu", "Notifications", "Overlay"} {
		s := c.section(name)
		if s == nil || !s.Has("monitors") {
			continue
		}
		mode, _ := s.Value("monitors").(string)
		if mode == "general" {
			mode = "inherit"
		}
		rename(s, "monitors", "screen")
		// these follow General or pick a monitor by role, never by name
		s.Set("screen", jsonx.Obj("mode", mode))
	}
	c.note("monitors settings became screen targets")
}

func (c *converter) launcher() {
	l := c.section("Launcher")
	if l == nil {
		return
	}
	lowerFirst(l, "edge")
	p := group(l, "providers", "windows", "windows", "calculator", "calculator", "commands", "commands",
		"runCommands", "run", "webSearch", "web", "searchEngine", "webEngine", "chat", "chat",
		"clipboard", "clipboard", "clipboardSource", "clipboardSource", "clipboardMaxEntries", "clipboardMaxEntries", "emoji", "emoji")
	web := jsonx.NewObject()
	if v, ok := take(p, "web"); ok {
		web.Set("enabled", v)
	}
	if v, ok := take(p, "webEngine"); ok {
		web.Set("engine", v)
	}
	clip := jsonx.NewObject()
	if v, ok := take(p, "clipboard"); ok {
		clip.Set("enabled", v)
	}
	if v, ok := take(p, "clipboardSource"); ok {
		clip.Set("source", v)
	}
	if v, ok := take(p, "clipboardMaxEntries"); ok {
		clip.Set("maxEntries", v)
	}
	ordered := jsonx.NewObject()
	for _, k := range []string{"windows", "calculator", "commands", "run", "web", "chat", "clipboard", "emoji"} {
		switch k {
		case "web":
			ordered.Set(k, web)
		case "clipboard":
			ordered.Set(k, clip)
		default:
			if v, ok := p.Get(k); ok {
				ordered.Set(k, v)
			}
		}
	}
	l.Set("providers", ordered)
}

func (c *converter) notifications() {
	n := c.section("Notifications")
	if n == nil {
		return
	}
	group(n, "gaps", "evenGaps", "even", "gap", "all", "gapTop", "top", "gapBottom", "bottom", "gapLeft", "left", "gapRight", "right")
	scale(n, "timeout", 1000)
	rename(n, "maxAgeDays", "maxAge")
	scale(n, "maxAge", 86400000)
}

func (c *converter) idle() {
	i := c.section("Idle")
	if i == nil {
		return
	}
	for _, k := range []string{"dimTimeout", "lockTimeout", "screenOffTimeout", "suspendTimeout"} {
		scale(i, k, 1000)
	}
	group(i, "dim", "dimTimeout", "timeout", "dimMode", "mode", "dimLevel", "level", "dimBy", "by")
	group(i, "lock", "lockTimeout", "timeout")
	group(i, "screenOff", "screenOffTimeout", "timeout")
	group(i, "suspend", "suspendTimeout", "timeout")
	rename(i, "listeners", "items")
	for _, l := range items(i, "items") {
		scale(l, "timeout", 1000)
	}
}

func (c *converter) calendar() {
	cal := c.section("Calendar")
	if cal == nil {
		return
	}
	for _, k := range []string{"defaultDuration", "defaultReminder", "syncInterval"} {
		scale(cal, k, 60000)
	}
	rename(cal, "accounts", "items")
	// What was fetched (a calendar's name, server color, read-only flag,
	// components) is the calendar cache's now: the next sync fills it. A
	// local calendar's name is the user's own, kept.
	for _, account := range items(cal, "items") {
		local := account.Value("kind") == "local"
		for _, entry := range items(account, "calendars") {
			for _, k := range entry.Keys() {
				if k != "href" && k != "color" && k != "enabled" && !(k == "name" && local) {
					entry.Delete(k)
				}
			}
		}
	}
}

func (c *converter) simpleUnits() {
	if w := c.section("Weather"); w != nil {
		rename(w, "intervalMinutes", "interval")
		scale(w, "interval", 60000)
	}
	if u := c.section("ClaudeUsage"); u != nil {
		rename(u, "intervalMinutes", "interval")
		scale(u, "interval", 60000)
		rename(u, "accounts", "items")
	}
	if p := c.section("Pomodoro"); p != nil {
		for _, k := range [][2]string{{"workMinutes", "work"}, {"shortBreakMinutes", "shortBreak"}, {"longBreakMinutes", "longBreak"}} {
			rename(p, k[0], k[1])
			scale(p, k[1], 60000)
		}
	}
	if wb := c.section("WindowBehaviour"); wb != nil {
		scale(wb, "cursorHideTimeout", 1000)
	}
	if m := c.section("Monitors"); m != nil {
		rename(m, "profiles", "items")
	}
	if w := c.section("Workspaces"); w != nil {
		for _, s := range items(w, "strips") {
			if v, ok := s.Get("monitor"); ok {
				rename(s, "monitor", "screen")
				s.Set("screen", monitorScreen(v))
			}
		}
	}
	if g := c.section("Greeter"); g != nil {
		if v, ok := g.Get("monitor"); ok {
			rename(g, "monitor", "screen")
			s := monitorScreen(v)
			if s.Value("mode") == "all" {
				s.Set("mode", "primary")
			}
			g.Set("screen", s)
		}
	}
}

func (c *converter) appearance() {
	a := c.section("Appearance")
	if a == nil {
		return
	}
	theme := jsonx.NewObject()
	at := indexOf(a, "theme")
	if v, ok := take(a, "theme"); ok {
		theme.Set("name", v)
	}
	if v, ok := take(a, "themeSchedule"); ok {
		theme.Set("schedule", v)
	}
	insertAt(a, "theme", theme, at)

	wall := jsonx.NewObject()
	at = indexOf(a, "wallpaper")
	for _, kv := range [][2]string{{"wallpaperMode", "mode"}, {"wallpaper", "file"}, {"wallpapers", "perScreen"},
		{"wallpaperFolder", "folder"}, {"wallpaperRotation", "rotation"}, {"variantWallpapers", "variants"},
		{"wallpaperBackend", "backend"}, {"wallpaperDaemon", "daemon"}} {
		if v, ok := take(a, kv[0]); ok {
			wall.Set(kv[1], v)
		}
	}
	scale(obj(wall.Value("rotation")), "interval", 60000)
	insertAt(a, "wallpaper", wall, at)
}

func indexOf(o *jsonx.Object, key string) int {
	for i, k := range o.Keys() {
		if k == key {
			return i
		}
	}
	return -1
}

// interfaceSection: Widget is Interface, its radius null unless overridden
func (c *converter) interfaceSection() {
	w := c.section("Widget")
	if w == nil {
		return
	}
	rename(c.cfg, "Widget", "Interface")
	override, _ := take(w, "overrideRadius")
	if override != true {
		w.Set("radius", nil)
	}
}

func (c *converter) popouts() {
	p := c.section("Popouts")
	if p == nil {
		return
	}
	group(p, "timing", "openDelay", "openDelay", "dismissDelay", "closeDelay")
	group(p, "trigger", "edgeTriggerSize", "size")
}

// collections: Dock and OSD entries
func (c *converter) collections() {
	if o := c.section("OSD"); o != nil {
		rename(o, "osds", "items")
		for _, e := range items(o, "items") {
			c.entryScreen(e)
			lowerFirst(e, "edge")
			lowerFirst(e, "orientation")
		}
	}
	if d := c.section("Dock"); d != nil {
		rename(d, "docks", "items")
		for _, e := range items(d, "items") {
			c.entryScreen(e)
			lowerFirst(e, "edge")
			group(e, "timing", "openDelay", "openDelay", "closeDelay", "closeDelay")
			group(e, "trigger", "triggerSize", "size")
			group(e, "magnify", "magnify", "enabled", "magnifiedSize", "size", "magnifyRange", "range")
			group(e, "running", "showRunning", "show", "windowScope", "scope", "runningIndicator", "indicator", "separator", "separator")
		}
	}
}

// entryScreen: a Dock or OSD entry's monitors (general|primary|focused|
// all|monitor) and monitor
func (c *converter) entryScreen(e *jsonx.Object) {
	mode, _ := e.Value("monitors").(string)
	name, _ := e.Value("monitor").(string)
	at := indexOf(e, "monitors")
	take(e, "monitors")
	take(e, "monitor")
	var s *jsonx.Object
	switch mode {
	case "general", "":
		s = screen("inherit")
	case "monitor":
		s = screen("named", name)
	default:
		s = screen(mode)
	}
	insertAt(e, "screen", s, at)
}

// The keys a bar's style holds, by the format-1 switch that overrode them
var barStyleKeys = [][]string{
	{"overrideWidgetStyle", "widgetStyle", "tintOpacity", "outlineWidth", "lineWidth", "lineSide", "widgetShape", "widgetGrouping", "widgetEnds", "groupColor", "widgetTextColor"},
	{"overrideAccents", "separatorStyle", "separatorColor", "separatorThickness", "separatorGap", "accentLine", "accentLineColor", "accentLineFade", "accentLineWidth"},
	{"overrideFontSize", "fontSize"},
	{"overrideRadius", "widgetRadius"},
}

// barStyle is a BarStyle from the format-1 section or a bar: its shadow
// grouped, and (for a bar) every key it didn't override null.
func barStyle(src *jsonx.Object, isBar bool) *jsonx.Object {
	style := jsonx.NewObject()
	style.Set("fontSize", nil)
	style.Set("widgetRadius", nil)
	for _, set := range barStyleKeys {
		on := !isBar || src.Value(set[0]) == true
		for _, k := range set[1:] {
			if k == "fontSize" || k == "widgetRadius" {
				if isBar && on {
					style.Set(k, src.Value(k))
				}
				continue
			}
			if on {
				if v, ok := src.Get(k); ok {
					style.Set(k, v)
				}
			} else {
				style.Set(k, nil)
			}
		}
	}
	shadowOn := !isBar || src.Value("overrideShadow") == true
	shadow := jsonx.NewObject()
	for _, kv := range [][2]string{{"shadow", "enabled"}, {"shadowColor", "color"}, {"shadowSize", "size"}} {
		if shadowOn {
			if v, ok := src.Get(kv[0]); ok {
				shadow.Set(kv[1], v)
			}
		} else {
			shadow.Set(kv[1], nil)
		}
	}
	style.Set("shadow", shadow)
	return style
}

func (c *converter) bars() {
	sectionStyle := c.section("BarStyle")
	c.cfg.Delete("BarStyle")
	list := arr(c.cfg.Value("Bars"))
	bars := jsonx.NewObject()
	if sectionStyle != nil {
		bars.Set("style", barStyle(sectionStyle, false))
	}
	if list != nil {
		for _, v := range list.Items {
			b := obj(v)
			if b == nil {
				continue
			}
			c.bar(b)
		}
		bars.Set("items", list)
	}
	at := indexOf(c.cfg, "Bars")
	c.cfg.Delete("Bars")
	insertAt(c.cfg, "Bars", bars, at)
}

func (c *converter) bar(b *jsonx.Object) {
	if v, ok := b.Get("monitor"); ok {
		rename(b, "monitor", "screen")
		b.Set("screen", monitorScreen(v))
	}
	lowerFirst(b, "location")
	style := barStyle(b, true)
	for _, set := range barStyleKeys {
		for _, k := range set {
			b.Delete(k)
		}
	}
	for _, k := range []string{"overrideShadow", "shadow", "shadowColor", "shadowSize"} {
		b.Delete(k)
	}
	widgets, hasWidgets := take(b, "widgets")
	b.Set("style", style)
	if hasWidgets {
		b.Set("widgets", widgets)
	}
	// Each widget: an id unique in its bar, its popout grouped
	ids := newIDs()
	if w := obj(widgets); w != nil {
		for _, sec := range w.Keys() {
			for _, widget := range items(w, sec) {
				t, _ := widget.Value("type").(string)
				setID(widget, ids, lowerCamel(t))
				c.widget(t, widget)
			}
		}
	}
}

// widget: a bar widget's settings in their format-2 shape
func (c *converter) widget(t string, w *jsonx.Object) {
	p := obj(w.Value("properties"))
	if p == nil {
		return
	}
	if p.Has("showPopout") {
		popout := jsonx.NewObject()
		at := indexOf(p, "showPopout")
		if v, ok := take(p, "showPopout"); ok {
			popout.Set("enabled", v)
		}
		if v, ok := take(p, "popoutMenu"); ok {
			popout.Set("menu", v)
		}
		insertAt(p, "popout", popout, at)
	}
	switch t {
	case "Updates":
		rename(p, "intervalMinutes", "interval")
		scale(p, "interval", 60000)
	case "NextEvent":
		scale(p, "lookahead", 60000)
	}
}

func (c *converter) edgeMenus() {
	list := arr(c.cfg.Value("EdgeMenus"))
	menus := jsonx.NewObject()
	if list != nil {
		for _, v := range list.Items {
			if m := obj(v); m != nil {
				c.edgeMenu(m)
			}
		}
		menus.Set("items", list)
	}
	at := indexOf(c.cfg, "EdgeMenus")
	c.cfg.Delete("EdgeMenus")
	insertAt(c.cfg, "EdgeMenus", menus, at)
}

func (c *converter) edgeMenu(m *jsonx.Object) {
	if v, ok := m.Get("monitor"); ok {
		rename(m, "monitor", "screen")
		s := monitorScreen(v)
		if s.Value("mode") == "all" {
			s.Set("mode", "primary") // a menu is on one screen
		}
		m.Set("screen", s)
	}
	lowerFirst(m, "edge")
	layout := group(m, "layout", "fineGrid", "fine", "moduleScale", "moduleScale", "moduleBorders", "moduleBorders", "modules", "modules")
	if fine, ok := take(layout, "fine"); ok {
		insertAt(layout, "grid", jsonx.Obj("fine", fine), 0)
	}
	c.modules(obj(m.Value("layout")))
	group(m, "open", "openOnHover", "onHover", "openDelay", "delay")
	group(m, "trigger", "triggerSize", "size", "triggerLength", "length")
	group(m, "close", "closeOnLeave", "onLeave", "closeDelay", "delay", "closeOnOutsideClick", "onOutsideClick")
}

// modules gives a layout's modules their ids (unique in the layout).
func (c *converter) modules(layout *jsonx.Object) {
	if layout == nil {
		return
	}
	ids := newIDs()
	for _, m := range items(layout, "modules") {
		t, _ := m.Value("type").(string)
		setID(m, ids, lowerCamel(t))
		p := obj(m.Value("properties"))
		if p == nil {
			continue
		}
		switch t {
		case "Updates":
			rename(p, "intervalMinutes", "interval")
			scale(p, "interval", 60000)
		case "CommandOutput":
			scale(p, "interval", 1000)
		}
	}
}

// desktop: all / primary / monitors[] → items, each a layout with its
// screen (all monitors' and the primary monitor's always there, turned off
// when unused).
func (c *converter) desktop() {
	d := c.section("Desktop")
	if d == nil {
		return
	}
	list := jsonx.Arr()
	ids := newIDs()
	add := func(l *jsonx.Object, s *jsonx.Object, id string) {
		if l == nil {
			return
		}
		take(l, "monitor")
		item := jsonx.NewObject()
		item.Set("id", ids.claim(id))
		for _, k := range l.Keys() {
			item.Set(k, l.Value(k))
		}
		item.Set("screen", s)
		c.layoutGrid(item)
		c.modules(item)
		list.Append(item)
	}
	add(obj(d.Value("all")), screen("all"), "all")
	add(obj(d.Value("primary")), screen("primary"), "primary")
	for _, l := range items(d, "monitors") {
		name, _ := l.Value("monitor").(string)
		add(l, screen("named", name), slug(name, "monitor"))
	}
	c.cfg.Set("Desktop", jsonx.Obj("items", list))
}

// layoutGrid: columns, rows and fineGrid → grid
func (c *converter) layoutGrid(l *jsonx.Object) {
	g := jsonx.NewObject()
	at := -1
	for _, kv := range [][2]string{{"columns", "columns"}, {"rows", "rows"}, {"fineGrid", "fine"}} {
		if i := indexOf(l, kv[0]); i >= 0 && (at < 0 || i < at) {
			at = i
		}
	}
	for _, kv := range [][2]string{{"fineGrid", "fine"}, {"columns", "columns"}, {"rows", "rows"}} {
		if v, ok := take(l, kv[0]); ok {
			g.Set(kv[1], v)
		}
	}
	if g.Len() > 0 {
		insertAt(l, "grid", g, at)
	}
}

func (c *converter) screenLayouts() {
	for _, name := range []string{"Lockscreen", "Greeter"} {
		s := c.section(name)
		if s == nil {
			continue
		}
		l := obj(s.Value("layout"))
		if l == nil {
			continue
		}
		c.layoutGrid(l)
		group(l, "backdrop", "background", "source", "blurWallpaper", "blur", "backgroundColor", "color", "dim", "dim")
		group(l, "borders", "passwordBorder", "password", "greetingBorder", "greeting")
		c.modules(l)
	}
}

func (c *converter) compositor() {
	comp := c.section("Compositor")
	if comp == nil {
		comp = jsonx.NewObject()
		c.cfg.Set("Compositor", comp)
	}
	if h := c.section("Hyprland"); h != nil {
		managed := obj(h.Value("managed"))
		if managed != nil {
			for _, list := range []string{"curves", "customAnimations"} {
				ids := newIDs()
				for _, it := range items(managed, list) {
					base := "curve"
					if list == "customAnimations" {
						base = "animation"
						rename(it, "durationMs", "duration")
					}
					name, _ := it.Value("name").(string)
					if leaf, ok := it.Value("leaf").(string); ok && name == "" {
						name = leaf
					}
					setID(it, ids, slug(name, base))
				}
			}
			comp.Set("hyprland", managed)
		}
		c.cfg.Delete("Hyprland")
	}
	for _, kv := range [][2]string{{"Sway", "sway"}, {"Niri", "niri"}} {
		if s := c.section(kv[0]); s != nil {
			comp.Set(kv[1], s)
			c.cfg.Delete(kv[0])
		}
	}
}

func (c *converter) input() {
	i := c.section("Input")
	if i == nil {
		return
	}
	group(i, "keyboard", "keyboard", "enabled", "kbLayout", "layout", "kbVariant", "variant", "kbOptions", "options",
		"repeatRate", "repeatRate", "repeatDelay", "repeatDelay", "numlockByDefault", "numlock")
	group(i, "mouse", "mouse", "enabled", "accelProfile", "accel", "sensitivity", "sensitivity", "leftHanded", "leftHanded")
	group(i, "touchpad", "touchpad", "enabled", "naturalScroll", "naturalScroll", "tapToClick", "tapToClick",
		"disableWhileTyping", "disableWhileTyping", "scrollFactor", "scrollFactor")
	group(i, "cursor", "cursor", "enabled", "cursorTheme", "theme", "cursorSize", "size")
}

func (c *converter) windowLook() {
	w := c.section("WindowLook")
	if w == nil {
		return
	}
	group(w, "borders", "borders", "enabled", "activeColor", "activeColor", "inactiveColor", "inactiveColor")
	group(w, "shape", "shape", "enabled", "matchShell", "matchShell", "borderSize", "size", "rounding", "rounding")
	group(w, "gaps", "gaps", "enabled", "gapsIn", "inner", "gapsOut", "outer")
	group(w, "surfaceBlur", "surfaceBlur", "enabled", "surfaceBlurThroughWindows", "throughWindows",
		"surfaceBlurBackdrops", "backdrops", "surfaceBlurPauseFullscreen", "pauseFullscreen")
	group(w, "blur", "blur", "enabled", "windowBlur", "windowBlur", "blurSize", "size", "blurPasses", "passes",
		"blurXray", "xray", "blurIgnoreOpacity", "ignoreOpacity", "blurNewOptimizations", "newOptimizations",
		"blurNoise", "noise", "blurContrast", "contrast", "blurVibrancy", "vibrancy", "blurPopups", "popups", "blurSpecial", "special")
	group(w, "shadow", "shadow", "enabled", "shadowMatchShell", "matchShell", "shadowSize", "size", "shadowPower", "power",
		"shadowColor", "color", "shadowStrength", "strength")
	group(w, "dim", "dim", "enabled", "dimStrength", "strength")
	group(w, "opacity", "opacity", "enabled", "activeOpacity", "active", "inactiveOpacity", "inactive", "fullscreenOpacity", "fullscreen")
}

// overlayViews: views → items, each with an id; a Custom page's grid and
// modules are its layout
func (c *converter) overlayViews() {
	o := c.section("Overlay")
	if o == nil {
		return
	}
	rename(o, "views", "items")
	ids := newIDs()
	for _, v := range items(o, "items") {
		t, _ := v.Value("type").(string)
		base := lowerCamel(t)
		if t == "Custom" {
			name, _ := v.Value("name").(string)
			base = slug(name, "page")
			layout := jsonx.NewObject()
			at := indexOf(v, "fineGrid")
			if at < 0 {
				at = indexOf(v, "modules")
			}
			if fine, ok := take(v, "fineGrid"); ok {
				layout.Set("grid", jsonx.Obj("fine", fine))
			}
			if mods, ok := take(v, "modules"); ok {
				layout.Set("modules", mods)
			}
			insertAt(v, "layout", layout, at)
			c.modules(layout)
		}
		setID(v, ids, base)
	}
}

// ids gives the collections whose items had none theirs.
func (c *converter) ids() {
	list := func(section, key, base string, name func(*jsonx.Object) string) {
		s := c.section(section)
		if s == nil {
			return
		}
		// The ids items already have first, so a made one never takes
		// one a later item owns
		ids, kept := newIDs(), map[*jsonx.Object]bool{}
		for _, it := range items(s, key) {
			if id, _ := it.Value("id").(string); validID.MatchString(id) && !ids[id] {
				ids[id], kept[it] = true, true
			}
		}
		for _, it := range items(s, key) {
			if kept[it] {
				putID(it, it.Value("id").(string))
			} else {
				setID(it, ids, slug(name(it), base))
			}
		}
	}
	field := func(k string) func(*jsonx.Object) string {
		return func(o *jsonx.Object) string { s, _ := o.Value(k).(string); return s }
	}
	list("Idle", "items", "listener", field("onTimeout"))
	list("ClaudeUsage", "items", "account", field("label"))
	list("Monitors", "items", "profile", field("name"))
	list("Session", "env", "env", field("name"))
	list("Session", "autostart", "autostart", func(o *jsonx.Object) string {
		cmd, _ := o.Value("command").(string)
		if f := strings.Fields(cmd); len(f) > 0 {
			return f[0]
		}
		return ""
	})
	list("Keybinds", "binds", "bind", field("key"))
	list("Keybinds", "presets", "preset", field("name"))
	if kb := c.section("Keybinds"); kb != nil {
		for _, p := range items(kb, "presets") {
			ids := newIDs()
			for _, b := range items(p, "binds") {
				setID(b, ids, slug(field("key")(b), "bind"))
			}
		}
	}
	list("Chat", "providers", "provider", field("name"))
	list("Chat", "presets", "preset", field("name"))
	list("Workspaces", "strips", "strip", func(o *jsonx.Object) string {
		if s := obj(o.Value("screen")); s != nil {
			if names := arr(s.Value("names")); names != nil && names.Len() > 0 {
				n, _ := names.Items[0].(string)
				return n
			}
		}
		return ""
	})
}

// order puts the envelope first.
func (c *converter) order() {
	at := 0
	for _, k := range []string{"$schema", "format", "version"} {
		if v, ok := c.cfg.Get(k); ok {
			c.cfg.Delete(k)
			insertAt(c.cfg, k, v, at)
			at++
		}
	}
}

// --------------------------------------------------------------- ids

// idSet hands out ids unique within one list: base, base-2, base-3, …
type idSet map[string]bool

func newIDs() idSet { return idSet{} }

func (s idSet) claim(base string) string {
	id := base
	for n := 2; s[id]; n++ {
		id = base + "-" + strconv.Itoa(n)
	}
	s[id] = true
	return id
}

// setID gives o an id first in its keys: its own when it has a valid one
// not taken yet, else one made from base.
func setID(o *jsonx.Object, ids idSet, base string) {
	id, _ := o.Value("id").(string)
	if !validID.MatchString(id) || ids[id] {
		id = ids.claim(base)
	} else {
		ids[id] = true
	}
	putID(o, id)
}

// putID sets o's id first in its keys.
func putID(o *jsonx.Object, id string) {
	o.Delete("id")
	insertAt(o, "id", id, 0)
}

var (
	validID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
	nonSlug = regexp.MustCompile(`[^a-z0-9]+`)
)

// slug is a readable id from a name ("SUPER + space" → "super-space"),
// base when the name has nothing usable.
func slug(name, base string) string {
	s := strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(name), "-"), "-")
	if len(s) > 40 {
		s = strings.Trim(s[:40], "-")
	}
	if s == "" {
		return base
	}
	return s
}

// lowerCamel is a type's id base ("ClockCalendar" → "clockCalendar").
func lowerCamel(t string) string {
	if t == "" {
		return "item"
	}
	return strings.ToLower(t[:1]) + t[1:]
}
