pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.apps
import qs.services.system

// What every custom widget element is given (CustomElement loads one by its
// kind, elements/<Type>/Custom<Type>.qml): its config, the widget's resolved
// fields and history, and helpers reading its bindings and running its
// actions (the widget's, picked by `run`, through CustomWidgetsManager.invoke). Bindings: a field
// name, a path in the sample or a format (CustomWidgetData.elementValue);
// an empty one falls back to the widget's own field. Its options are its
// kind's schema (elements/<Type>/schema.yaml), every default filled.
Item {
  id: root

  // { id, type, place, bind, options, run } (a CustomElement)
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
  // The definition's actions (actions.items), which `run` picks from
  property var widgetActions: []
  // The script isn't answering (a start error, an exit): command actions are off
  property bool failing: false
  // Another action holds the widget's script actions (CustomWidgetsManager.busy)
  property bool busy: false
  // The host can take typed keys (an overlay card, an edge menu, a bar
  // popout), so an Entry works
  property bool keysHost: false
  // The module's font family (module.font), for a Text with none of its own
  property string moduleFont: ""

  readonly property var bind: element?.bind ?? ({})
  readonly property var options: element?.options ?? ({})
  // trigger -> action id (click, change, on, off, submit)
  readonly property var run: element?.run ?? ({})
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

  // The theme colour name its `tone` binding gives through the definition's
  // states ("" unbound, or a word nothing maps: CustomWidgetData.elementTone)
  readonly property string toneName: CustomWidgetData.elementTone(root.fields, root.bind)
  // The state's colour from the script, or null; the error colour while the
  // script fails
  readonly property var stateColor: root.fields?.failure ? Style.error : (root.fields?.color ? Style.resolve(root.fields.color) : null)

  // The colour part (CustomElementBase.yaml's x-parts.color): a bound
  // `tone`'s colour (every kind, text too: binding it is the request), else
  // a picked colour, else `fallback`. Graphics (`state`) take the state's
  // colour when left on Auto; text (`text`, which has a stateColor switch)
  // only when asked
  function colorOf(fallback) {
    if (root.toneName !== "")
      return Style.resolve(root.toneName);
    const picked = root.options.color;
    const byState = "stateColor" in root.options ? root.options.stateColor : picked === "";
    if (byState && root.stateColor !== null)
      return root.stateColor;
    return picked ? Style.resolve(picked) : fallback;
  }

  // The action `trigger` runs (an entry of widgetActions), or null
  function actionFor(trigger) {
    return CustomWidgetData.actionOf({
      "actions": {
        "items": root.widgetActions
      }
    }, root.run[trigger] ?? "");
  }

  // Whether `trigger` does something now: actions on, an action picked, the
  // sample leaves it on and, for a command, the script can run it
  function canRun(trigger) {
    const item = root.actionFor(trigger);
    if (!root.actionsEnabled || item === null)
      return false;
    if (!CustomWidgetData.actionEnabled(root.fields?.actions, item))
      return false;
    return item.kind === "axiom" || (!root.busy && !root.failing);
  }

  // Its `trigger` action's last run, when it failed (CustomWidgetsManager.lastAction:
  // `message` the stderr line, `at` when), until the action runs again; else null
  function failed(trigger) {
    const last = CustomWidgetsManager.lastAction[root.widgetId];
    const id = root.run[trigger] ?? "";
    return id !== "" && last && last.failed && last.action === root.actionFor(trigger)?.id ? last : null;
  }

  // An image's source from a path or URL: a URL as it is, else a file
  // (`~` expanded); "" for none. The Image element's and a List row's
  function imageUrl(path) {
    return !path ? "" : /^[a-z]+:\/\//.test(path) ? path : "file://" + Paths.expandHome(path);
  }

  // An icon theme icon's source for `name` (AppIconManager.appIcon: the
  // generic program icon when the theme lacks it), "" for no name
  function themeIcon(name) {
    return name ? AppIconManager.appIcon(name) : ""; // lock-inert: only resolves an icon file
  }

  // The ink that reads on `color`, a colour from data (a custom widget's
  // tone): called per element, never per row
  function inkOn(color) {
    return Tone.readableOn(color, Style.surfacePage, [Style.text]); // style-exempt: data colour (a custom widget's tone), its ink once per element
  }

  // Press: run the action `trigger` picks with `value` ({value}; `continuous`:
  // a slider's, the latest value wins). Returns "" when it ran, else why not
  // (CustomWidgetsManager.invoke); "no action" when none is picked
  function runTrigger(trigger, value, continuous) {
    if (!root.actionsEnabled)
      return "locked";
    return CustomWidgetsManager.invoke(root.widgetId, root.run[trigger] ?? "", value, !!continuous); // lock-inert: actionsEnabled is off on the lock screen
  }
}
