pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.apps
import qs.components.content.parts
import qs.components.content.parts.custom

// A custom widget's Sparkline element: a series the script prints (its value
// binding, or a list in the sample: drawn at once, the last 240), else the
// last samples of a number from CustomWidgetsManager's history, between min
// and max (CustomWidgetData.graphRange: with no max bound or given, it
// scales to the largest of both series). `value2` adds a second line in the
// same way; `style` is a line or bars.
CustomElementBase {
  id: root

  readonly property var graphRange: CustomWidgetData.graphRange(root.fields, root.bind)
  // A list the script printed, else null: the number's history
  readonly property var listed: CustomWidgetData.series(root.value("value"), 240)
  readonly property var listed2: root.bind.value2 ? CustomWidgetData.series(root.value("value2"), 240) : null

  Sparkline {
    anchors.fill: parent
    values: root.listed ?? root.history?.[root.bind.value ?? ""] ?? []
    values2: root.bind.value2 ? root.listed2 ?? root.history?.[root.bind.value2] ?? [] : []
    // A list is as long as it is (at least 2), a history as the service keeps
    capacity: root.listed !== null || root.listed2 !== null ? Math.max(2, root.listed?.length ?? 0, root.listed2?.length ?? 0) : CustomWidgetsManager.historyLength
    style: root.options.style
    minValue: root.graphRange.min
    maxValue: root.graphRange.max
    lineColor: root.colorOf(Style.accent)
  }
}
