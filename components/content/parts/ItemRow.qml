pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.components.reusable

// One entry in a module's list (clipboard clips, calculator answers,
// recordings): an icon or a rounded thumbnail, a title and a muted
// subtitle, a muted `detail` on the right (a value), and buttons after it
// (children), faint until the row is hovered so showing them moves
// nothing. Clicking the row `activated`s it, unless it isn't `clickable`.
Rectangle {
  id: root

  property string icon: ""
  // An image url: a thumbnail in place of the icon
  property string image: ""
  property string title: ""
  property string subtitle: ""
  // Title lines before it elides
  property int titleLines: 1
  property string titleFamily: Appearance.fontFamily
  // Marked (e.g. pinned): the icon in the accent
  property bool marked: false
  property color iconColor: root.marked ? Theme.accent : Theme.foregroundAlt
  property string detail: ""
  property bool clickable: true
  readonly property bool hovered: rowHover.hovered
  default property alias actions: actionRow.data

  signal activated

  Layout.fillWidth: true
  implicitHeight: Math.max(content.implicitHeight, Appearance.fontSize * 2) + Widget.spacing * 2
  radius: Widget.radius
  color: Qt.alpha(Theme.backgroundHighlight, rowHover.hovered ? 0.5 : 0)

  ColorGlide on color {}

  HoverHandler {
    id: rowHover
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Widget.spacing
    anchors.rightMargin: Widget.spacing / 2
    spacing: Widget.spacing

    StyledIcon {
      visible: root.image === "" && root.icon !== ""
      Layout.preferredWidth: Appearance.fontSize * 1.5
      horizontalAlignment: Text.AlignHCenter
      text: root.icon
      textSize: Appearance.fontSizeBy(2)
      textColor: root.iconColor
    }

    ClippingRectangle {
      visible: root.image !== ""
      Layout.preferredWidth: Appearance.fontSize * 3
      Layout.preferredHeight: Appearance.fontSize * 2
      radius: Widget.radius / 2
      color: Theme.backgroundAlt

      Image {
        anchors.fill: parent
        source: root.image
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: Appearance.fontSize * 6
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledText {
        Layout.fillWidth: true
        text: root.title
        textFamily: root.titleFamily
        textSize: Appearance.fontSizeBy(-1)
        elide: Text.ElideRight
        wrapMode: root.titleLines > 1 ? Text.Wrap : Text.NoWrap
        maximumLineCount: root.titleLines
      }
      StyledText {
        visible: root.subtitle !== ""
        Layout.fillWidth: true
        text: root.subtitle
        textSize: Appearance.fontSizeBy(-3)
        textColor: Theme.foregroundAlt
        elide: Text.ElideRight
      }
    }

    StyledText {
      visible: root.detail !== ""
      text: root.detail
      textSize: Appearance.fontSizeBy(-1)
      textColor: Theme.foregroundAlt
    }

    RowLayout {
      id: actionRow
      spacing: 0
      opacity: rowHover.hovered ? 1 : 0
      enabled: rowHover.hovered

      Glide on opacity {}
    }
  }
}
