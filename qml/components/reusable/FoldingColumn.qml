pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.forms

// A column that folds open and shut: its height runs between its
// content's and nothing, clipped on the way, its content fading with it,
// and it hides once shut. It
// animates only when `open` changes, not when built. The paddings fold
// with it (FoldingCard's body, the settings sidebar's card links). Its inner
// column is a FormColumn, so the form rows in a card know their top row.
Item {
  id: root

  property bool open: true
  property real topPadding: 0
  property real bottomPadding: 0
  property alias spacing: body.spacing
  default property alias content: body.data
  // The inner column's children: a list that notifies (unlike `data`)
  readonly property alias contentChildren: body.children
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

  FormColumn {
    id: body
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.topPadding
    opacity: root._reveal
  }
}
