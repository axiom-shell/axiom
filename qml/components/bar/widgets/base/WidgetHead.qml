pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable

// A head at the start of a BarWidget that draws its own content (Time,
// the tray, Workspaces): an icon, a short text or an item of the widget's
// own (`ownHead`). On a split bar it's the widget's icon part, the rest its
// label, as an IconTextRow's icon and label (BarShapes.splitPart).
// The widget places it at `start` along itself (its padding, or where its
// centred content starts), adds `length` to its size and starts its
// content after it, and passes on `splits`, `splitAt` and `splitPart`.
Item {
  id: root

  required property var barConfig
  // An item of the widget's own, measured by its implicit size (Time's
  // date), else a Material Symbols name, else a short text
  property Item ownHead: null
  property string icon: ""
  property string text: ""
  required property color iconColor
  required property color textColor
  // The colors follow a change by gliding unless `glides` is off (a pulse
  // sets them each frame)
  property bool glides: true
  readonly property Item head: ownHead ?? (icon !== "" ? iconHead : text !== "" ? textHead : null)
  // Where it starts along the widget
  property real start: barConfig.innerPadding
  // Something follows it (the widget's own content): with nothing, it
  // doesn't split
  property bool hasLabel: true

  readonly property bool vertical: barConfig.vertical
  readonly property bool shown: head !== null
  readonly property real headLength: shown ? Math.ceil(vertical ? head.implicitHeight : head.implicitWidth) : 0
  readonly property bool splits: shown && hasLabel && barConfig.splitRoom >= 0
  // The gap before the content: a split bar's room, else an icon's gap to
  // its label (BarWidget's row spacing)
  readonly property real gap: !shown || !hasLabel ? 0 : splits ? barConfig.splitRoom : barConfig.iconGap
  // The room it takes along the widget, its gap included
  readonly property real length: headLength + gap
  readonly property var _place: splits ? BarShapes.splitPart(vertical, start, headLength, gap, barConfig.thickness / 2, barConfig.fontSize) : null
  readonly property real splitAt: _place?.at ?? -1
  readonly property rect splitPart: _place?.part ?? Qt.rect(0, 0, 0, 0)

  visible: shown
  x: vertical ? 0 : start
  y: vertical ? start : 0
  width: vertical ? barConfig.thickness : headLength
  height: vertical ? headLength : barConfig.thickness

  // Centred across the bar
  Binding {
    target: root.head
    when: root.head !== null
    property: "parent"
    value: root
  }
  Binding {
    target: root.head
    when: root.head !== null
    property: "x"
    value: root.vertical ? Math.round((root.width - (root.head?.implicitWidth ?? 0)) / 2) : 0
  }
  Binding {
    target: root.head
    when: root.head !== null
    property: "y"
    value: root.vertical ? 0 : Math.round((root.height - (root.head?.implicitHeight ?? 0)) / 2)
  }

  StyledIcon {
    id: iconHead
    visible: root.head === iconHead
    text: root.icon
    textColor: root.iconColor
    textSize: root.barConfig.fontSize

    ColorGlide on color {
      enabled: root.glides
    }
  }

  Text {
    id: textHead
    visible: root.head === textHead
    text: root.text
    color: root.textColor
    textFormat: Text.PlainText
    font.family: Appearance.fontFamily
    font.pixelSize: root.barConfig.fontSize
    font.features: {
      "tnum": 1
    }

    ColorGlide on color {
      enabled: root.glides
    }
  }
}
