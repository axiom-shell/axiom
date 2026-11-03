pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.methods

// One app on a dock: its icon (grown by the dock's magnification) and a
// running indicator, spanning the whole depth of the dock window at its
// place along it (DockWindow.starts/sizes). Click focuses or starts it,
// middle click starts another, right click opens its menu, resting on it
// shows its name and windows. Dragging moves a pinned app, pins a running
// one dropped among the pinned ones, and unpins one dropped off the dock.
Item {
  id: root

  required property int index
  required property var dockWindow

  readonly property var dock: root.dockWindow.dock
  readonly property var item: root.dockWindow.items[root.index] ?? null
  readonly property string key: root.item?.key ?? ""
  readonly property var windows: root.item?.windows ?? []
  readonly property bool focused: root.windows.some(w => w.id === DockManager.focusedId)
  readonly property real size: root.dockWindow.sizes[root.index] ?? root.dockWindow.base
  readonly property real along: root.dockWindow.starts[root.index] ?? 0
  readonly property bool vertical: root.dockWindow.vertical
  readonly property bool dragging: root.dockWindow.dragIndex === root.index
  readonly property bool hovered: area.containsMouse

  // Where the pointer is carrying it, from the press (window coordinates)
  property point dragDelta: Qt.point(0, 0)

  x: root.vertical ? 0 : root.along
  y: root.vertical ? root.along : 0
  width: root.vertical ? parent.width : root.size
  height: root.vertical ? root.size : parent.height
  z: root.dragging ? 1 : 0

  // The icon, sitting `padding` in from the box's edge side and growing away
  // from it
  Image {
    id: icon
    readonly property real fromEdge: root.dockWindow.boxOffset + root.dockWindow.pad

    x: (root.vertical ? root.dockWindow.crossAt(fromEdge, root.size) : 0) + (root.dragging ? root.dragDelta.x : 0)
    y: (root.vertical ? 0 : root.dockWindow.crossAt(fromEdge, root.size)) + (root.dragging ? root.dragDelta.y : 0)
    width: root.size
    height: root.size
    sourceSize: Qt.size(root.dockWindow.peak * 2, root.dockWindow.peak * 2)
    source: root.key ? DockManager.iconFor(root.key, root.windows[0]) : ""
    smooth: true
    mipmap: true
    asynchronous: true
    opacity: area.pressed && !root.dragging ? 0.7 : 1
  }

  // A dot per window (up to three), or a line, in the box's padding on the
  // edge side; the accent while one of them is focused
  Item {
    id: indicator
    readonly property real dot: Math.max(3, Math.min(6, root.dockWindow.base / 10))
    readonly property int dots: Math.min(3, root.windows.length)
    readonly property bool line: root.dock.running.indicator === "line"
    readonly property real alongLength: line ? root.dockWindow.base * 0.4 : dots * dot + (dots - 1) * dot
    readonly property real fromEdge: root.dockWindow.boxOffset + Math.max(1, (root.dockWindow.pad - dot) / 2)

    visible: root.dock.running.indicator !== "none" && root.windows.length > 0 && !root.dragging
    x: root.vertical ? root.dockWindow.crossAt(fromEdge, dot) : (root.size - alongLength) / 2
    y: root.vertical ? (root.size - alongLength) / 2 : root.dockWindow.crossAt(fromEdge, dot)
    width: root.vertical ? dot : alongLength
    height: root.vertical ? alongLength : dot

    Rectangle {
      visible: indicator.line
      anchors.fill: parent
      radius: indicator.dot / 2
      color: root.focused ? Theme.accent : Theme.foreground
    }

    Repeater {
      model: indicator.line ? 0 : indicator.dots

      delegate: Rectangle {
        required property int index
        x: root.vertical ? 0 : index * indicator.dot * 2
        y: root.vertical ? index * indicator.dot * 2 : 0
        width: indicator.dot
        height: indicator.dot
        radius: indicator.dot / 2
        color: root.focused ? Theme.accent : Theme.foreground
      }
    }
  }

  // Resting on it opens the small menu (name and windows)
  Timer {
    interval: 450
    running: area.containsMouse && !area.pressed && root.dockWindow.dragIndex < 0 && !root.dockWindow.menuFull && root.dockWindow.menuKey !== root.key && (root.dock.showLabels || root.windows.length > 0)
    onTriggered: root.dockWindow.openMenu(root.key, false)
  }

  DragArea {
    id: area
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    property point _press: Qt.point(0, 0)

    onPressed: mouse => {
      _press = Qt.point(mouse.x, mouse.y);
      if (!root.dockWindow.menuFull)
        root.dockWindow.closeMenu();
    }

    onDragStarted: {
      if (area.pressedButtons !== Qt.LeftButton)
        return;
      root.dockWindow.closeMenu();
      root.dockWindow.dragIndex = root.index;
    }
    onDragMoved: (mx, my) => {
      if (root.dragging)
        root.dragDelta = Qt.point(mx - _press.x, my - _press.y);
    }
    onDropped: {
      if (!root.dragging)
        return;
      const along = root.along + root.size / 2 + (root.vertical ? root.dragDelta.y : root.dragDelta.x);
      const across = root.vertical ? root.dragDelta.x : root.dragDelta.y;
      root._drop(along, across);
      root._endDrag();
    }
    onDragCanceled: root._endDrag()

    onClicked: mouse => {
      if (area.dragged)
        return;
      if (mouse.button === Qt.RightButton) {
        root.dockWindow.openMenu(root.key, true);
      } else if (mouse.button === Qt.MiddleButton) {
        DockManager.launch(root.key);
      } else {
        root.dockWindow.closeMenu();
        DockManager.activate(root.item);
      }
    }
  }

  function _endDrag() {
    root.dragDelta = Qt.point(0, 0);
    root.dockWindow.dragIndex = -1;
  }

  // Dropped with its centre at `along` (window coordinates), `across` off
  // its place: off the dock unpins it, among the pinned apps (re)pins it
  // there, after them leaves it be
  function _drop(along, across) {
    const outward = root.dockWindow.edge === ScreenEdge.Bottom || root.dockWindow.edge === ScreenEdge.Right ? -across : across;
    if (outward > root.dockWindow.thickness + root.dockWindow.base) {
      if (root.item.pinned)
        DockManager.unpin(root.dock.id, root.key);
      return;
    }
    const starts = root.dockWindow.starts;
    const sizes = root.dockWindow.sizes;
    const pinned = root.dockWindow.pinnedCount;
    let index = 0;
    for (let i = 0; i < pinned; i++) {
      if (i !== root.index && starts[i] + sizes[i] / 2 < along)
        index++;
    }
    const pinnedEnd = pinned > 0 ? starts[pinned - 1] + sizes[pinned - 1] + root.dockWindow.spacing : root.dockWindow.boxStart + root.dockWindow.pad;
    if (root.item.pinned || along < pinnedEnd)
      DockManager.pin(root.dock.id, root.key, index);
  }
}
