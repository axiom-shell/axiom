pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods
import qs.components.reusable

// Split's icon part over a widget's background (WidgetBackground), filling
// it, in the look's split (look.split's icon and cap): joined, the
// background's shape from its start to the divider (the split's cap)
// centred in the gap to the label (`at`); a badge, a shape behind what
// the icon part holds (`part`) with badgePad round it, at least as long
// as it's thick, a circle (a pill round a lead graphic) under capsule,
// else a square rounded by the widget radius scaled to its size. In
// `color`, or its own slice of the bar's gradient (`sliceOf`).
Item {
  id: root

  required property var bar
  // Along it, the middle of the gap between the icon part and the label,
  // -1 when the widget doesn't split; what the icon part holds, in its
  // coordinates (BarWidgetHost.split)
  property real at: -1
  property rect part: Qt.rect(0, 0, 0, 0)
  // The background's start cap, and its tab's shape (BarTabs.tab) or null
  property string startCap: "round"
  property var tab: null
  property color color: "transparent"
  // Its slice of the bar's gradient along the background from `start` for
  // `length`, or null
  property var sliceOf: (start, length) => null

  readonly property var _split: bar.look.split

  anchors.fill: parent

  ColorGlide on color {}

  // Joined: the shape from its start to the divider
  ShapedBox {
    id: joined
    readonly property string _cap: root._split?.cap ?? "flat"
    readonly property real _length: root.at + BarShapes.depth(_cap, root.bar.thickness) / 2

    visible: root._split?.icon === "joined" && root.at >= 0
    anchors.fill: undefined
    width: root.bar.vertical ? root.width : _length
    height: root.bar.vertical ? _length : root.height
    bar: root.bar
    outline: ({
        "startCap": root.startCap,
        "endCap": joined._cap,
        "tab": root.tab
      })
    paint: ({
        "fill": root.color,
        "fillSlice": root.sliceOf(0, joined._length)
      })
  }

  // A badge: behind the icon part's content
  Rectangle {
    id: badge
    readonly property bool vertical: root.bar.vertical
    readonly property real thickness: root.bar.thickness
    readonly property real pad: root._split?.badgePad ?? 0
    readonly property real partAlong: vertical ? root.part.height : root.part.width
    readonly property real partAcross: vertical ? root.part.width : root.part.height
    readonly property real across: Math.min(thickness, partAcross + pad * 2)
    readonly property real along: Math.max(partAlong + pad * 2, across)
    readonly property real alongMiddle: vertical ? root.part.y + partAlong / 2 : root.part.x + partAlong / 2
    readonly property real acrossMiddle: vertical ? root.part.x + partAcross / 2 : root.part.y + partAcross / 2
    // Within the background across (a tab's reaches past the bar's thickness)
    readonly property real acrossStart: Math.max(0, Math.min((vertical ? root.width : root.height) - across, acrossMiddle - across / 2))

    visible: root._split?.icon === "badge" && root.at >= 0
    x: vertical ? acrossStart : alongMiddle - along / 2
    y: vertical ? alongMiddle - along / 2 : acrossStart
    width: vertical ? across : along
    height: vertical ? along : across
    radius: root.bar.look.shape.name === "capsule" ? across / 2 : Math.min(across / 2, root.bar.radius * across / thickness)
    color: root.color
    // Its slice of the bar's gradient
    gradient: badgeGradient.slice !== null ? badgeGradient : null

    RectSlice {
      id: badgeGradient
      slice: root.sliceOf(badge.alongMiddle - badge.along / 2, badge.along)
      vertical: badge.vertical
    }
  }
}
