pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A drop target over a Flow of carried items (a DragLayer's): a drop goes
// before the item nearest the pointer on its row, or after the last. Put
// the Flow in it (the default property) and name the Repeater that fills
// it; an accent bar marks where a drop would land.
Item {
  id: root

  // The DragLayer whose drags it takes
  required property var dragLayer
  // The Repeater whose items are the Flow's, in order
  required property Repeater repeater
  // What the layer's `accepts` can tell it by
  property string targetKind: "flow"

  default property alias content: holder.data

  readonly property bool hovered: root.dragLayer && root.dragLayer.hoverTarget === root

  implicitWidth: holder.childrenRect.width
  implicitHeight: holder.childrenRect.height

  // The place a drop at `point` (in the drag layer) goes before (the
  // count: after the last)
  function indexAt(point) {
    for (let i = 0; i < root.repeater.count; i++) {
      const item = root.repeater.itemAt(i);
      if (!item)
        continue;
      // In the Flow's own coordinates, as the items are placed
      const p = root.dragLayer.mapToItem(item.parent, point.x, point.y);
      // A row below the pointer: before its first item
      if (p.y < item.y)
        return i;
      if (p.y < item.y + item.height && p.x < item.x + item.width / 2)
        return i;
    }
    return root.repeater.count;
  }

  Component.onCompleted: root.dragLayer.registerTarget(root)
  Component.onDestruction: root.dragLayer.unregisterTarget(root)

  Item {
    id: holder
    anchors.fill: parent
  }

  // Where a drop lands: before the item at the hover index, or after the last
  Rectangle {
    readonly property int at: root.hovered ? root.dragLayer.hoverIndex : -1
    readonly property Item before: at >= 0 && at < root.repeater.count ? root.repeater.itemAt(at) : null
    readonly property Item last: root.repeater.count > 0 ? root.repeater.itemAt(root.repeater.count - 1) : null
    readonly property Item beside: before ?? last
    visible: at >= 0 && beside !== null
    width: Widget.px(2)
    radius: width / 2
    color: Theme.accent
    x: beside ? holder.mapFromItem(beside.parent, before ? beside.x : beside.x + beside.width, 0).x - width / 2 + (before ? -Widget.spacing / 4 : Widget.spacing / 4) : 0
    y: beside ? holder.mapFromItem(beside.parent, 0, beside.y).y : 0
    height: beside ? beside.height : 0
  }
}
