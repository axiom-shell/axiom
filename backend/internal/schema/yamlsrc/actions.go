package yamlsrc

import (
	"slices"
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
//   - compositor: [...] named compositorActions to add (only those named: the
//     rest stay keybind-only), gated by the table's `needs` (x-enumShowIf)
//
// Its enum is the table's ipcActions less those left out, then the compositor ones, then exec (but
// with noArgument), then the extras; labelled as the Keybind definition
// labels them, with the table's icons (x-enumIcons) and sections
// (x-enumGroups), an extra's from the field's own. On an `action` property, a sibling `argument` shows for the
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
var actionsMarkKeys = map[string]bool{"except": true, "noArgument": true, "extra": true, "compositor": true}

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
	tableIcons, _ := tables.Value("icons").(*jsonx.Object)
	if ipc == nil || calls == nil || tableIcons == nil || labels == nil {
		fail("needs the table's ipcActions, calls and icons and the Keybind definition's action labels")
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
	compositorRows, _ := tables.Value("compositorActions").(*jsonx.Object)
	argumentKinds, _ := tables.Value("argumentKinds").(*jsonx.Object)
	needs, _ := tables.Value("needs").(*jsonx.Object)
	var compositor []string
	for _, name := range list("compositor") {
		if compositorRows == nil || !compositorRows.Has(name) {
			fail("compositor names " + name + ", which isn't one of the table's compositorActions")
			continue
		}
		compositor = append(compositor, name)
	}
	ownLabels, _ := action.Value("x-enumLabels").(*jsonx.Object)
	ownIcons, _ := action.Value("x-enumIcons").(*jsonx.Object)
	ownGroups, _ := action.Value("x-enumGroups").(*jsonx.Object)
	enum, names, argument, call := jsonx.Arr(), jsonx.NewObject(), jsonx.Arr(), jsonx.Arr()
	icons, groups := jsonx.NewObject(), jsonx.NewObject()
	// An extra's icon and group, from the field's own (each optional)
	own := func(name string) {
		if ownIcons != nil {
			if icon, ok := ownIcons.Value(name).(string); ok {
				icons.Set(name, icon)
			}
		}
		if ownGroups != nil {
			if group, ok := ownGroups.Value(name).(string); ok {
				groups.Set(name, group)
			}
		}
	}
	enumShowIf := jsonx.NewObject()
	if own, ok := action.Value("x-enumShowIf").(*jsonx.Object); ok {
		enumShowIf = own
	}
	order := append(append(ipc.Keys(), compositor...), "exec")
	for _, name := range order {
		isCompositor := slices.Contains(compositor, name)
		if except[name] || noArgument && !isCompositor && takesArgument(name) {
			continue
		}
		label, ok := labels.Value(name).(string)
		if !ok {
			fail("the Keybind definition has no label for " + name)
		}
		enum.Append(name)
		names.Set(name, label)
		if row, ok := ipc.Value(name).(*jsonx.Array); ok && len(row.Items) > 2 {
			groups.Set(name, jsonx.ToString(row.Items[2]))
		}
		if isCompositor {
			// Only where the compositor can do it (the table's `needs`)
			if row, ok := compositorRows.Value(name).(*jsonx.Array); ok && len(row.Items) > 1 {
				groups.Set(name, jsonx.ToString(row.Items[1]))
			}
			var conds []any
			if caps, ok := needs.Value(name).(*jsonx.Array); ok {
				for _, c := range caps.Items {
					conds = append(conds, jsonx.Obj("/$supports."+jsonx.ToString(c), true))
				}
			}
			switch len(conds) {
			case 0:
			case 1:
				enumShowIf.Set(name, conds[0])
			default:
				enumShowIf.Set(name, jsonx.Obj("anyOf", jsonx.Arr(conds...)))
			}
		}
		if icon, ok := tableIcons.Value(name).(string); ok {
			icons.Set(name, icon)
		} else {
			own(name)
		}
		if isCompositor && argumentKinds != nil && argumentKinds.Has(name) || !isCompositor && takesArgument(name) {
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
		own(name)
	}
	if enumShowIf.Len() > 0 {
		action.Set("x-enumShowIf", enumShowIf)
	}
	action.Set("enum", enum)
	action.Set("x-enumLabels", names)
	action.Set("x-enumIcons", icons)
	action.Set("x-enumGroups", groups)
	if props == nil {
		return
	}
	for key, shown := range map[string]*jsonx.Array{"argument": argument, "call": call} {
		if field, ok := props.Value(key).(*jsonx.Object); ok {
			field.Set("x-showIf", jsonx.Obj("action", shown))
		}
	}
}
