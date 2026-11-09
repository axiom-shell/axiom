pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.methods

// The active workspace's box (or underline) in a bar switcher's row of
// cells, drawn once over their boxes and under their labels (the row draws
// its WorkspaceCells in two layers around it), sliding from cell to cell as
// the active workspace changes, where the cells would each recolour. Placed
// by the active cell's index, as every cell before it is at its rest
// length (WorkspaceCells.startOf), and as long as that cell widened. It
// fills the row, which clips it: a step
// past one end (`expectWrap`) leaves that end and comes in at the other
// rather than sliding back across. As a segment of the bar's run (the
// widget's Background off) it takes the active cell's shape (`shape`), and
// an Auto color its slice of the bar's gradient (`slice`).
Item {
  id: root

  required property var barConfig
  // BarsConfig.cellColors for the active state
  required property var look
  // The active cell's index in the row, or -1 when none shows
  required property int index
  required property real thickness
  // Each cell's length at rest
  required property var lengths
  // What the active cell grows by (`wideActive`: one normal cell's length)
  required property real extra
  // The active cell's length
  readonly property real activeLength: (lengths[index] ?? 0) + extra
  required property real spacing
  property real radius: 0
  // `solidBoxes`: a filled box on every bar style (`look` is the solid one)
  property bool solid: false
  // The active cell's shape as a segment of the bar's run
  // (BarShapes.cellShape), or null
  property var shape: null
  // Its slice of the bar's gradient where it rests, for the part of its
  // box `look.gradient` names, or null
  property var slice: null

  readonly property bool isVertical: barConfig.vertical
  readonly property bool boxed: barConfig.widgetBoxed || solid
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
    return WorkspaceCells.startOf(root.lengths, root.spacing, Math.max(0, i));
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
        root._wrap(root._alongAt(from), root._alongAt(root.index), (root.lengths[from] ?? 0) + root.extra);
    }
    if (root.index < 0)
      root._placed = false;
    else
      Qt.callLater(root._place);
  }
  Component.onCompleted: {
    _lastIndex = index;
    Qt.callLater(root._place);
  }
  // Called later, as a method: the call is dropped if the indicator is gone
  // by then (a bar rebuilt), as a closure's isn't
  function _place() {
    root._placed = root.index >= 0;
  }

  // From `fromAlong` out past the end it's leaving, then in from the other
  // to `toAlong`, where the box now rests (`_shift` offsetting it). Before
  // the start means past the longer of the two cells: the box's length
  // glides from the one it left (`fromLength`) meanwhile
  function _wrap(fromAlong, toAlong, fromLength) {
    const forward = root._wrapForward;
    const pastEnd = root._rowLength + root.spacing;
    const beforeStart = -Math.max(root.activeLength, fromLength) - root.spacing;
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
    // Cells differ in length (a text label, a row of icons)
    Glide on width {
      enabled: root._placed
      duration: Appearance.animNormal
    }
    Glide on height {
      enabled: root._placed
      duration: Appearance.animNormal
    }

    CellBox {
      visible: root.boxed
      barConfig: root.barConfig
      radius: root.radius
      shape: root.shape
      fillColor: root.look.fill
      strokeColor: root.look.stroke
      fillSlice: root.look.gradient?.part === "fill" ? root.slice : null
      strokeSlice: root.look.gradient?.part === "stroke" ? root.slice : null
      animated: true
    }

    CellUnderline {
      barConfig: root.barConfig
      color: root.look.indicator
    }
  }
}
