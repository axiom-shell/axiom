pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.apps

// What every custom widget element is given (CustomElement loads one by its
// kind, elements/<Type>/Custom<Type>.qml): its config, the widget's resolved
// fields and history, and helpers reading its bindings and running its
// action (a named one through CustomWidgetsManager.invoke, else its commands). Bindings: a field
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
  // The definition has an action command (named actions can run it)
  property bool invokeSet: false
  // The script isn't answering (a start error, an exit): named actions are off
  property bool failing: false
  // Another action holds the widget's script actions (CustomWidgetsManager.busy)
  property bool busy: false

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
  readonly property var stateColor: root.fields?.color ? Style.resolve(root.fields.color) : null

  // The colour part (CustomElementBase.yaml's x-parts.color): a picked
  // colour, else `fallback`. Graphics (`state`) take the state's colour
  // when left on Auto; text (`text`, which has a stateColor switch) only
  // when asked
  function colorOf(fallback) {
    const picked = root.options.color;
    const byState = "stateColor" in root.options ? root.options.stateColor : picked === "";
    if (byState && root.stateColor !== null)
      return root.stateColor;
    return picked ? Style.resolve(picked) : fallback;
  }

  // The named action the element runs instead of its commands ("" none);
  // a built-in is "axiom:…"
  readonly property string actionId: root.element?.action ?? ""
  readonly property bool builtin: root.actionId.startsWith("axiom:")
  // Whether pressing it does something: actions on, and for a named one the
  // sample leaves it enabled and the script can run it
  readonly property bool canRun: root.actionsEnabled && (root.actionId === "" || (CustomWidgetData.actionEnabled(root.fields?.actions, root.actionId) && (root.builtin || (root.invokeSet && !root.busy && !root.failing))))

  // Its named action's last run, when it failed (CustomWidgetsManager.lastAction:
  // `message` the stderr line, `at` when), until the action runs again; else null
  readonly property var failed: {
    const last = CustomWidgetsManager.lastAction[root.widgetId];
    return root.actionId !== "" && last && last.failed && last.action === root.actionId ? last : null;
  }

  // The ink that reads on `color`, a colour from data (a custom widget's
  // tone): called per element, never per row
  function inkOn(color) {
    return Tone.readableOn(color, Style.surfacePage, [Style.text]); // style-exempt: data colour (a custom widget's tone), its ink once per element
  }

  // Run one of the element's actions with `value` filled in
  function act(action, value) {
    if (root.actionsEnabled) // lock-inert: actionsEnabled is off on the lock screen
      CustomWidgetsManager.runCommand(root.widgetId, root.actions[action] ?? "", value);
  }

  // Press: the element's named action when it has one (`continuous`: a
  // slider's, the latest value wins), else its `kind` command. Returns ""
  // when it ran, else why not (CustomWidgetsManager.invoke)
  function run(kind, value, continuous) {
    if (root.actionId === "")
      root.act(kind, value);
    else if (root.actionsEnabled) // lock-inert: actionsEnabled is off on the lock screen
      return CustomWidgetsManager.invoke(root.widgetId, root.actionId, value, !!continuous);
    return "";
  }
}
