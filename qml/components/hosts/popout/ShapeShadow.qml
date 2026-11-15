pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The soft shadow of a plain rounded box, drawn from the box's shape (its
// size and corner radius) instead of a capture of the box: OutsideShadow's
// shadow, rendered once for a small box of the same radius and shadow
// size and cut in nine (the corners as they are, the edges stretched
// along their length, the middle empty: the box covers it). Growing the
// box then costs eight textured quads, no capture and no blur of a
// box-sized texture each frame. Drawn under the `box` sibling, past its
// edges. Needs the box to be at least twice the corner radius plus the
// shadow's reach across, as a page's is.
Item {
  id: root

  // The sibling the shadow is cast by (its x, y, width and height)
  required property Item box
  // The box's corner radius
  property real radius: 0
  property bool active: true
  property var look: BarStyle.look
  property alias shadowColor: master.shadowColor

  // The room the shadow takes past the box on every side
  readonly property real reach: master.reach
  readonly property real _radius: Math.ceil(root.radius)
  // The corner piece's side; the small box is two of its radius and the
  // reach across, so each edge's stretched piece is two reaches long
  readonly property real _corner: root.reach + root._radius + 1
  readonly property real _master: 2 * (root._radius + root.reach)
  readonly property real _sourceSide: root._master + 2 * root.reach
  readonly property bool _shown: root.active && root.look.shadow === true

  // The slices are drawn once, again when what they are drawn from changes
  signal rebake

  x: box.x - root.reach
  y: box.y - root.reach
  width: box.width + 2 * root.reach
  height: box.height + 2 * root.reach
  visible: root._shown

  on_ShownChanged: bakeTimer.restart()
  on_SourceSideChanged: bakeTimer.restart()
  Component.onCompleted: bakeTimer.restart()

  // Off screen (the slices render it, even unseen): the small box and
  // its shadow
  Item {
    x: -100000
    width: root._sourceSide
    height: root._sourceSide

    Rectangle {
      id: small
      x: root.reach
      y: root.reach
      width: root._master
      height: root._master
      radius: root._radius
      color: Style.surfacePage
    }

    OutsideShadow {
      id: master
      target: small
      active: root._shown
      hideTarget: true
      look: root.look
    }
  }

  Timer {
    id: bakeTimer
    interval: Appearance.animFast
    onTriggered: root.rebake()
  }

  // Corners and edges, row by row; the middle (4) is skipped
  Repeater {
    model: 9

    ShaderEffectSource {
      id: slice
      required property int index
      readonly property int col: slice.index % 3
      readonly property int row: Math.floor(slice.index / 3)
      readonly property real stretch: 2 * root.reach

      // Where in the small shadow, and where over the box's
      function _src(i) {
        return i === 0 ? 0 : (i === 1 ? root._corner : root._sourceSide - root._corner);
      }
      function _len(i) {
        return i === 1 ? slice.stretch : root._corner;
      }
      function _dst(i, total) {
        return i === 0 ? 0 : (i === 1 ? root._corner : total - root._corner);
      }
      function _dlen(i, total) {
        return i === 1 ? Math.max(0, total - 2 * root._corner) : root._corner;
      }

      visible: slice.index !== 4
      sourceItem: slice.index !== 4 && root._shown ? master : null
      sourceRect: Qt.rect(slice._src(slice.col), slice._src(slice.row), slice._len(slice.col), slice._len(slice.row))
      live: false
      smooth: false
      x: slice._dst(slice.col, root.width)
      y: slice._dst(slice.row, root.height)
      width: slice._dlen(slice.col, root.width)
      height: slice._dlen(slice.row, root.height)
      textureSize: Qt.size(slice._len(slice.col) * Screen.devicePixelRatio, slice._len(slice.row) * Screen.devicePixelRatio)

      Connections {
        target: root
        function onRebake() {
          slice.scheduleUpdate();
        }
      }
    }
  }
}
