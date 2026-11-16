pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An array of picks as chips, a click taking one away: an `x-ref` array of
// ids (the shortcuts a window rule pauses) or an array of enum strings
// (`x-ordered`: the order counts). Each change is `edited` with the whole new
// array. `options` are the values that can be picked, in order; `labels`,
// `icons` and `groups` ({ value: text }, { value: icon }, { value: group
// heading }, a field's `x-enumGroups`) describe them, a value with no label
// showing as it is (one no longer in the options still shows, so it can be
// taken away). With `ordered` the chips drag into place (a FlowDropTarget on
// an InlineDragLayer of its own). `addMode` says how more are added:
// "inline" lists the others under the chips (under their group's header), a
// click adding one at the end; "picker" is one button opening a
// TypePickerPopup of the others.
ColumnLayout {
  id: root

  property string label
  property string description
  property Component headerExtra: null
  // Under the description (FieldHeader.below)
  property Component headerBelow: null
  property var value: []
  property var options: []
  property var labels: ({})
  property var icons: ({})
  property var groups: ({})
  property bool ordered: false
  // inline | picker
  property string addMode: "inline"
  // The picker button's text
  property string addText

  signal edited(var value)

  readonly property var picked: (root.value ?? []).filter(v => typeof v === "string")
  // The options not picked, as [{ name, values }] in the order each group
  // first comes in the options ("" for those without one)
  readonly property var available: root.options.filter(v => !root.picked.includes(v)).reduce((out, v) => {
    const name = root.groups[v] ?? "";
    const group = out.find(g => g.name === name);
    if (group)
      group.values.push(v);
    else
      out.push({
        "name": name,
        "values": [v]
      });
    return out;
  }, [])
  // The picker's entries: the options not picked
  readonly property var _types: root.options.filter(v => !root.picked.includes(v)).map(v => ({
        "type": v,
        "label": root.labelOf(v),
        "icon": root.icons[v] ?? ""
      }))

  function labelOf(v) {
    return root.labels[v] ?? I18n.tr(v);
  }

  function add(v) {
    root.edited(root.picked.concat([v]));
  }

  function remove(index) {
    const next = root.picked.slice();
    next.splice(index, 1);
    root.edited(next);
  }

  // Moves the picked value at `from` to before the one at `to` (the count:
  // the end)
  function move(from, to) {
    const next = root.picked.slice();
    const [v] = next.splice(from, 1);
    next.splice(to > from ? to - 1 : to, 0, v);
    root.edited(next);
  }

  spacing: Widget.spacing

  FieldHeader {
    label: root.label
    description: root.description
    trailing: root.headerExtra
    below: root.headerBelow
  }

  // Carries the picked chips (an ordered one's)
  InlineDragLayer {
    id: carrier
    accepts: (target, drag) => root.ordered && target === pickedTarget
    onDropped: (drag, target, index) => root.move(drag.index, index)
  }

  FlowDropTarget {
    id: pickedTarget
    visible: root.picked.length > 0
    Layout.fillWidth: true
    implicitHeight: pickedFlow.implicitHeight
    dragLayer: carrier
    repeater: pickedRepeater

    Flow {
      id: pickedFlow
      width: pickedTarget.width
      spacing: Widget.spacing / 2

      Repeater {
        id: pickedRepeater
        model: root.picked

        DragChip {
          id: chip
          required property string modelData
          required property int index
          icon: root.icons[chip.modelData] ?? ""
          label: root.labelOf(chip.modelData)
          dragLayer: carrier
          payload: root.ordered ? ({
              "index": chip.index,
              "label": chip.label
            }) : null
          opacity: carrier.dragging?.index === chip.index ? 0.4 : 1 // style-exempt: a chip being dragged dims, a drag ghost
          onClicked: root.remove(chip.index)

          StyledIcon {
            text: "close"
            textColor: chip.ink
            size: "xs"
          }
        }
      }
    }
  }

  StyledText {
    visible: root.addMode === "inline" && root.picked.length === 0
    Layout.fillWidth: true
    text: I18n.tr("None chosen. Add some from below.")
    tone: "muted"
  }

  // The options not picked: a click adds one at the end
  Repeater {
    model: root.addMode === "inline" ? root.available : []

    ColumnLayout {
      id: group
      required property var modelData
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledText {
        visible: group.modelData.name !== "" && root.available.length > 1
        text: I18n.tr(group.modelData.name)
        role: "micro"
        tone: "faint"
      }

      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: group.modelData.values

          StyledTextButton {
            id: option
            required property string modelData
            kind: "outlined"
            iconText: root.icons[option.modelData] ?? "add"
            text: root.labelOf(option.modelData)
            onClicked: root.add(option.modelData)
          }
        }
      }
    }
  }

  AddEntryButton {
    id: addButton
    visible: root.addMode === "picker"
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
    onTypeSelected: type => root.add(type)
  }
}
