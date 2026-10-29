pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.content.parts

// A custom widget's Sparkline element: the last samples of a number (its
// value binding, or the widget's value), from CustomWidgetsManager's
// history.
// options: max (0 scales to the largest), color
CustomElementBase {
  id: root

  Sparkline {
    anchors.fill: parent
    values: root.history?.[root.bind.value ?? ""] ?? []
    maxValue: parseFloat(root.opt("max", 0))
    lineColor: root.colorOf("color", Theme.accent)
  }
}
