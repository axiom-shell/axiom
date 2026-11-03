pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A single choice as one control: SegmentButtons on a shared track, with
// the chosen one's accent sliding from button to button. The buttons go
// straight inside (a Repeater of them is fine); each draws only its label
// here, the row drawing the track and the accent under them.
Item {
  id: root

  default property alias content: row.data
  property alias spacing: row.spacing

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // The chosen button: reading each child's `active` makes this follow it
  readonly property Item _active: {
    for (const child of row.children) {
      if (child.visible && (child as SegmentButton)?.active)
        return child;
    }
    return null;
  }

  // Off until laid out, so the accent doesn't slide in from the start
  property bool _settled: false
  Component.onCompleted: Qt.callLater(() => root._settled = true)

  Rectangle {
    anchors.fill: parent
    radius: Widget.radius
    color: Theme.backgroundHighlight
  }

  Rectangle {
    visible: root._active !== null
    x: root._active?.x ?? 0
    y: root._active?.y ?? 0
    width: root._active?.width ?? 0
    height: root._active?.height ?? 0
    radius: Widget.radius
    color: Theme.accent

    Glide on x {
      enabled: root._settled
      duration: Appearance.animNormal
    }
    Glide on width {
      enabled: root._settled
      duration: Appearance.animNormal
    }
  }

  RowLayout {
    id: row
    // SegmentButtons check for this to draw only their labels
    objectName: "segmentTrack"
    anchors.fill: parent
    spacing: Widget.spacing / 2
  }
}
