pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.reusable
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
  // trigger -> its argument (the text added to the action's command)
  readonly property var args: element?.args ?? ({})
  // Drawn down its box rather than across (a Bar, Segments, Separator)
  readonly property bool vertical: root.height > root.width

  // -- Placement and size (CustomElementBase.yaml's place and size parts) --
  // `align` (Left | Center | Right) and `valign` (Top | Middle | Bottom) of
  // content smaller than the box, as Text's alignments for a text kind
  readonly property int hAlign: ({
      "left": Text.AlignLeft,
      "right": Text.AlignRight
    })[root.options.align] ?? Text.AlignHCenter
  readonly property int vAlign: ({
      "top": Text.AlignTop,
      "bottom": Text.AlignBottom
    })[root.options.valign] ?? Text.AlignVCenter
  // The padding inside the box: 0, or a little once the element draws a
  // background (a filled Text sets it); the only padding there is
  property real inset: 0
  // `size` other than Fit as the shell's text size, 0 for Fit
  readonly property real fixedTextSize: ({
      "small": Style.typeCaption,
      "normal": Style.typeBody,
      "large": Style.typeHeadline,
      "huge": Style.typeBody * 2
    })[root.options.size] ?? 0
  // The same as an icon's size, 0 for Fit
  readonly property real fixedIconSize: ({
      "small": Style.iconSm,
      "normal": Style.iconMd,
      "large": Style.iconLg,
      "huge": Style.iconXl
    })[root.options.size] ?? 0

  // Where content `w` px wide starts across the box (`align`)
  function placeX(w) {
    return CustomWidgetData.alignOffset(root.options.align ?? "center", root.width - w);
  }

  // Where content `h` px tall starts down the box (`valign`)
  function placeY(h) {
    return CustomWidgetData.alignOffset(root.options.valign ?? "middle", root.height - h);
  }

  // A text size for a box `boxH` px tall: the fixed size, else (Fit) four
  // fifths of the box, never below the smallest type
  function textSizeFor(boxH) {
    return root.fixedTextSize || Math.max(Style.typeMicro, boxH * 0.8); // fitted: the element's box
  }

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

  // What the element shows (its first slot's value: a colour rule or
  // Visible that names no key reads it); CustomElement passes the kind's slots
  property var kindSlots: []
  readonly property var own: CustomWidgetData.ownValue(root.fields, root.bind, root.kindSlots[0] ?? "")
  // The state's colour from the script, or null; the error colour while the
  // script fails
  readonly property var stateColor: root.fields?.failure ? Style.error : (root.fields?.color ? Style.resolve(root.fields.color) : null)

  // The colour `key` of the element's colour part (CustomElementBase.yaml's
  // x-parts.color): the first rule of `<key>States` that holds, else the
  // picked one, else `auto`
  function colorFor(key, auto) {
    const name = CustomWidgetData.colorFor(root.options[key], root.options[key + "States"], root.fields, root.own, "");
    return name !== "" ? Style.resolve(name) : auto;
  }

  // The element's main colour (`color`): Auto (and a rule's Auto) takes the
  // script's state colour when it gives one, else `fallback`
  function colorOf(fallback) {
    return root.colorFor("color", root.stateColor ?? fallback);
  }

  // The action `trigger` runs (an entry of widgetActions), or null
  function actionFor(trigger) {
    return CustomWidgetData.actionOf({
      "actions": {
        "items": root.widgetActions
      }
    }, root.run[trigger] ?? "");
  }

  // Its Enabled condition (enabledWhen) holds for the current sample
  readonly property bool allowed: CustomWidgetData.shown(root.element?.enabledWhen, root.fields, root.own)

  // Whether `trigger` does something now: actions on, an action picked, its
  // Enabled condition holds, the sample leaves it on and, for a command, the
  // script can run it
  function canRun(trigger) {
    const item = root.actionFor(trigger);
    if (!root.actionsEnabled || item === null || !root.allowed)
      return false;
    if (!CustomWidgetData.actionEnabled(root.fields?.actions, item))
      return false;
    return item.kind === "axiom" || (!root.busy && !root.failing);
  }

  // The trigger this element last ran (runTrigger accepted it) and when
  property string _ranTrigger: ""
  property real _ranAt: 0
  // The run the manager held the widget for when it accepted that trigger
  // (a discrete action that waits; 0: none, a continuous or detached run)
  property int _ranRun: 0
  // This element's own last run, when it failed (CustomWidgetsManager.lastAction:
  // `message` the stderr line, `at` when): the widget's last action names
  // the action its last accepted trigger picks, and finished since; else
  // null. A Toggle or a slider lets go of the state it held, an Entry keeps
  // its text, and the box flashes
  readonly property var failedRun: {
    const last = CustomWidgetsManager.lastAction[root.widgetId];
    if (!last || !last.failed || root._ranTrigger === "")
      return null;
    // A run with a number is matched by it, so only the element that started
    // it answers; one without (0) by its action and time
    if (root._ranRun > 0)
      return last.run === root._ranRun ? last : null;
    return !last.run && last.action === root.actionFor(root._ranTrigger)?.id && last.at >= root._ranAt ? last : null;
  }
  // Held for a moment after a failed run: a blink (a fixed time)
  property bool flashing: false
  onFailedRunChanged: {
    if (root.failedRun) {
      root.flashing = true;
      flashTimer.restart();
    }
  }
  Timer {
    id: flashTimer
    interval: 1200
    onTriggered: root.flashing = false
  }

  // A failed run: the box blinks red (above a kind's own children, taking
  // no input) and says why on hover
  Rectangle {
    z: 10
    anchors.fill: parent
    radius: Style.radius
    color: root.flashing ? Style.errorWash : Tone.cleared(Style.errorWash) // style-exempt: the wash at no alpha, so the blink doesn't fade through black

    ColorGlide on color {
      duration: Appearance.animSlow
      enabled: Appearance.animations
    }
  }
  HoverHandler {
    id: failHover
  }
  LazyLoader {
    active: failHover.hovered && root.failedRun !== null
    StyledToolTip {
      target: root
      text: root.failedRun?.message ?? ""
    }
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

  // Press: run the action `trigger` picks with `value` ({value}; undefined for
  // a trigger with no value of its own, a Button's; `continuous`: a slider's,
  // the latest value wins) and the trigger's argument. Returns "" when it ran, else why not
  // (CustomWidgetsManager.invoke); "no action" when none is picked
  function runTrigger(trigger, value, continuous) {
    if (!root.actionsEnabled)
      return "locked";
    const heldBefore = CustomWidgetsManager.busy[root.widgetId]?.run ?? 0;
    const refused = CustomWidgetsManager.invoke(root.widgetId, root.run[trigger] ?? "", value, !!continuous, false, root.args[trigger] ?? ""); // lock-inert: actionsEnabled is off on the lock screen
    if (refused === "") {
      root._ranTrigger = trigger;
      root._ranAt = Date.now();
      const held = CustomWidgetsManager.busy[root.widgetId];
      root._ranRun = held && held.run !== heldBefore && held.action === root.actionFor(trigger)?.id ? held.run : 0;
    }
    return refused;
  }
}
