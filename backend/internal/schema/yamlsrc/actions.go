package yamlsrc

import (
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// fillAxiomActions fills every string enum marked `x-axiomActions` from
// the bind actions table (actions.JSON). The mark is an object of
//   - except: [...] the ipcActions left out
//   - noArgument: true for only the actions that take no argument (no {0}
//     in their IPC call), and no exec
//   - extra: [...] values of the field's own, after the table's, labelled
//     by its own x-enumLabels
//
// Its enum is the table's ipcActions less those left out, then exec (but
// with noArgument), then the extras; labelled as the Keybind definition
// labels them. On an `action` property, a sibling `argument` shows for the
// actions whose IPC call takes {0} (and exec), a sibling `call` for those
// with calls. The mark goes.
func (a *assembler) fillAxiomActions(root *jsonx.Object) {
	var labels *jsonx.Object
	if defs, ok := root.Value("definitions").(*jsonx.Object); ok {
		if action := pointer(defs, "/Keybind/properties/action"); action != nil {
			labels, _ = action.Value("x-enumLabels").(*jsonx.Object)
		}
	}
	var walk func(v any, where string)
	walk = func(v any, where string) {
		switch t := v.(type) {
		case *jsonx.Object:
			if props, ok := t.Value("properties").(*jsonx.Object); ok {
				if action, ok := props.Value("action").(*jsonx.Object); ok && action.Has("x-axiomActions") {
					a.fillActions(props, action, labels, where)
				}
			}
			if t.Has("x-axiomActions") {
				a.fillActions(nil, t, labels, where)
			}
			for _, k := range t.Keys() {
				walk(t.Value(k), where+"/"+k)
			}
		case *jsonx.Array:
			for _, x := range t.Items {
				walk(x, where)
			}
		}
	}
	walk(root, "")
}

// The keys an x-axiomActions mark may have
var actionsMarkKeys = map[string]bool{"except": true, "noArgument": true, "extra": true}

func (a *assembler) fillActions(props, action, labels *jsonx.Object, where string) {
	fail := func(msg string) { a.errs = append(a.errs, &Error{File: where, Msg: "x-axiomActions: " + msg}) }
	spec, _ := action.Value("x-axiomActions").(*jsonx.Object)
	action.Delete("x-axiomActions")
	tables, err := actions.Tables()
	if err != nil {
		fail(err.Error())
		return
	}
	ipc, _ := tables.Value("ipcActions").(*jsonx.Object)
	calls, _ := tables.Value("calls").(*jsonx.Object)
	if ipc == nil || calls == nil || labels == nil {
		fail("needs the table's ipcActions and calls and the Keybind definition's action labels")
		return
	}
	if spec == nil {
		fail("is {except: [...], noArgument: true, extra: [...]}, each optional")
		return
	}
	for _, k := range spec.Keys() {
		if !actionsMarkKeys[k] {
			fail("has an unknown key " + k)
		}
	}
	list := func(key string) []string {
		var names []string
		if !spec.Has(key) {
			return nil
		}
		arr, ok := spec.Value(key).(*jsonx.Array)
		if !ok {
			fail(key + " isn't a list")
			return nil
		}
		for _, v := range arr.Items {
			name, _ := v.(string)
			names = append(names, name)
		}
		return names
	}
	except := map[string]bool{}
	for _, name := range list("except") {
		if !ipc.Has(name) {
			fail("except names " + name + ", which isn't one of the table's ipcActions")
		}
		except[name] = true
	}
	noArgument := false
	if spec.Has("noArgument") {
		noArgument, _ = spec.Value("noArgument").(bool)
	}
	takesArgument := func(name string) bool {
		row, ok := ipc.Value(name).(*jsonx.Array)
		return name == "exec" || ok && strings.Contains(jsonx.ToString(row.Items[0]), "{0}")
	}
	ownLabels, _ := action.Value("x-enumLabels").(*jsonx.Object)
	enum, names, argument, call := jsonx.Arr(), jsonx.NewObject(), jsonx.Arr(), jsonx.Arr()
	for _, name := range append(ipc.Keys(), "exec") {
		if except[name] || noArgument && takesArgument(name) {
			continue
		}
		label, ok := labels.Value(name).(string)
		if !ok {
			fail("the Keybind definition has no label for " + name)
		}
		enum.Append(name)
		names.Set(name, label)
		if takesArgument(name) {
			argument.Append(name)
		}
		if calls.Has(name) {
			call.Append(name)
		}
	}
	for _, name := range list("extra") {
		if names.Has(name) {
			fail("extra names " + name + ", which the table already gives")
			continue
		}
		label, ok := ownLabels.Value(name).(string)
		if ownLabels == nil || !ok {
			fail("the extra " + name + " has no label in the field's own x-enumLabels")
		}
		enum.Append(name)
		names.Set(name, label)
	}
	action.Set("enum", enum)
	action.Set("x-enumLabels", names)
	if props == nil {
		return
	}
	for key, shown := range map[string]*jsonx.Array{"argument": argument, "call": call} {
		if field, ok := props.Value(key).(*jsonx.Object); ok {
			field.Set("x-showIf", jsonx.Obj("action", shown))
		}
	}
}
