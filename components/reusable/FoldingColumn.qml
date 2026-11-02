pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A column that folds open and shut: its height runs between its
// content's and nothing, clipped on the way, its content fading with it,
// and it hides once shut. It
// animates only when `open` changes, not when built. The paddings fold
// with it (FoldingCard's body, the settings sidebar's card links).
Item {
  id: root

  property bool open: true
  property real topPadding: 0
  property real bottomPadding: 0
  property alias spacing: body.spacing
  default property alias content: body.data
  // False only once fully shut, so content shown while folding can be
  // dropped then, not before
  readonly property bool shown: root._reveal > 0

  property real _reveal: root.open ? 1 : 0

  implicitHeight: (body.implicitHeight + root.topPadding + root.bottomPadding) * root._reveal
  visible: root.shown
  clip: root._reveal < 1

  Glide on _reveal {
    duration: Appearance.animNormal
  }

  ColumnLayout {
    id: body
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.topPadding
    opacity: root._reveal
  }
}
