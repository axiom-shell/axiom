pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods

// What a bar widget draws in on its bar (BarsConfig.widgetColors): its
// color for its state, whether that's its Auto own color, where it sits
// along the bar for the bar's gradient, and from those `colors` (muted and
// pressed as set), `drawnColors` (and a pulse between it and its muted
// self) and `paint`, the colors its parts draw in. BarWidget's, which
// passes its inputs through as its own.
QtObject {
  id: root

  required property var barConfig
  property var properties
  // Its widget's length along the bar
  property real length: 0
  // The color field its accentColor shows for its state ("" for none or a
  // color of its own), and that color. A state names its color (`stateColorName`:
  // a failure's "error") in place of the field's. Only its Auto own color
  // (`accentAuto`) gives way to the bar's gradient.
  property string accentField: ""
  property string stateColorName: ""
  property color accentColor: Theme.resolveColor(root.stateColorName !== "" ? root.stateColorName : root.properties?.[root.accentField] ?? "")
  // Its Auto fields ({ key: { role, gradient } }, BarsConfig.withAutoColors), and where it sits
  // along its bar as laid out, for the bar's gradient (set by its host)
  property var autoColors: ({})
  property real barOffset: 0
  property real barLength: 0
  // It shows an icon part and a label apart (split), and the pointer is
  // over it (Fill on hover)
  property bool splits: false
  property bool hovered: false
  // It draws a pill level (its background filled to its value)
  property bool level: false
  // It is dimmed (an off lock key, a paused timer), pressed, and
  // pulsing: `pulse` (0-1) is how far it is between itself and its muted
  // self while it does
  property bool muted: false
  property bool pressed: false
  property bool pulsing: false
  property real pulse: 0
  // "Colour the text by state" (BarWidgetStyle.stateContent): the display
  // `appearance` ({ colorText }) or null for none, and whether it has a
  // state now (its color: the drawn accent)
  property var appearance: null
  property bool hasState: true
  property color stateColor: root.drawnColors.accent
  // Its text color's name: a widget with no field for it (the tray,
  // Workspaces: their heads) the field's default
  readonly property string _foreground: root.properties?.foregroundColor ?? "base00"

  // Its color for its state is its Auto own color (a named state color
  // is never)
  readonly property bool accentAuto: root.stateColorName === "" && root.autoColors[root.accentField]?.gradient === true
  // Where its middle sits along the bar (0-1), or -1 without a gradient
  readonly property real barSpot: BarGradient.spot(0, root.length, root.barOffset, root.barLength)
  // (These read only config, the state colour, where it sits and its flags:
  // never what it draws, which reads them.)
  readonly property var colors: BarsConfig.widgetColors(root.barConfig, root.accentColor, root._foreground, {
    "splits": root.splits,
    "hovered": root.hovered,
    "spot": root.barSpot,
    "auto": root.accentAuto,
    "level": root.level,
    "muted": root.muted,
    "pressed": root.pressed
  })
  // Its muted self, only while it pulses
  readonly property var mutedColors: root.pulsing ? BarsConfig.widgetColors(root.barConfig, root.accentColor, root._foreground, {
    "splits": root.splits,
    "hovered": root.hovered,
    "spot": root.barSpot,
    "auto": root.accentAuto,
    "level": root.level,
    "muted": true,
    "pressed": root.pressed
  }) : null
  // `colors` as drawn: a pulse's mix of them
  readonly property var drawnColors: root.pulse <= 0 || root.mutedColors === null ? root.colors : BarWidgetStyle.mixColors(root.colors, root.mutedColors, root.pulse)
  // What its text and its icon draw in: its colors', or its state's
  // where its appearance colours by state
  readonly property var content: BarWidgetStyle.stateContent(root.drawnColors, root.appearance, root.stateColor, root.hasState)

  // `name`'s color as set on the widget (resolved, "" for none)
  function own(name) {
    return Theme.resolveColor(root.properties?.[name] ?? "");
  }

  // `name`'s color before it is read on its part: the bar's gradient where
  // the field is Auto and gives way to it, the bar's text color under
  // an Auto field's neutral or active role, else the widget's own
  function fieldColor(name) {
    return BarWidgetStyle.fieldColor(root.barConfig.palette, root.barSpot, root.own(name), root.autoColors[name]?.gradient === true, root.autoColors[name]?.role ?? "");
  }

  // `name`'s color on its `part` ("text" | "icon" | "mark" | "headText"),
  // read where that part sits
  function field(name, part) {
    return BarWidgetStyle.content(root.drawnColors, root.fieldColor(name), part);
  }

  // `color` dimmed to sit back where `part` ("text" | "icon" | "headText")
  // sits
  function mutedOf(part, color) {
    return BarWidgetStyle.muted(part === "text" ? root.drawnColors.textBack : root.drawnColors.iconBack, color);
  }

  // The colors its parts draw in: text, icon, headText and graphic (a
  // ring's or bar's line, track, caption), and the functions that read a
  // color of its own on them (field, muted) or give one as set (line)
  readonly property var paint: ({
      "text": root.content.text,
      "icon": root.content.icon,
      "headText": root.drawnColors.headText,
      "graphic": root.content.graphic,
      "muted": (part, color) => root.mutedOf(part, color ?? ({
            "text": root.content.text,
            "icon": root.content.icon,
            "headText": root.drawnColors.headText
          })[part]),
      "field": (name, part) => root.field(name, part),
      "line": name => root.own(name)
    })
}
