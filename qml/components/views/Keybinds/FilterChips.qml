pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// The Keybinds page's toggle chips, in groups set apart by a short line,
// then Clear while any is on. Both tabs use it: the list (KeybindFilter)
// and the editor (KeybindManager.page.visibleKey).
Flow {
  id: root

  // [{ id, options: [{ value, label }] }]; empty groups are skipped
  property var groups: []
  // { <group id>: [selected values] }
  property var selection: ({})
  property bool filtering: false

  signal toggled(string group, string value)
  signal cleared

  spacing: Widget.spacing

  // Chips, and a divider before each group but the first, as one list
  // so every chip wraps on its own
  readonly property var _items: root.groups.filter(group => group.options.length > 0).reduce((items, group, index) => {
    if (index > 0)
      items.push({
        "divider": true
      });
    return items.concat(group.options.map(option => ({
          "divider": false,
          "group": group.id,
          "value": option.value,
          "label": option.label
        })));
  }, [])

  Repeater {
    model: root._items

    delegate: Loader {
      id: item
      required property var modelData
      sourceComponent: modelData.divider ? divider : chip

      Component {
        id: divider

        Item {
          implicitWidth: 1
          implicitHeight: Widget.height

          StyledSeparator {
            anchors.centerIn: parent
            width: 1
            separatorHeight: parent.height * 0.6
            opacity: 0.6
          }
        }
      }

      Component {
        id: chip

        SegmentButton {
          implicitHeight: Widget.height
          text: item.modelData.label
          active: (root.selection[item.modelData.group] ?? []).includes(item.modelData.value)
          onClicked: root.toggled(item.modelData.group, item.modelData.value)
        }
      }
    }
  }

  SegmentButton {
    visible: root.filtering
    implicitHeight: Widget.height
    text: I18n.tr("Clear")
    onClicked: root.cleared()
  }
}
