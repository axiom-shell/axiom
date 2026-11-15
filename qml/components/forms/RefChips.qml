pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An `x-ref` field holding an array of ids (the shortcuts a window rule
// pauses): the picked ones as chips, a click taking one away, then a button
// opening a picker of those not picked yet. Each change is `edited` with the
// whole new array. `options` are the ids that can be picked, in order;
// `labels` and `icons` are { id: text } and { id: icon }, an id with no label
// showing as it is (one no longer in the options still shows, so it can be
// taken away).
ColumnLayout {
  id: root

  property string label
  property string description
  property Component headerExtra: null
  // The button's text
  property string addText
  property var value: []
  property var options: []
  property var labels: ({})
  property var icons: ({})

  signal edited(var value)

  readonly property var picked: (root.value ?? []).filter(v => typeof v === "string")
  // The picker's entries: the options not picked
  readonly property var _types: root.options.filter(id => !root.picked.includes(id)).map(id => ({
        "type": id,
        "label": root.labels[id] ?? id,
        "icon": root.icons[id] ?? ""
      }))

  spacing: Widget.spacing

  FieldHeader {
    label: root.label
    description: root.description
    trailing: root.headerExtra
  }

  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: root.picked

      SegmentButton {
        id: chip
        required property string modelData
        iconText: root.icons[chip.modelData] ?? ""
        text: root.labels[chip.modelData] ?? chip.modelData
        active: true
        onClicked: root.edited(root.picked.filter(id => id !== chip.modelData))
      }
    }
  }

  StyledTextButton {
    id: addButton
    Layout.fillWidth: true
    implicitHeight: Widget.height
    iconText: "add"
    text: root.addText
    enabled: root._types.length > 0
    onClicked: picker.openAt(addButton)
  }

  // Labels are the caller's, already translated
  TypePickerPopup {
    id: picker
    parent: root
    matchWidth: true
    types: root._types
    labelOf: type => type.label
    onTypeSelected: type => root.edited(root.picked.concat([type]))
  }
}
