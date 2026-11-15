pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config
import qs.components.reusable

// The Keybinds page's filters (both tabs: the list's KeybindFilter and the
// editor's KeybindManager.page.visibleKey). The root is the `Filters` button
// for a toolbar's `trailing`: primary, with a count, while any chip is on;
// it opens every chip, in groups set apart by a short line, in a popover.
// ActiveFilters goes in the toolbar's `filters` line: only the chips that
// are on, one tap each to clear, then Clear.
StyledTextButton {
  id: root

  // [{ id, options: [{ value, label }] }]; empty groups are skipped
  property var groups: []
  // { <group id>: [selected values] }
  property var selection: ({})

  signal toggled(string group, string value)

  // How many chips are on
  readonly property int activeCount: root.groups.reduce((sum, group) => sum + (root.selection[group.id] ?? []).length, 0)
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

  kind: root.activeCount > 0 ? "primary" : "tonal"
  iconText: "filter_list"
  text: I18n.tr("Filters")
  implicitHeight: Widget.height
  onClicked: popover.opened ? popover.close() : popover.open()

  CountBadge {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: -Math.round(height / 3)
    anchors.rightMargin: -Math.round(width / 3)
    shown: root.activeCount > 0
    text: String(root.activeCount)
    color: Style.onAccent
    textColor: Style.accent
  }

  Popup {
    id: popover
    x: root.width - width
    y: root.height + Widget.spacing
    width: Widget.textPx(440)
    padding: Widget.padding
    margins: Widget.spacing
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: DropdownSurface {
      floating: true
    }

    contentItem: Flow {
      spacing: Widget.spacing

      // Built only while shown
      Repeater {
        model: popover.visible ? root._items : []

        delegate: Loader {
          id: item
          required property var modelData
          sourceComponent: modelData.divider ? divider : chip

          Component {
            id: divider

            Item {
              implicitWidth: Style.dividerWidth
              implicitHeight: Widget.smallHeight

              StyledSeparator {
                anchors.centerIn: parent
                width: Style.dividerWidth
                height: parent.height * 0.6
                backTone: "raised"
              }
            }
          }

          Component {
            id: chip

            ToggleChip {
              text: item.modelData.label
              checked: (root.selection[item.modelData.group] ?? []).includes(item.modelData.value)
              onToggled: root.toggled(item.modelData.group, item.modelData.value)
            }
          }
        }
      }
    }
  }
}
