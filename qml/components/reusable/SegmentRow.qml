pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A single choice as one control: SegmentButtons on a shared track
// (SegmentTrack), the chosen one's thumb sliding from button to button. The
// buttons go straight inside (a Repeater of them is fine); each draws only
// its label here, the row drawing the track and the thumb under them. The
// segments are equal and as wide as the widest label, never elided: a form
// row stacks the control under its label when it doesn't fit.
Item {
  id: root

  default property alias content: row.data
  property alias spacing: row.spacing

  implicitWidth: row.implicitWidth + track.inset * 2
  implicitHeight: row.implicitHeight + track.inset * 2
  Layout.minimumWidth: root.implicitWidth

  // The visible buttons in order, and the chosen one's place among them:
  // reading each child's `active` makes these follow it
  readonly property var _visible: Array.prototype.filter.call(row.children, child => child.visible && (child as SegmentButton) !== null)
  readonly property int _index: Math.max(0, root._visible.findIndex(child => child.active))

  SegmentTrack {
    id: track
    anchors.fill: parent
    count: root._visible.length
    index: root._index
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
