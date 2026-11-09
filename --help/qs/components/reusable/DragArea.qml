pragma ComponentBehavior: Bound
import QtQuick

// A MouseArea that tells a press-and-move drag from a click: past
// `threshold` pixels it's a drag (dragStarted at the press point, then
// dragMoved), released it's dropped; a press that didn't move is tapped.
// With a `dragLayer` (the bar and overlay editors'), the drag carries
// `payload` there: begin, move, end and cancel are forwarded to it.
MouseArea {
  id: root

  // False: it only taps
  property bool dragEnabled: true
  // An object with begin(payload, item, x, y), move(item, x, y), end()
  // and cancel()
  property var dragLayer: null
  property var payload: null
  property real threshold: 6
  // Set from the drag's start until the next press, so the click that
  // follows a drop isn't taken for a tap
  property bool dragged: false

  property real _pressX: 0
  property real _pressY: 0

  signal dragStarted(real x, real y)
  signal dragMoved(real x, real y)
  signal dropped
  signal dragCanceled
  signal tapped

  hoverEnabled: true
  // Keep the pointer while carrying over a scrolling area
  preventStealing: true
  cursorShape: root.dragged ? Qt.ClosedHandCursor : (root.dragEnabled ? Qt.OpenHandCursor : Qt.PointingHandCursor)

  onPressed: mouse => {
    root._pressX = mouse.x;
    root._pressY = mouse.y;
    root.dragged = false;
  }
  onPositionChanged: mouse => {
    if (!root.pressed || !root.dragEnabled)
      return;
    if (!root.dragged && Math.hypot(mouse.x - root._pressX, mouse.y - root._pressY) > root.threshold) {
      root.dragged = true;
      root.dragStarted(root._pressX, root._pressY);
    }
    if (root.dragged)
      root.dragMoved(mouse.x, mouse.y);
  }
  onDragStarted: (x, y) => {
    if (root.dragLayer)
      root.dragLayer.begin(root.payload, root, x, y);
  }
  onDragMoved: (x, y) => {
    if (root.dragLayer)
      root.dragLayer.move(root, x, y);
  }
  onDropped: {
    if (root.dragLayer)
      root.dragLayer.end();
  }
  onDragCanceled: {
    if (root.dragLayer)
      root.dragLayer.cancel();
  }

  onReleased: {
    if (root.dragged)
      root.dropped();
  }
  onCanceled: {
    if (root.dragged)
      root.dragCanceled();
    root.dragged = false;
  }
  onClicked: {
    if (!root.dragged)
      root.tapped();
  }
}
