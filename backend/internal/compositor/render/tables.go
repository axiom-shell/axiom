package render

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Tables are the data the JS helpers read from LayerStack and
// PolkitAgents (plain JSON in those files, parsed from them, as
// scripts/gen_docs.py reads LayerStack.layers, never copied by hand), and
// the bind actions (actions.JSON).
type Tables struct {
	// LayerStack's layers ({ namespace, order, bar, noAnim, why }), and what
	// blurs behind axiom's surfaces, by namespace
	Layers                                       []*jsonx.Object
	BarLayers                                    []string
	BlurSurfaces, BlurBackdrops, BlurOverOverlay []string
	BlurChrome, BlurBacked                       []string

	// The bind actions' tables (actions.JSON)
	IPCActions, CompositorActions, Calls, Needs, ActionFlags, SwitcherSteps, ArgumentKinds *jsonx.Object
	FlagNames                                                                              []string

	// PolkitAgents\' agents ({ process, unit })
	PolkitAgents []*jsonx.Object
}

// The files Tables come from, by their repo paths
const (
	LayerStackFile   = "components/methods/LayerStack.qml"
	PolkitAgentsFile = "components/methods/PolkitAgents.qml"
)

// ParseTables reads the tables from their files' text (read: a repo path's
// text).
func ParseTables(read func(path string) (string, error)) (*Tables, error) {
	layerStack, err := read(LayerStackFile)
	if err != nil {
		return nil, err
	}
	bindActions, err := actions.Tables()
	if err != nil {
		return nil, err
	}
	polkit, err := read(PolkitAgentsFile)
	if err != nil {
		return nil, err
	}
	t := &Tables{}
	agents, err := qmlValue(polkit, "agents")
	if err != nil {
		return nil, err
	}
	for _, v := range items(agents) {
		if a, ok := v.(*jsonx.Object); ok {
			t.PolkitAgents = append(t.PolkitAgents, a)
		}
	}
	layers, err := qmlValue(layerStack, "layers")
	if err != nil {
		return nil, err
	}
	for _, v := range items(layers) {
		l, ok := v.(*jsonx.Object)
		if !ok {
			return nil, fmt.Errorf("%s: a layer isn't an object", LayerStackFile)
		}
		t.Layers = append(t.Layers, l)
		if isTrue(l.Value("bar")) {
			t.BarLayers = append(t.BarLayers, str(l.Value("namespace")))
		}
	}
	lists := []struct {
		name string
		to   *[]string
	}{
		{"blurSurfaces", &t.BlurSurfaces}, {"blurBackdrops", &t.BlurBackdrops}, {"blurOverOverlay", &t.BlurOverOverlay},
		{"blurChrome", &t.BlurChrome}, {"blurBacked", &t.BlurBacked},
	}
	for _, l := range lists {
		v, err := qmlValue(layerStack, l.name)
		if err != nil {
			return nil, err
		}
		*l.to = stringList(v)
		// `root.barLayers.concat([…])`: the bars' first
		if strings.HasPrefix(qmlExpression(layerStack, l.name), "root.barLayers.concat(") {
			*l.to = append(append([]string(nil), t.BarLayers...), *l.to...)
		}
	}
	objects := []struct {
		name string
		to   **jsonx.Object
	}{
		{"ipcActions", &t.IPCActions}, {"compositorActions", &t.CompositorActions}, {"calls", &t.Calls}, {"needs", &t.Needs},
		{"actionFlags", &t.ActionFlags}, {"switcherSteps", &t.SwitcherSteps}, {"argumentKinds", &t.ArgumentKinds},
	}
	for _, o := range objects {
		obj, ok := bindActions.Value(o.name).(*jsonx.Object)
		if !ok {
			return nil, fmt.Errorf("the bind actions: %s isn't an object", o.name)
		}
		*o.to = obj
	}
	t.FlagNames = stringList(bindActions.Value("flagNames"))
	return t, nil
}

// qmlExpression is what follows `property var <name>:` in a QML file
func qmlExpression(text, name string) string {
	marker := "property var " + name + ":"
	i := strings.Index(text, marker)
	if i < 0 {
		return ""
	}
	return strings.TrimLeft(text[i+len(marker):], " \t")
}

// qmlValue is the JSON literal of `property var <name>`: an array, an
// object in parentheses (`({…})`), or the array a `….concat([…])` adds
func qmlValue(text, name string) (any, error) {
	expr := qmlExpression(text, name)
	if expr == "" {
		return nil, fmt.Errorf("no property %s", name)
	}
	start := strings.IndexAny(expr, "[{")
	if start < 0 {
		return nil, fmt.Errorf("property %s holds no literal", name)
	}
	end := matching(expr, start)
	if end < 0 {
		return nil, fmt.Errorf("property %s's literal isn't closed", name)
	}
	v, err := jsonx.Unmarshal([]byte(stripComments(expr[start : end+1])))
	if err != nil {
		return nil, fmt.Errorf("property %s: %w", name, err)
	}
	return v, nil
}

// matching is the index of the bracket closing the one at start, outside
// strings, or -1
func matching(text string, start int) int {
	depth := 0
	var quote byte
	for i := start; i < len(text); i++ {
		c := text[i]
		switch {
		case quote != 0:
			if c == '\\' {
				i++
			} else if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '[' || c == '{':
			depth++
		case c == ']' || c == '}':
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

// stripComments takes // comments out of a literal, outside strings
func stripComments(text string) string {
	var b strings.Builder
	var quote byte
	for i := 0; i < len(text); i++ {
		c := text[i]
		switch {
		case quote != 0:
			b.WriteByte(c)
			if c == '\\' && i+1 < len(text) {
				i++
				b.WriteByte(text[i])
			} else if c == quote {
				quote = 0
			}
		case c == '"':
			quote = c
			b.WriteByte(c)
		case c == '/' && i+1 < len(text) && text[i+1] == '/':
			for i < len(text) && text[i] != '\n' {
				i++
			}
			b.WriteByte('\n')
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}
