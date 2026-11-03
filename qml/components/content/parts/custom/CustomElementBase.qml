pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.apps

// What every custom widget element is given (CustomElement loads one by its
// kind, elements/<Type>/Custom<Type>.qml): its config, the widget's resolved
// fields and history, and helpers reading its bindings. Bindings: a field
// name, a path in the sample or a format (CustomWidgetData.elementValue);
// an empty one falls back to the widget's own field. Its options are its
// kind's schema (elements/<Type>/schema.yaml), every default filled.
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
  // Drawn down its box rather than across (a Bar, Segments, Separator)
  readonly property bool vertical: root.height > root.width

  // A slot's value: its binding, else the widget's `field`
  function value(slot, field) {
    const b = root.bind[slot];
    return b ? CustomWidgetData.elementValue(root.fields, b) : field ? root.fields?.[field] : undefined;
  }

  // A slot as text ("" for nothing)
  function text(slot, field) {
    return CustomWidgetData.asText(root.value(slot, field));
  }

  // The value, min and max slots as numbers (each bound, else the
  // output's own: CustomWidgetData.elementRange)
  readonly property var range: CustomWidgetData.elementRange(root.fields, root.bind)

  // 0-1 of the value between min and max; -1 without a value
  function ratio() {
    return CustomWidgetData.elementRatio(root.fields, root.bind);
  }

  // The state's colour from the script, or null
  readonly property var stateColor: root.fields?.color ? Theme.resolveColor(root.fields.color) : null

  // The colour part (CustomElementBase.yaml's x-parts.color): a picked
  // colour, else `fallback`. Graphics (`state`) take the state's colour
  // when left on Auto; text (`text`, which has a stateColor switch) only
  // when asked
  function colorOf(fallback) {
    const picked = root.options.color;
    const byState = "stateColor" in root.options ? root.options.stateColor : picked === "";
    if (byState && root.stateColor !== null)
      return root.stateColor;
    return picked ? Theme.resolveColor(picked) : fallback;
  }

  // Run one of the element's actions with `value` filled in
  function act(action, value) {
    if (root.actionsEnabled)
      CustomWidgetsManager.runCommand(root.widgetId, root.actions[action] ?? "", value);
  }
}
