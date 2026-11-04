pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One bar widget in the editor: its type's icon and label, as a pill
// (`payload`: what dragging it carries, { kind, zone, index, type }). A
// right click asks for its menu (DragChip's `menuRequested`).
DragChip {
  id: root

  // `dragLayer` is the DragLayer that carries it and names the types
  // (a library key: a custom widget's is "CustomWidget:<id>")
  property string type: ""
  // The widget's own `visible: false` (kept in config, not shown on the bar)
  property bool hiddenWidget: false
  // Hidden by a running bar for want of room
  property bool crowded: false
  // Left in place, faded, while it's being carried
  property bool faded: false
  // Its place in the order a crowded bar drops widgets in (1 goes first;
  // 0 shows none: a spacer, or the badges off)
  property int dropOrder: 0

  hasMenu: true
  icon: root.dragLayer.icon(root.type)
  label: root.dragLayer.label(root.type)
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

  // When it goes on a crowded bar
  CountBadge {
    shown: root.dropOrder > 0
    text: String(root.dropOrder)
    color: root.selected ? Theme.background : Theme.accent
    textColor: root.selected ? Theme.accent : Theme.background
  }
}
