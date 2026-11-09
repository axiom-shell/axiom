pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// i18n: keys from the schema (module labels)
// A module type in the library: its icon and name.
// Dragging it carries a new module at its default size; a click is
// `clicked`.
DragChip {
  id: root

  required property var typeInfo

  icon: root.typeInfo.icon
  label: I18n.tr(root.typeInfo.label)
  readonly property var size: root.dragLayer?.editor.defaultSize(root.typeInfo.type) ?? OverlayConfig.defaultSize(root.typeInfo.type)
  payload: ({
      "kind": "module-add",
      "type": root.typeInfo.type,
      "w": root.size[0],
      "h": root.size[1],
      "icon": root.icon,
      "label": root.label
    })
}
