pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A compact row that folds something open and shut (the Wi-Fi menu's
// connection details, VPN section and More): whatever goes inside, then a
// chevron, the whole row clickable and a Tab stop (Space or Enter fold it).
// Smaller than FoldHeader, which heads a card's section. Children can read `hovered` (to turn accent with the
// chevron); buttons among them take their own clicks.
Item {
  id: root

  property bool open: false
  property bool foldable: true
  // Draws its own hover tint (off: the host tints)
  property bool tinted: true
  readonly property bool hovered: press.hovered
  default property alias content: row.data

  signal toggled

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight

  Pressable {
    id: press
    enabled: root.foldable
    tinted: root.tinted
    bleed: Widget.smallPadding
    onClicked: root.toggled()
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: chevron.left
    anchors.rightMargin: Widget.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: Widget.spacing
  }

  FoldChevron {
    id: chevron
    visible: root.foldable
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    open: root.open
    hot: root.hovered
  }
}
