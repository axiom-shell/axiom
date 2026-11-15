pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods
import qs.config

// The track and sliding thumb of SegmentRow and StyledToggle (private to
// them): equal segments, `count` of them, the thumb under segment `index`.
// The hosts lay their labels over it and draw no track of their own. The
// track is the root Surface, so a host may set its `radius`; the thumb
// follows concentrically.
Surface {
  id: root

  // -- Public API --
  property int count: 1
  property int index: 0

  // -- Implementation --
  // the thumb's inset in the track
  readonly property real inset: Widget.px(2)
  readonly property real _segment: (root.width - root.inset * 2) / Math.max(1, root.count)
  // Off until laid out, so the thumb doesn't slide in from the start
  property bool _settled: false

  tone: Style.segmentTrackTone
  outlined: Style.segmentTrackTone === "sunken"
  radius: Style.radiusInner

  Component.onCompleted: Qt.callLater(() => root._settled = true)

  Surface {
    id: thumb

    x: Math.round(root.inset + root.index * root._segment)
    y: root.inset
    width: Math.round(root._segment)
    height: root.height - root.inset * 2
    tone: Style.segmentThumbTone
    outlined: Style.segmentThumbTone === "surface"
    radius: Style.concentric(root.radius, root.inset)

    Glide on x {
      enabled: root._settled
      duration: Appearance.animNormal
    }
  }
}
