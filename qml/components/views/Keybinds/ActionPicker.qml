pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable

// A bind's action: a field-like button showing it (a FieldFrame holding a
// Pressable: Tab stop, Space/Return/Enter and a click open it, and so does
// Down on it), opening the shared TypePickerPopup as wide as the button, the
// actions under a heading per category (KeybindManager.actionInfo), with its
// search, Up/Down, Enter and Escape.
FieldFrame {
  id: root

  required property string currentValue
  signal picked(string action)

  // [{ type: the action, label, icon, group: its category }]
  readonly property var types: KeybindManager.actionInfo.map(info => ({
        "type": info.action,
        "label": info.label,
        "icon": KeybindManager.actionIcon(info.action),
        "group": info.section
      }))

  implicitHeight: Widget.height
  active: popup.visible

  Keys.onDownPressed: popup.openAt(root)

  Pressable {
    onClicked: popup.openAt(root)
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.padding
    spacing: Widget.spacing

    StyledIcon {
      text: KeybindManager.actionIcon(root.currentValue)
      tone: "muted"
    }

    StyledLabel {
      text: KeybindManager.actionLabels[root.currentValue] ?? root.currentValue
      overflow: "line"
      Layout.fillWidth: true
    }

    StyledIcon {
      text: "arrow_drop_down"
      tone: "muted"
      size: "md"
    }
  }

  TypePickerPopup {
    id: popup
    types: root.types
    groups: KeybindManager.actionSections
    matchWidth: true
    placeholderText: I18n.tr("Search actions")
    // The labels are already translated (KeybindManager.actionInfo)
    labelOf: type => type.label
    onTypeSelected: action => {
      if (action !== root.currentValue)
        root.picked(action);
    }
  }
}
