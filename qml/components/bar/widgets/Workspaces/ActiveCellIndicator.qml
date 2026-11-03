pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// The active workspace's box (or underline) in a bar switcher's row of
// cells, drawn once over their boxes and under their labels (the row draws
// its WorkspaceCells in two layers around it), sliding from cell to cell as
// the active workspace changes, where the cells would each recolour. Placed
// by the active cell's index, as every cell before it is at its rest
// length. It fills the row, which it's clipped to while it wraps: a step
// past one end (`expectWrap`) leaves that end and comes in at the other
// rather than sliding back across.
Item {
  id: root

  required property var barConfig
  // BarsConfig.cellColors for the active state
  required property var look
  // The active cell's index in the row, or -1 when none shows
  required property int index
  required property real thickness
  required property real restLength
  // The active cell's length (twice the rest with `wideActive`)
  required property real activeLength
  required property real spacing
  property real radius: 0

  readonly property bool isVertical: barConfig.vertical
  readonly property bool boxed: barConfig.widgetBoxed
  // Whether there's anything to slide: a box, or an underline
  readonly property bool slides: boxed || barConfig.widgetStyle === "underline"
  readonly property real _along: _alongAt(index)
  readonly property real _rowLength: isVertical ? height : width

  // Slides only between cells, never in from the start when it first shows
  property bool _placed: false
  // The index shown before the latest change (set, not bound: a binding on
  // `index` may not have caught up yet when onIndexChanged reads it)
  property int _lastIndex: -1
  // A wrap announced (forward: past the last cell), until the index changes
  // or it's given up on; meanwhile the box jumps instead of sliding, and
  // `_shift` carries it out and back in
  property bool _wrapPending: false
  property bool _wrapForward: true
  property real _shift: 0

  function _alongAt(i) {
    return Math.max(0, i) * (root.restLength + root.spacing);
  }

  function expectWrap(forward) {
    if (!root._placed || !Appearance.animations)
      return;
    root._wrapForward = forward;
    root._wrapPending = true;
    wrapTimeout.restart();
  }

  onIndexChanged: {
    const from = root._lastIndex;
    root._lastIndex = root.index;
    if (root._wrapPending) {
      root._wrapPending = false;
      wrapTimeout.stop();
      if (root.index >= 0 && from >= 0 && (root._wrapForward ? root.index < from : root.index > from))
        root._wrap(root._alongAt(from), root._alongAt(root.index));
    }
    if (root.index < 0)
      root._placed = false;
    else
      Qt.callLater(() => root._placed = root.index >= 0);
  }
  Component.onCompleted: {
    _lastIndex = index;
    Qt.callLater(() => root._placed = root.index >= 0);
  }

  // From `fromAlong` out past the end it's leaving, then in from the other
  // to `toAlong`, where the box now rests (`_shift` offsetting it)
  function _wrap(fromAlong, toAlong) {
    const forward = root._wrapForward;
    const pastEnd = root._rowLength + root.spacing;
    const beforeStart = -root.activeLength - root.spacing;
    wrapAnimation.stop();
    wrapOut.from = fromAlong - toAlong;
    wrapOut.to = (forward ? pastEnd : beforeStart) - toAlong;
    wrapIn.from = (forward ? beforeStart : pastEnd) - toAlong;
    root._shift = wrapOut.from;
    wrapAnimation.start();
  }

  // An announced wrap that never came (the switch failed or went elsewhere)
  Timer {
    id: wrapTimeout
    interval: 1000
    onTriggered: root._wrapPending = false
  }

  // Speeding up on the way out, so the two halves read as one move
  SequentialAnimation {
    id: wrapAnimation
    NumberAnimation {
      id: wrapOut
      target: root
      property: "_shift"
      duration: Appearance.animFast
      easing.type: Easing.InCubic
    }
    NumberAnimation {
      id: wrapIn
      target: root
      property: "_shift"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  anchors.fill: parent
  clip: wrapAnimation.running
  visible: slides && index >= 0

  Item {
    id: box
    x: root.isVertical ? 0 : root._along + root._shift
    y: root.isVertical ? root._along + root._shift : 0
    width: root.isVertical ? root.thickness : root.activeLength
    height: root.isVertical ? root.activeLength : root.thickness

    Glide on x {
      enabled: root._placed && !root._wrapPending && !wrapAnimation.running
      duration: Appearance.animNormal
    }
    Glide on y {
      enabled: root._placed && !root._wrapPending && !wrapAnimation.running
      duration: Appearance.animNormal
    }

    Rectangle {
      anchors.fill: parent
      visible: root.boxed
      radius: root.radius
      color: root.look.fill
      border.color: root.look.stroke
      border.width: root.barConfig.widgetStyle === "outline" ? root.barConfig.outlineWidth : 0
    }

    CellUnderline {
      barConfig: root.barConfig
      color: root.look.indicator
    }
  }
}
