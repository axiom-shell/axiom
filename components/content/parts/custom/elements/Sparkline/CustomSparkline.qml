pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.content.parts
import qs.components.content.parts.custom

// A custom widget's Sparkline element: the last samples of a number (its
// value binding, or the widget's value) from CustomWidgetsManager's
// history, between min and max (CustomWidgetData.graphRange: with no max
// bound or given, it scales to the largest).
CustomElementBase {
  id: root

  readonly property var graphRange: CustomWidgetData.graphRange(root.fields, root.bind)

  Sparkline {
    anchors.fill: parent
    values: root.history?.[root.bind.value ?? ""] ?? []
    minValue: root.graphRange.min
    maxValue: root.graphRange.max
    lineColor: root.colorOf(Theme.accent)
  }
}
