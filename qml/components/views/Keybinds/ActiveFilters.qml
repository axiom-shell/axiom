pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// The Keybinds page's chips that are on, for the toolbar's `filters` line
// (beside FilterChips' `Filters` button): one ToggleChip each, a tap clears
// it, then Clear. One line at any width: the chips scroll sideways. It takes
// FilterChips' groups and selection and sends its toggled and cleared.
RowLayout {
  id: active

  property var groups: []
  property var selection: ({})

  signal toggled(string group, string value)
  signal cleared

  // [{ group, value, label }] for each chip that is on
  readonly property var _on: active.groups.reduce((chips, group) => chips.concat(group.options.filter(option => (active.selection[group.id] ?? []).includes(option.value)).map(option => ({
          "group": group.id,
          "value": option.value,
          "label": option.label
        }))), [])

  Layout.fillWidth: true
  spacing: Widget.spacing

  Flickable {
    Layout.fillWidth: true
    implicitHeight: chips.implicitHeight
    contentWidth: chips.implicitWidth
    contentHeight: chips.implicitHeight
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Row {
      id: chips
      spacing: Widget.spacing

      // Built only while shown
      Repeater {
        model: active.visible ? active._on : []

        delegate: ToggleChip {
          required property var modelData
          text: modelData.label
          checked: true
          onToggled: active.toggled(modelData.group, modelData.value)
        }
      }
    }
  }

  StyledTextButton {
    kind: "text"
    text: I18n.tr("Clear")
    onClicked: active.cleared()
  }
}
