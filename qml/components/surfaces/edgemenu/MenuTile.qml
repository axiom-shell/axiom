pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.hosts.popout

// One card's tile in a tiled menu (`background: none`, MenuTiles), under
// the card in EdgeMenuBody: the menu's fill at the card's shape, with the
// shadow the menu's box would cast. While the blur window backs the menu
// (`tiles.backed`) it draws the tile there instead (a BlurShape), which
// blurs behind it and casts its shadow; otherwise it fills itself, its
// shadow kept outside it (OutsideShadow). Drawn out of the body's
// scrolling view, so the shadow isn't cut at its edge: placed from the
// card's rect in the grid (`card`), scrolled by `scroll` and cut to
// `viewSize` (MenuTiles.shown), its growing eased as the card's slot is.
Item {
  id: root

  // The card in the grid ({ x, y, width, height }), or null for none
  required property var card
  // The host's drawing (EdgeMenuBody.tiles)
  required property var tiles
  property point scroll: Qt.point(0, 0)
  property size viewSize: Qt.size(0, 0)
  property color fillColor: Theme.background
  property real radius: Widget.radius
  // Eases its growing (after it's first laid out)
  property bool animate: false

  // The card's place, its growing eased (as ModuleGrid's slots)
  property real _gy: root.card?.y ?? 0
  property real _gh: root.card?.height ?? 0
  Glide on _gy {
    enabled: root.animate
    duration: Appearance.animNormal
  }
  Glide on _gh {
    enabled: root.animate
    duration: Appearance.animNormal
  }
  readonly property var _shown: root.card ? MenuTiles.shown([
    {
      "x": root.card.x,
      "y": root._gy,
      "width": root.card.width,
      "height": root._gh
    }
  ], root.scroll, root.viewSize)[0] : null
  readonly property bool backed: root.tiles?.backed ?? false
  readonly property var _origin: root.tiles?.origin ?? null

  visible: root._shown !== null
  x: root._shown?.x ?? 0
  y: root._shown?.y ?? 0
  width: root._shown?.width ?? 0
  height: root._shown?.height ?? 0

  // Its shadow, filled itself
  OutsideShadow {
    target: shape
    hideTarget: true
    active: !root.backed && root.visible
    look: root.tiles?.look ?? BarStyle.look
  }
  Rectangle {
    id: shape
    anchors.fill: parent
    radius: root.radius
    color: "black"
  }

  Rectangle {
    id: fill
    anchors.fill: parent
    radius: root.radius
    color: root.backed ? "transparent" : root.tiles?.opaque ? root.fillColor : Appearance.fill(root.fillColor)
  }

  // ...or by the blur window, at its place on the screen
  BlurShape {
    source: fill
    kind: "rect"
    screen: root.tiles?.screen ?? ""
    x: (root._origin?.x ?? 0) + root.x
    y: (root._origin?.y ?? 0) + root.y
    color: Qt.alpha(root.fillColor, root.tiles?.opacity ?? 1)
    shadow: root.tiles?.look ?? null
    overlayLayer: root.tiles?.overlayLayer ?? false
    shown: root.backed && root.visible && root._origin !== null
    clipRect: root.tiles?.clip ?? null
  }
}
