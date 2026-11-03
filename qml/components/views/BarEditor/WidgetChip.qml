pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One bar widget in the editor: its type's icon and name, as a pill
// (`payload`: what dragging it carries, { kind, zone, index, type })
DragChip {
  id: root

  // `dragLayer` is the DragLayer that carries it and names the types
  property string type: ""
  // The widget's own `visible: false` (kept in config, not shown on the bar)
  property bool hiddenWidget: false
  // Hidden by a running bar for want of room
  property bool crowded: false
  // Left in place, faded, while it's being carried
  property bool faded: false

  icon: root.dragLayer.icon(root.type)
  label: root.compact ? root.dragLayer.shortLabel(root.type) : root.dragLayer.label(root.type)
  opacity: root.faded ? 0.3 : (root.hiddenWidget ? 0.6 : 1)

  // Hidden on the bar
  StyledIcon {
    visible: root.hiddenWidget
    text: "visibility_off"
    textColor: root.ink
    opacity: 0.7
  }

  // No room for it on the bar
  StyledIcon {
    visible: root.crowded && !root.hiddenWidget
    text: "compress"
    textColor: root.selected ? root.ink : Theme.warning
  }
}
