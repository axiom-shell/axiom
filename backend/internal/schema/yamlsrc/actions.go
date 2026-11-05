package yamlsrc

import (
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// fillAxiomActions fills every `action` marked `x-axiomActions: {except:
// [...]}` from the bind actions table (actions.JSON): its enum is the
// table's ipcActions less those named, then exec, labelled as the Keybind
// definition labels them; a sibling `argument` shows for the actions whose
// IPC call takes {0} (and exec), a sibling `call` for those with calls.
// The mark goes.
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
	var list *jsonx.Array
	if spec != nil && spec.Len() == 1 {
		list, _ = spec.Value("except").(*jsonx.Array)
	}
	except := map[string]bool{}
	if list == nil {
		fail("is {except: [<ipcActions left out>]}")
		return
	}
	for _, v := range list.Items {
		name, _ := v.(string)
		if !ipc.Has(name) {
			fail("except names " + jsonx.ToString(v) + ", which isn't one of the table's ipcActions")
		}
		except[name] = true
	}
	enum, names, argument, call := jsonx.Arr(), jsonx.NewObject(), jsonx.Arr(), jsonx.Arr()
	for _, name := range append(ipc.Keys(), "exec") {
		if except[name] {
			continue
		}
		label, ok := labels.Value(name).(string)
		if !ok {
			fail("the Keybind definition has no label for " + name)
		}
		enum.Append(name)
		names.Set(name, label)
		if row, ok := ipc.Value(name).(*jsonx.Array); name == "exec" || ok && strings.Contains(jsonx.ToString(row.Items[0]), "{0}") {
			argument.Append(name)
		}
		if calls.Has(name) {
			call.Append(name)
		}
	}
	action.Set("enum", enum)
	action.Set("x-enumLabels", names)
	for key, shown := range map[string]*jsonx.Array{"argument": argument, "call": call} {
		if field, ok := props.Value(key).(*jsonx.Object); ok {
			field.Set("x-showIf", jsonx.Obj("action", shown))
		}
	}
}
