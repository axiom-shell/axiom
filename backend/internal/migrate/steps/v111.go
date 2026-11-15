package steps

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v111 rewrites released custom widgets (CustomWidgets.items[], v1.2.1) to
// the shapes the editor rework reads. Per definition that is, in order:
//  1. bare-word bindings become `{path}` (typed text is literal now);
//  2. Button and Toggle `options.label` / `options.icon` move into `bind`;
//  3. bar and element command strings become `actions.items` entries that
//     `bar.run` and each element's `run` point at;
//  4. `states` and Text's `stateColor` become colour rules (`colorStates`);
//  5. a Button's `bind.enabled` becomes `enabledWhen` (one `{path}`) or goes.
//
// A definition whose `actions.items` is already an array is done and skipped
// whole; every definition changed gets that array (empty when no action was
// made), which keeps a second run from wrapping the moved labels again.
func v111(cfg *jsonx.Object) []string {
	section := object(cfg, "CustomWidgets")
	if section == nil {
		return nil
	}
	items, _ := section.Value("items").(*jsonx.Array)
	if items == nil {
		return nil
	}
	var changes []string
	for _, entry := range items.Items {
		def, _ := entry.(*jsonx.Object)
		if def == nil {
			continue
		}
		if parts := v111Definition(def); len(parts) > 0 {
			name, _ := def.Value("id").(string)
			if name == "" {
				name, _ = def.Value("name").(string)
			}
			changes = append(changes, fmt.Sprintf("CustomWidgets item %q: %s", name, strings.Join(parts, ", ")))
		}
	}
	return changes
}

// v111Trigger is one bar trigger, in the order its actions are made
type v111Trigger struct{ key, name string }

var v111BarTriggers = []v111Trigger{
	{"click", "Click"}, {"rightClick", "Right click"}, {"middleClick", "Middle click"},
	{"scrollUp", "Scroll up"}, {"scrollDown", "Scroll down"},
}

// v111ElementTriggers are the element triggers that ran a command on v1.2.1
var v111ElementTriggers = map[string][]string{
	"Button": {"click"}, "List": {"click"}, "Toggle": {"on", "off"}, "Bar": {"change"},
}

// v111DefaultStates is CustomWidgetData.defaultStates on v1.2.1 (Waybar's
// usual classes → theme colour names), in its order
var v111DefaultStates = [][2]string{
	{"ok", "success"}, {"good", "success"}, {"warning", "warning"}, {"warn", "warning"},
	{"critical", "error"}, {"error", "error"}, {"urgent", "error"}, {"info", "info"}, {"active", "accent"},
}

// v111TextColorRules are the rules for Color by state without user words:
// the built-in states, read from `{color}`
var v111TextColorRules = [][2]string{
	{"error", "error"}, {"warning", "warning"}, {"success", "success"}, {"info", "info"}, {"accent", "accent"},
}

// v111Graphics are the kinds whose own colour was the state colour
var v111Graphics = map[string]bool{
	"Icon": true, "List": true, "Status": true, "Ring": true, "Gauge": true,
	"Bar": true, "Segments": true, "Sparkline": true,
}

var (
	v111Number  = regexp.MustCompile(`^-?\d+(\.\d+)?$`)
	v111IDBad   = regexp.MustCompile(`[^A-Za-z0-9._-]`)
	v111IDStart = regexp.MustCompile(`^[A-Za-z0-9]`)
)

func v111Definition(def *jsonx.Object) []string {
	actions, _ := def.Value("actions").(*jsonx.Object)
	if def.Has("actions") && actions == nil {
		return nil
	}
	if actions != nil {
		if _, done := actions.Value("items").(*jsonx.Array); done {
			return nil
		}
	}
	var elements []*jsonx.Object
	if module := object(def, "module"); module != nil {
		if list, _ := module.Value("elements").(*jsonx.Array); list != nil {
			for _, e := range list.Items {
				if el, _ := e.(*jsonx.Object); el != nil {
					elements = append(elements, el)
				}
			}
		}
	}
	var bar *jsonx.Object
	if v, ok := def.Get("bar"); ok {
		bar, _ = v.(*jsonx.Object)
	} else {
		bar = jsonx.NewObject()
	}

	var parts []string
	add := func(part string) { parts = append(parts, part) }
	if v111Bindings(elements) {
		add("bindings became {key}")
	}
	if v111Labels(elements) {
		add("labels moved into fields")
	}
	enabled, dropped := v111Enabled(elements)
	if enabled {
		add("enabled became a condition")
	}
	for _, id := range dropped {
		add(fmt.Sprintf("%s enabled: not a value, dropped", id))
	}
	made := jsonx.Arr()
	if v111Commands(def, actions, bar, elements, made) {
		add("commands became actions")
	}
	if v111States(def, bar, elements) {
		add("state colours became rules")
	}
	if len(parts) == 0 {
		return nil
	}
	if bar != nil && !def.Has("bar") && bar.Len() > 0 {
		def.Set("bar", bar)
	}
	if actions == nil {
		actions = jsonx.NewObject()
		def.Set("actions", actions)
	}
	actions.Set("items", made)
	return parts
}

// v111Bindings wraps each bare-word binding as `{word}`
func v111Bindings(elements []*jsonx.Object) bool {
	changed := false
	for _, el := range elements {
		bind, _ := el.Value("bind").(*jsonx.Object)
		if bind == nil {
			continue
		}
		for _, key := range bind.Keys() {
			v, _ := bind.Value(key).(string)
			if v == "" || v111Number.MatchString(strings.TrimSpace(v)) || strings.ContainsAny(v, "{}:") {
				continue
			}
			bind.Set(key, "{"+v+"}")
			changed = true
		}
	}
	return changed
}

// v111Labels moves Button label and icon and Toggle label out of options
// into bind, as typed; a bound slot wins and the option is just dropped
func v111Labels(elements []*jsonx.Object) bool {
	changed := false
	for _, el := range elements {
		var keys []string
		switch el.Value("type") {
		case "Button":
			keys = []string{"label", "icon"}
		case "Toggle":
			keys = []string{"label"}
		default:
			continue
		}
		opts, _ := el.Value("options").(*jsonx.Object)
		if opts == nil {
			continue
		}
		for _, key := range keys {
			v, ok := opts.Get(key)
			if !ok {
				continue
			}
			opts.Delete(key)
			changed = true
			text, _ := v.(string)
			if text == "" {
				continue
			}
			bind, _ := el.Value("bind").(*jsonx.Object)
			if bind == nil {
				if el.Has("bind") {
					continue
				}
				bind = jsonx.NewObject()
				el.Set("bind", bind)
			}
			if cur, _ := bind.Value(key).(string); cur != "" {
				continue
			}
			bind.Set(key, text)
		}
	}
	return changed
}

var v111OnePath = regexp.MustCompile(`^\{([^{}]+)\}$`)

// v111Enabled turns a Button's `bind.enabled` that is exactly one `{path}`
// into `enabledWhen: {test: on, key: path}`; any other non-empty text is
// dropped (its element id is returned); the binding is deleted either way
func v111Enabled(elements []*jsonx.Object) (bool, []string) {
	changed := false
	var dropped []string
	for _, el := range elements {
		if el.Value("type") != "Button" {
			continue
		}
		bind, _ := el.Value("bind").(*jsonx.Object)
		if bind == nil || !bind.Has("enabled") {
			continue
		}
		text, _ := bind.Value("enabled").(string)
		bind.Delete("enabled")
		if strings.TrimSpace(text) == "" {
			changed = true
			continue
		}
		if m := v111OnePath.FindStringSubmatch(strings.TrimSpace(text)); m != nil {
			el.Set("enabledWhen", jsonx.Obj("test", "on", "key", strings.TrimSpace(m[1])))
			changed = true
			continue
		}
		id, _ := el.Value("id").(string)
		dropped = append(dropped, id)
	}
	return changed, dropped
}

func v111Action(id, name, command string) *jsonx.Object {
	return jsonx.Obj("id", id, "name", name, "kind", "command", "command", command, "wait", false)
}

func v111ActionID(name string, taken map[string]bool) string {
	id := v111IDBad.ReplaceAllString(strings.ReplaceAll(name, " ", "-"), "-")
	if !v111IDStart.MatchString(id) {
		id = "action-" + id
	}
	return freeID(id, taken)
}

// v111Commands turns the definition's bar commands and its elements'
// commands into actions (appended to made) and their run references, and
// removes the old command keys
func v111Commands(def, actions, bar *jsonx.Object, elements []*jsonx.Object, made *jsonx.Array) bool {
	changed := false
	taken := map[string]bool{}
	byCommand := map[string]string{}
	// ensure makes (or reuses) the action running command
	ensure := func(name, command string, fixedID string) string {
		if id, ok := byCommand[command]; ok {
			return id
		}
		var id string
		if fixedID != "" {
			id = freeID(fixedID, taken)
		} else {
			id = v111ActionID(name, taken)
		}
		made.Append(v111Action(id, name, command))
		byCommand[command] = id
		return id
	}
	setRun := func(host *jsonx.Object, trigger, id string) {
		if host == nil {
			return
		}
		run, _ := host.Value("run").(*jsonx.Object)
		if run == nil {
			if host.Has("run") {
				return
			}
			run = jsonx.NewObject()
			host.Set("run", run)
		}
		run.Set(trigger, id)
	}
	command := func(o *jsonx.Object, key string) string {
		s, _ := o.Value(key).(string)
		if strings.TrimSpace(s) == "" {
			return ""
		}
		return s
	}

	barClick := ""
	if actions != nil {
		for _, t := range v111BarTriggers {
			if actions.Has(t.key) {
				changed = true
			}
			cmd := command(actions, t.key)
			if cmd == "" {
				continue
			}
			id := ensure(t.name, cmd, t.key)
			setRun(bar, t.key, id)
			if t.key == "click" {
				barClick = id
			}
		}
		for _, t := range v111BarTriggers {
			actions.Delete(t.key)
		}
	}

	for _, el := range elements {
		typ, _ := el.Value("type").(string)
		elID, _ := el.Value("id").(string)
		if el.Has("actions") {
			changed = true
		}
		own, _ := el.Value("actions").(*jsonx.Object)
		el.Delete("actions")
		ownCommand := ""
		for _, trigger := range v111ElementTriggers[typ] {
			if own == nil {
				break
			}
			cmd := command(own, trigger)
			if cmd == "" {
				continue
			}
			base := elID
			if base == "" {
				base = trigger
			}
			name := base
			if trigger == "on" || trigger == "off" {
				name = base + " " + trigger
			}
			id := ensure(name, cmd, "")
			setRun(el, trigger, id)
			if trigger == "click" || trigger == "change" {
				ownCommand = cmd
			}
		}
		if typ == "Button" && ownCommand == "" && barClick != "" {
			setRun(el, "click", barClick)
		}
		if !strings.Contains(ownCommand, "{value}") {
			continue
		}
		switch typ {
		case "Button":
			bind, _ := el.Value("bind").(*jsonx.Object)
			if bind == nil {
				continue
			}
			label, _ := bind.Value("label").(string)
			if cur, _ := bind.Value("value").(string); cur == "" && label != "" {
				bind.Set("value", label)
			}
		case "List":
			opts, _ := el.Value("options").(*jsonx.Object)
			if opts == nil {
				if el.Has("options") {
					continue
				}
				opts = jsonx.NewObject()
				el.Set("options", opts)
			}
			if !opts.Has("row") {
				opts.Set("row", jsonx.Obj("id", "{text}"))
			}
		}
	}
	return changed || made.Len() > 0
}

func v111Rules(words [][2]string) *jsonx.Array {
	rules := jsonx.Arr()
	for _, w := range words {
		if rules.Len() == 16 {
			break
		}
		rules.Append(jsonx.Obj("test", "is", "value", w[0], "color", w[1]))
	}
	return rules
}

func v111ColorStates(key string, words [][2]string) *jsonx.Object {
	return jsonx.Obj("enabled", true, "key", key, "rules", v111Rules(words))
}

// v111States turns the definition's `states` map and Text's stateColor
// switch into colour rules
func v111States(def, bar *jsonx.Object, elements []*jsonx.Object) bool {
	changed := def.Has("states")
	var user [][2]string
	userWord := map[string]bool{}
	if states, _ := def.Value("states").(*jsonx.Object); states != nil {
		for _, key := range states.Keys() {
			if color, _ := states.Value(key).(string); color != "" {
				user = append(user, [2]string{key, color})
				userWord[key] = true
			}
		}
	}
	def.Delete("states")

	for _, el := range elements {
		typ, _ := el.Value("type").(string)
		opts, _ := el.Value("options").(*jsonx.Object)
		if opts == nil {
			if el.Has("options") || !v111Graphics[typ] || len(user) == 0 {
				continue
			}
			opts = jsonx.NewObject()
			el.Set("options", opts)
		}
		switch {
		case typ == "Text" || typ == "TextBlock":
			on := opts.Value("stateColor") == true
			if opts.Delete("stateColor") {
				changed = true
			}
			if !on {
				continue
			}
			if len(user) > 0 {
				words := append([][2]string{}, user...)
				for _, d := range v111DefaultStates {
					if !userWord[d[0]] {
						words = append(words, d)
					}
				}
				opts.Set("colorStates", v111ColorStates("state", words))
			} else {
				opts.Set("colorStates", v111ColorStates("color", v111TextColorRules))
			}
		case v111Graphics[typ] && len(user) > 0:
			if c, ok := opts.Get("color"); ok && c != "" {
				continue
			}
			opts.Set("colorStates", v111ColorStates("state", user))
			changed = true
		}
	}
	if len(user) > 0 && bar != nil {
		bar.Set("colorStates", v111ColorStates("state", user))
		changed = true
	}
	return changed
}
