pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Segments element: a row (or column, by its shape) of
// blocks or dots lit up to the value between min and max (SegmentMeter).
CustomElementBase {
  id: root

  SegmentMeter {
    anchors.fill: parent
    count: root.options.count
    round: root.options.round
    share: Math.max(0, root.ratio())
    vertical: root.vertical
    litColor: root.colorOf(Theme.accent)
  }
}
