pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.content.parts

// A custom widget's Figure element: a big value with its unit and a caption
// (the widget's value, unit and subtext by default).
// options: color
CustomElementBase {
  id: root

  readonly property string shownValue: root.bind.value ? root.text("value") : root.fields?.value !== undefined ? String(Math.round(root.fields.value * 10) / 10) : (root.fields?.plain ?? "")

  StatFigure {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, root.width)
    value: root.shownValue
    unit: root.text("unit", "unit")
    label: root.text("label", "subtext")
    valueColor: root.colorOf("color", Theme.foreground)
    valueSize: Math.max(Appearance.fontSize, Math.min(Appearance.fontSize * 4, root.height * 0.5, root.width / Math.max(3, root.shownValue.length + 1) * 1.5))
  }
}
