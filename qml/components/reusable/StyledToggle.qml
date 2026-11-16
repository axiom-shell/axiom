pragma ComponentBehavior: Bound
import QtQuick

// A two- or three-way toggle: a SegmentRow of one SegmentButton per option,
// the thumb under the chosen one gliding across as it changes. A click picks
// the segment (the chosen one again does nothing); Tab focuses it, Space flips
// two, Left and Right step. The owner keeps the value: set `value`, and
// update it from `picked`.
SegmentRow {
  id: root

  // The option values (two or three), and the label each shows
  property var options: []
  property var labels: ({})
  property var value

  signal picked(var value)

  Repeater {
    model: root.options

    SegmentButton {
      required property var modelData

      text: root.labels[modelData] ?? ""
      active: root.value === modelData
      onClicked: {
        if (root.value !== modelData)
          root.picked(modelData);
      }
    }
  }
}
