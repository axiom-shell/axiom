pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// A bar switcher cell's pointer area, hit in the cell's box as drawn. As a
// segment of the bar's run (`shape`: the widget's Background off) it
// reaches past its parent as far as the box does (`margins`, by default
// BarShapes.cellMargins: back under the cell before, out to a tab's edge)
// and holds only the points in the box's shape (BarShapes.cellContains),
// so the corners beside a powerline cap answer for the cell whose box
// shows there. `box` is the item the shape is drawn on (its parent, or a
// box shared by several areas, each given its own `margins`). With no
// shape, its parent's bounds. The widget's hit area asks it whether it's
// hovered (BarWidgetHost's `hovers`).
MouseArea {
  id: root

  // The cell's shape (BarShapes.cellShape), or null
  property var shape: null
  property bool vertical: false
  property Item box: parent
  // How far it reaches past its parent on each side: { left, top, right, bottom }
  property var margins: BarShapes.cellMargins(root.shape, root.shape, root.vertical)

  x: -root.margins.left
  y: -root.margins.top
  width: (root.parent?.width ?? 0) + root.margins.left + root.margins.right
  height: (root.parent?.height ?? 0) + root.margins.top + root.margins.bottom
  containmentMask: QtObject {
    function contains(point: point): bool {
      // A containmentMask replaces the bounds check
      if (point.x < 0 || point.y < 0 || point.x >= root.width || point.y >= root.height || !root.box)
        return false;
      const at = root.mapToItem(root.box, point.x, point.y);
      return BarShapes.cellContains(root.shape, at.x, at.y, root.box.width, root.box.height, root.vertical);
    }
  }
}
