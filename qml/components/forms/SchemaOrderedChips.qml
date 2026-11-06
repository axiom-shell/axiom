pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// i18n: keys from callers and the schema (option labels, group names)
// An array of enum strings whose order counts (`x-ordered`): the chosen
// options above, in their order, dragged into place or clicked away; the
// others below (by `x-enumGroups`, when given), a click adding one at the
// end. Each change is `edited` with the whole new array.
ColumnLayout {
  id: root

  property string label
  property string description
  property Component headerExtra: null
  // The value now, and every option it may hold
  property var value: []
  property var options: []
  // { value: label }, { value: icon }, { value: group }
  property var labels: ({})
  property var icons: ({})
  property var groups: ({})

  signal edited(var value)

  readonly property var chosen: (root.value ?? []).filter(v => root.options.includes(v))
  // The options not chosen, as [{ name, values }] in the order each
  // group first comes in the options ("" for those without one)
  readonly property var available: root.options.filter(v => !root.chosen.includes(v)).reduce((out, v) => {
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

  function labelOf(v) {
    return root.labels[v] ?? I18n.tr(v);
  }

  function add(v) {
    root.edited(root.chosen.concat([v]));
  }

  function remove(index) {
    const next = root.chosen.slice();
    next.splice(index, 1);
    root.edited(next);
  }

  // Moves the chosen option at `from` to before the one at `to` (the
  // count: the end)
  function move(from, to) {
    const next = root.chosen.slice();
    const [v] = next.splice(from, 1);
    next.splice(to > from ? to - 1 : to, 0, v);
    root.edited(next);
  }

  spacing: Widget.spacing

  FieldHeader {
    label: root.label
    description: root.description
    trailing: root.headerExtra
  }

  // Carries the chosen chips. Takes no room: it's only the coordinate
  // space, and draws the carried chip's label
  DragLayer {
    id: carrier
    Layout.fillWidth: true
    Layout.preferredHeight: 0
    z: 10
    accepts: (target, drag) => target === chosenTarget
    onDropped: (drag, target, index) => root.move(drag.index, index)
    onMoved: point => ghost.at = point

    StyledContainer {
      id: ghost
      property point at: Qt.point(0, 0)
      visible: carrier.dragging !== null
      x: ghost.at.x + Widget.spacing
      y: ghost.at.y - height / 2
      implicitWidth: ghostLabel.implicitWidth + Widget.padding * 2
      implicitHeight: Widget.height
      backgroundColor: Theme.accent

      StyledText {
        id: ghostLabel
        anchors.centerIn: parent
        text: carrier.dragging?.label ?? ""
        textColor: Theme.background
      }
    }
  }

  FlowDropTarget {
    id: chosenTarget
    visible: root.chosen.length > 0
    Layout.fillWidth: true
    implicitHeight: chosenFlow.implicitHeight
    dragLayer: carrier
    repeater: chosenRepeater

    Flow {
      id: chosenFlow
      width: chosenTarget.width
      spacing: Widget.spacing / 2

      Repeater {
        id: chosenRepeater
        model: root.chosen

        DragChip {
          id: chip
          required property string modelData
          required property int index
          icon: root.icons[chip.modelData] ?? ""
          label: root.labelOf(chip.modelData)
          dragLayer: carrier
          payload: ({
              "index": chip.index,
              "label": chip.label
            })
          opacity: carrier.dragging?.index === chip.index ? 0.4 : 1
          onClicked: root.remove(chip.index)

          StyledIcon {
            text: "close"
            textColor: chip.ink
            textSize: Appearance.fontSizeBy(-2)
          }
        }
      }
    }
  }

  StyledText {
    visible: root.chosen.length === 0
    Layout.fillWidth: true
    text: I18n.tr("None chosen. Add some from below.")
    textColor: Theme.foregroundAlt
    wrapMode: Text.Wrap
  }

  // The options not chosen: a click adds one at the end
  Repeater {
    model: root.available

    ColumnLayout {
      id: group
      required property var modelData
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledText {
        visible: group.modelData.name !== "" && root.available.length > 1
        text: I18n.tr(group.modelData.name)
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-1)
        font.weight: Font.Medium
      }

      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: group.modelData.values

          SegmentButton {
            id: option
            required property string modelData
            Layout.fillWidth: false
            iconText: root.icons[option.modelData] ?? "add"
            text: root.labelOf(option.modelData)
            onClicked: root.add(option.modelData)
          }
        }
      }
    }
  }
}
