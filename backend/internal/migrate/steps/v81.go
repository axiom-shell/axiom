package steps

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v81: the CommandOutput module folds into custom widgets (Phase 10 of the
// cleanup roadmap): each one, wherever a module grid holds it (pages, edge
// menus, the desktop, the lock screen), becomes a CustomWidgets definition
// running its command every interval as plain text, drawn by a Text block
// filling the module (monospace when it was), its click command the
// widget's click action (its text escaped, so it shows as typed, never as
// markup); the module is a CustomWidget showing it.
func v81(cfg *jsonx.Object) []string {
	var modules []*jsonx.Object
	collectModules(cfg, &modules)
	if len(modules) == 0 {
		return nil
	}
	items, taken := sectionItems(cfg, "CustomWidgets")
	if items == nil {
		return nil
	}
	for _, m := range modules {
		props, _ := m.Value("properties").(*jsonx.Object)
		if props == nil {
			props = jsonx.NewObject()
		}
		id := freeID("command", taken)
		items.Append(commandOutputWidget(id, props, m.Value("place")))
		m.Set("type", "CustomWidget")
		m.Set("properties", jsonx.Obj("definition", id))
	}
	return []string{fmt.Sprintf("%d CommandOutput module(s) became custom widgets (CustomWidgets.items), each still running its command", len(modules))}
}

// collectModules finds every module grid's CommandOutput modules: objects
// of that type in a "modules" array, anywhere in the config.
func collectModules(v any, out *[]*jsonx.Object) {
	switch t := v.(type) {
	case *jsonx.Object:
		for _, key := range t.Keys() {
			child := t.Value(key)
			if list, _ := child.(*jsonx.Array); list != nil && key == "modules" {
				for _, item := range list.Items {
					if m, _ := item.(*jsonx.Object); m != nil && m.Value("type") == "CommandOutput" {
						*out = append(*out, m)
					}
				}
			}
			collectModules(child, out)
		}
	case *jsonx.Array:
		for _, item := range t.Items {
			collectModules(item, out)
		}
	}
}

// sectionItems is the items list of cfg's section `name` (both made when
// missing) and the ids it holds; nil when either is of another shape.
func sectionItems(cfg *jsonx.Object, name string) (*jsonx.Array, map[string]bool) {
	section, _ := cfg.Value(name).(*jsonx.Object)
	if section == nil {
		if cfg.Has(name) {
			return nil, nil
		}
		section = jsonx.NewObject()
		cfg.Set(name, section)
	}
	items, _ := section.Value("items").(*jsonx.Array)
	if items == nil {
		if section.Has("items") {
			return nil, nil
		}
		items = jsonx.Arr()
		section.Set("items", items)
	}
	taken := map[string]bool{}
	for _, item := range items.Items {
		if o, _ := item.(*jsonx.Object); o != nil {
			if id, _ := o.Value("id").(string); id != "" {
				taken[id] = true
			}
		}
	}
	return items, taken
}

// freeID is base, else base-2, base-3 … not in taken (and takes it)
func freeID(base string, taken map[string]bool) string {
	id := base
	for n := 2; taken[id]; n++ {
		id = base + "-" + strconv.Itoa(n)
	}
	taken[id] = true
	return id
}

// commandOutputWidget is the definition a CommandOutput module's
// properties become, sized as its place was (in grid units, at most 8)
func commandOutputWidget(id string, props *jsonx.Object, place any) *jsonx.Object {
	str := func(key, fallback string) string {
		if s, ok := props.Value(key).(string); ok && s != "" {
			return s
		}
		return fallback
	}
	command := strings.TrimSpace(str("command", "uptime -p"))
	name := str("title", "")
	if name == "" {
		name = command
		if len(name) > 40 {
			name = name[:40]
		}
	}
	interval := 10000.0
	if v, ok := props.Value("interval").(float64); ok {
		interval = max(v, 1000)
	}
	w, h := 4.0, 2.0
	if p, _ := place.(*jsonx.Object); p != nil {
		if v, ok := p.Value("w").(float64); ok {
			w = min(max(v, 1), 8)
		}
		if v, ok := p.Value("h").(float64); ok {
			h = min(max(v, 1), 8)
		}
	}
	monospace := props.Value("monospace") == true
	return jsonx.Obj(
		"id", id,
		"name", name,
		"icon", str("icon", "terminal"),
		"command", command,
		"mode", "poll",
		"interval", interval,
		"output", "text",
		// Output shows as typed, as CommandOutput did: a "<" is no markup
		"escape", true,
		"hideEmpty", false,
		"actions", jsonx.Obj("click", str("clickCommand", "")),
		"module", jsonx.Obj(
			"size", jsonx.Arr(w, h),
			"elements", jsonx.Arr(jsonx.Obj(
				"id", "output",
				"type", "TextBlock",
				"place", jsonx.Obj("x", 0.0, "y", 0.0, "w", w*4, "h", h*4),
				"bind", jsonx.Obj("text", "text"),
				"options", jsonx.Obj("monospace", monospace),
			)),
		),
	)
}
