pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// A custom widget's Ring and Gauge elements: the value between min and max
// as a ring (a gauge opens at the bottom), a label inside (the percentage
// by default, or an icon).
// slots: value, min, max, label; options: color, inside (percent, value,
// icon, none)
CustomElementBase {
  id: root

  property bool gauge: false
  readonly property real share: Math.max(0, root.ratio())
  readonly property string inside: root.opt("inside", "percent")
  readonly property string label: root.bind.label ? root.text("label") : root.inside === "percent" ? (root.ratio() < 0 ? "–" : Math.round(root.share * 100) + "%") : root.inside === "value" ? (root.range.value === undefined ? "–" : String(Math.round(root.range.value * 10) / 10)) : ""

  PercentageCircle {
    id: ring
    anchors.fill: parent
    sweep: root.gauge ? 240 : 360
    percentage: root.share * 100
    fillColor: root.colorOf("color", Theme.accent)
    iconText: root.inside === "icon" ? (root.fields?.icon || root.fallbackIcon) : ""
    iconColor: root.colorOf("color", Theme.accent)
  }

  StyledText {
    visible: root.label !== ""
    anchors.centerIn: parent
    width: ring.side * 0.7
    horizontalAlignment: Text.AlignHCenter
    text: root.label
    font.bold: true
    textSize: Math.max(Appearance.fontSizeBy(-4), ring.side * 0.22)
    fontSizeMode: Text.HorizontalFit
    minimumPixelSize: Appearance.fontSizeBy(-4)
  }
}
