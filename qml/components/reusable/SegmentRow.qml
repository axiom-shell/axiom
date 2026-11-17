pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config

// A single choice as one control: SegmentButtons on a shared track
// (SegmentTrack), the chosen one's thumb sliding from button to button. The
// buttons go straight inside (a Repeater of them is fine); each draws only
// its label here, the row drawing the track and the thumb under them. The
// segments are equal and as wide as the widest label, never elided: a form
// row stacks the control under its label when it doesn't fit. The row is one
// Tab stop with the focus ring on its track: Left and Right step to the
// neighbouring available button, Space flips two; a pick is that button's
// `clicked`, as a click on it.
Item {
  id: root

  default property alias content: row.data
  property alias spacing: row.spacing

  implicitWidth: row.implicitWidth + track.inset * 2
  implicitHeight: Widget.slimHeight
  Layout.minimumWidth: root.implicitWidth

  // The visible buttons in order, and the chosen one's place among them:
  // reading each child's `active` makes these follow it
  readonly property var _visible: Array.prototype.filter.call(row.children, child => child.visible && (child as SegmentButton) !== null)
  readonly property int _index: Math.max(0, root._visible.findIndex(child => child.active))

  activeFocusOnTab: true
  Keys.onLeftPressed: root._step(-1)
  Keys.onRightPressed: root._step(1)
  Keys.onSpacePressed: root._flip()

  // The buttons that can be chosen, in order
  function _pickable() {
    return root._visible.filter(child => child.available);
  }

  // Two buttons: picks the other one
  function _flip() {
    const other = root._visible.length === 2 ? root._visible.find(child => !child.active && child.available) : undefined;
    if (other)
      other.clicked();
  }

  function _step(by) {
    const pickable = root._pickable();
    const at = pickable.findIndex(child => child.active);
    const to = Math.max(0, Math.min(pickable.length - 1, at + by));
    if (pickable.length > 0 && to !== at)
      pickable[to].clicked();
  }

  SegmentTrack {
    id: track
    anchors.fill: parent
    count: root._visible.length
    index: root._index

    FocusRing {
      shown: root.activeFocus
    }
  }

  RowLayout {
    id: row
    // SegmentButtons check for this to draw only their labels
    objectName: "segmentTrack"
    anchors.fill: parent
    anchors.margins: track.inset
    uniformCellSizes: true
    spacing: 0
  }
}
