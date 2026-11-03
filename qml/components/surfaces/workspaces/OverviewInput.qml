pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// The overview board's only input: the pointer decides what's hovered.
// Left: click a window to focus it (an empty spot: go to that workspace), or
// drag it to another workspace or a side of another window. Middle: close
// the window. Right-drag: resize it by the edge (or corner) nearest the
// press; the steps go out every 50 ms while dragging, so it's live.
MouseArea {
  id: root

  // The OverviewGrid (geometry, items, actions)
  required property var overview

  // "" | "press" (left, not yet a drag) | "drag" | "resize"
  property string mode: ""
  property string hoveredAddress: ""
  property int hoveredCell: -1
  // The window being pressed, dragged or resized
  property string activeAddress: ""

  // Drag: the preview's corner follows the pointer at the grab offset
  property real ghostX: 0
  property real ghostY: 0
  property int dropCell: -1
  // WorkspaceGeometry.dropTarget at the pointer (null: empty workspace or a
  // floating window, which just goes where it's dropped)
  property var dropHint: null
  property real _grabX: 0
  property real _grabY: 0
  property real _pressX: 0
  property real _pressY: 0
  readonly property real threshold: 6

  // Resize: grabbed edges, the last pointer position, and the step not sent
  property var _edges: ({})
  property bool _floating: false
  property real _lastX: 0
  property real _lastY: 0
  property var _pending: ({
      dw: 0,
      dh: 0,
      dx: 0,
      dy: 0
    })

  // Stop a drag or resize without applying it. False when there was none.
  function cancel() {
    if (root.mode === "")
      return false;
    if (root.mode === "resize")
      root._flush();
    root.mode = "";
    root.activeAddress = "";
    root.dropHint = null;
    root.dropCell = -1;
    return true;
  }

  function _hover(x, y) {
    root.hoveredAddress = WorkspaceGeometry.windowAt(root.overview.items, x, y);
    root.hoveredCell = WorkspaceGeometry.cellAt(x, y, root.overview.cellW, root.overview.cellH, root.overview.gap, root.overview.columns, root.overview.ids.length);
  }

  function _updateDrop(x, y) {
    root.ghostX = x - root._grabX;
    root.ghostY = y - root._grabY;
    root.dropCell = root.hoveredCell;
    const item = root.overview.itemFor(root.activeAddress);
    root.dropHint = root.dropCell >= 0 && item && !item.floating ? root.overview.dropTargetAt(root.dropCell, Qt.point(x, y), root.activeAddress) : null;
  }

  function _flush() {
    const p = root._pending;
    if (p.dw === 0 && p.dh === 0 && p.dx === 0 && p.dy === 0)
      return;
    root.overview.resizeWindow(root.activeAddress, p.dw, p.dh, p.dx, p.dy);
    root._pending = {
      dw: 0,
      dh: 0,
      dx: 0,
      dy: 0
    };
  }

  // Board-pixel pointer motion as a size/position step. A tiled window's
  // delta moves its split with the pointer (either edge); a floating
  // window's left/top edge moves it as well as resizing.
  function _step(dx, dy) {
    const e = root._edges;
    const p = root._pending;
    const horizontal = e.left || e.right;
    const vertical = e.top || e.bottom;
    if (!root._floating) {
      root._pending = {
        dw: p.dw + (horizontal ? dx : 0),
        dh: p.dh + (vertical ? dy : 0),
        dx: 0,
        dy: 0
      };
    } else {
      root._pending = {
        dw: p.dw + (e.right ? dx : e.left ? -dx : 0),
        dh: p.dh + (e.bottom ? dy : e.top ? -dy : 0),
        dx: p.dx + (e.left ? dx : 0),
        dy: p.dy + (e.top ? dy : 0)
      };
    }
    if (!flushTimer.running)
      flushTimer.start();
  }

  hoverEnabled: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
  preventStealing: true

  cursorShape: {
    if (root.mode === "drag")
      return Qt.ClosedHandCursor;
    if (root.mode === "resize") {
      const e = root._edges;
      if ((e.left && e.top) || (e.right && e.bottom))
        return Qt.SizeFDiagCursor;
      if ((e.right && e.top) || (e.left && e.bottom))
        return Qt.SizeBDiagCursor;
      return e.left || e.right ? Qt.SizeHorCursor : Qt.SizeVerCursor;
    }
    if (root.hoveredAddress !== "")
      return Qt.OpenHandCursor;
    return root.hoveredCell >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor;
  }

  onExited: {
    if (root.mode === "") {
      root.hoveredAddress = "";
      root.hoveredCell = -1;
    }
  }

  onPressed: mouse => {
    root._hover(mouse.x, mouse.y);
    if (root.mode !== "")
      return;
    if (mouse.button === Qt.LeftButton) {
      root.mode = "press";
      root.activeAddress = root.hoveredAddress;
      root._pressX = mouse.x;
      root._pressY = mouse.y;
    } else if (mouse.button === Qt.RightButton && root.hoveredAddress !== "") {
      const item = root.overview.itemFor(root.hoveredAddress);
      if (!item)
        return;
      root.mode = "resize";
      root.activeAddress = root.hoveredAddress;
      root._floating = item.floating;
      root._edges = WorkspaceGeometry.resizeEdges(item.rect, mouse.x, mouse.y);
      root._lastX = mouse.x;
      root._lastY = mouse.y;
    }
  }

  onPositionChanged: mouse => {
    root._hover(mouse.x, mouse.y);
    if (root.mode === "press" && root.activeAddress !== "" && Math.hypot(mouse.x - root._pressX, mouse.y - root._pressY) > root.threshold) {
      const rect = root.overview.itemFor(root.activeAddress)?.rect;
      if (!rect)
        return;
      root.mode = "drag";
      root._grabX = root._pressX - rect.x;
      root._grabY = root._pressY - rect.y;
    }
    if (root.mode === "drag") {
      root._updateDrop(mouse.x, mouse.y);
    } else if (root.mode === "resize") {
      root._step(mouse.x - root._lastX, mouse.y - root._lastY);
      root._lastX = mouse.x;
      root._lastY = mouse.y;
    }
  }

  onReleased: mouse => {
    if (mouse.button === Qt.LeftButton && root.mode === "press") {
      root.mode = "";
      if (root.activeAddress !== "")
        root.overview.focusWindow(root.activeAddress);
      else if (root.hoveredCell >= 0)
        root.overview.goTo(root.hoveredCell);
      root.activeAddress = "";
    } else if (mouse.button === Qt.LeftButton && root.mode === "drag") {
      root._updateDrop(mouse.x, mouse.y);
      const cursor = root.mapToItem(null, mouse.x, mouse.y);
      root.overview.dropWindow(root.activeAddress, root.dropCell, Qt.point(mouse.x, mouse.y), Qt.point(root.ghostX, root.ghostY), cursor);
      root.cancel();
    } else if (mouse.button === Qt.RightButton && root.mode === "resize") {
      flushTimer.stop();
      root.cancel();
    } else if (mouse.button === Qt.MiddleButton && root.mode === "" && root.hoveredAddress !== "") {
      root.overview.closeWindow(root.hoveredAddress);
    }
  }

  onCanceled: root.cancel()

  Timer {
    id: flushTimer
    interval: 50
    onTriggered: root._flush()
  }
}
