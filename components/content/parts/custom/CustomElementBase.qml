pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.apps

// What every custom widget element is given (CustomElement loads one by its
// kind): its config, the widget's resolved fields and history, and helpers
// reading its bindings and options. Bindings: a field name, a path in the
// sample or a format (CustomWidgetData.elementValue); an empty one falls
// back to the widget's own field.
Item {
  id: root

  // { id, type, place, bind, options, actions } (a CustomElement)
  property var element: ({})
  // CustomWidgetsManager.fields[id] (CustomWidgetData.resolve), or {}
  property var fields: ({})
  // CustomWidgetsManager.history[id]
  property var history: ({})
  property string widgetId: ""
  // Off on the lock screen and in previews that mustn't run anything
  property bool actionsEnabled: true
  // The definition's icon, for an element with none
  property string fallbackIcon: "widgets"

  readonly property var bind: element?.bind ?? ({})
  readonly property var options: element?.options ?? ({})
  readonly property var actions: element?.actions ?? ({})

  // An option, or `fallback` when unset or empty
  function opt(key, fallback) {
    const v = root.options[key];
    return v === undefined || v === null || v === "" ? fallback : v;
  }

  // A slot's value: its binding, else the widget's `field`
  function value(slot, field) {
    const b = root.bind[slot];
    return b ? CustomWidgetData.elementValue(root.fields, b) : field ? root.fields?.[field] : undefined;
  }

  // A slot as text ("" for nothing)
  function text(slot, field) {
    const v = root.value(slot, field);
    return v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
  }

  // The value, min and max slots as numbers (each bound, else the
  // output's own: CustomWidgetData.elementRange)
  readonly property var range: CustomWidgetData.elementRange(root.fields, root.bind)

  // 0-1 of the value between min and max; -1 without a value
  function ratio() {
    return CustomWidgetData.elementRatio(root.fields, root.bind);
  }

  // The `color` option: "" (the default), "state" (the widget's state
  // colour, else the default), or a theme name or colour
  function colorOf(key, fallback) {
    const name = root.opt(key, "");
    if (name === "state")
      return root.fields?.color ? Theme.resolveColor(root.fields.color) : fallback;
    return name ? Theme.resolveColor(name) : fallback;
  }

  // Run one of the element's actions with `value` filled in
  function act(action, value) {
    if (root.actionsEnabled)
      CustomWidgetsManager.runCommand(root.widgetId, root.actions[action] ?? "", value);
  }
}
