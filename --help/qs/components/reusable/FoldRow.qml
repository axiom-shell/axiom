pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A compact row that folds something open and shut (the Wi-Fi menu's
// connection details, VPN section and More): whatever goes inside, then a
// chevron, the whole row clickable. Smaller than FoldHeader, which heads
// a card's section. Children can read `hovered` (to turn accent with the
// chevron); buttons among them take their own clicks.
Item {
  id: root

  property bool open: false
  property bool foldable: true
  readonly property bool hovered: area.containsMouse
  default property alias content: row.data

  signal toggled

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.foldable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
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

  StyledIcon {
    id: chevron
    visible: root.foldable
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: "expand_more"
    textColor: root.hovered ? Theme.accent : Theme.foregroundAlt
    rotation: root.open ? 0 : -90

    Glide on rotation {}
  }
}
