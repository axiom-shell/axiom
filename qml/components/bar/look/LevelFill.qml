pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

import qs.config
import qs.components.reusable

// A widget's level (its backgroundLevel, 0-1: the pill display style) over
// its background (WidgetBackground), filling it: the background's own
// shape (in a merged run, the one the widget has alone: `startCap`,
// `endCap`) in `color`, seen from where the bar's run starts (up a
// vertical bar, from the bottom) through a window ending on a rounded edge
// (a capsule's, else the bar's radius). Clipped rather than a shape of its
// own, so a low level stays inside the background's ends instead of
// squeezing its corners square. The window overhangs the start (and, full,
// the far end unless that's flat), so only its leading edge rounds and
// never by less than its radius.
Item {
  id: root

  required property var bar
  // 0-1, -1 for none
  property real level: -1
  property color color: "transparent"
  property string startCap: "round"
  property string endCap: "round"
  property bool seamStart: false
  property bool seamEnd: false
  // A tab's shape (BarTabs.tab), or null
  property var tab: null

  anchors.fill: parent

  ColorGlide on color {}

  ClippingRectangle {
    id: window
    readonly property bool vertical: root.bar.vertical
    readonly property real share: Math.max(0, Math.min(1, root.level))
    readonly property real across: vertical ? root.width : root.height
    // The cap at the far end, where a full level ends
    readonly property string farCap: vertical ? root.startCap : root.endCap
    readonly property real room: vertical ? root.height : root.width
    readonly property real shown: room * share + (share >= 1 && farCap !== "flat" ? across : 0)

    visible: root.level >= 0 && window.share > 0
    color: "transparent"
    // A Rectangle keeps it to half the thickness, which the window never
    // drops below
    radius: root.bar.look.shape.name === "capsule" ? across / 2 : root.bar.radius
    x: vertical ? 0 : -across
    y: vertical ? root.height - shown : 0
    width: vertical ? root.width : shown + across
    height: vertical ? shown + across : root.height

    Glide on width {
      duration: Appearance.animNormal
    }
    Glide on height {
      duration: Appearance.animNormal
    }
    Glide on y {
      duration: Appearance.animNormal
    }

    ShapedBox {
      anchors.fill: undefined
      x: -window.x
      y: -window.y
      width: root.width
      height: root.height
      bar: root.bar
      outline: ({
          "startCap": root.startCap,
          "endCap": root.endCap,
          "seamStart": root.seamStart,
          "seamEnd": root.seamEnd,
          "tab": root.tab
        })
      paint: ({
          "fill": root.color
        })
    }
  }
}
