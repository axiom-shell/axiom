pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Ring element (and, with `gauge`, the Gauge's): the
// value between min and max as a ring (a gauge opens at the bottom), a
// label inside: the percentage, the value with the output's unit, or an
// icon.
CustomElementBase {
  id: root

  property bool gauge: false
  readonly property real share: Math.max(0, root.ratio())
  readonly property string inside: root.options.inside
  // The output's unit goes with its own value, not a bound one
  readonly property string unit: root.bind.value ? "" : String(root.fields?.unit ?? "")
  readonly property string label: {
    if (root.bind.label)
      return root.text("label");
    if (root.inside === "percent")
      return root.ratio() < 0 ? "–" : Math.round(root.share * 100) + "%";
    if (root.inside === "value")
      return root.range.value === undefined ? "–" : (Math.round(root.range.value * 10) / 10) + root.unit;
    return "";
  }

  PercentageCircle {
    id: ring
    anchors.fill: parent
    sweep: root.gauge ? 240 : 360
    percentage: root.share * 100
    fillColor: root.colorOf(Theme.accent)
    iconText: root.inside === "icon" ? (root.fields?.icon || root.fallbackIcon) : ""
    iconColor: ring.fillColor
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
