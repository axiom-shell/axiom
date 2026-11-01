pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// The frame of an OSD's cards (OSDMediaCard, OSDStatusCard): a square
// picture on the left (`picture`), a title and a faint line under it,
// and optionally an icon at the end saying what it's doing.
Item {
  id: root

  // The square on the left (a cover, a device's icon)
  property Component picture
  property string title: ""
  property string subtitle: ""
  // An icon at the end, or "" for none
  property string status: ""

  readonly property int pictureSize: Widget.px(48)
  // The text's width: room for a long device name or track title
  readonly property int textWidth: Widget.px(300)

  implicitWidth: row.implicitWidth + Widget.spacing * 4
  implicitHeight: Widget.px(64)

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Widget.spacing * 2
    spacing: Widget.spacing * 3

    Loader {
      Layout.preferredWidth: root.pictureSize
      Layout.preferredHeight: root.pictureSize
      sourceComponent: root.picture
    }

    ColumnLayout {
      spacing: 0
      Layout.preferredWidth: root.textWidth

      StyledText {
        Layout.fillWidth: true
        text: root.title
        textSize: Appearance.fontSizeLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      StyledText {
        Layout.fillWidth: true
        text: root.subtitle
        textColor: Theme.foregroundAlt
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: text !== ""
      }
    }

    StyledIcon {
      Layout.alignment: Qt.AlignVCenter
      visible: root.status !== ""
      text: root.status
      textSize: Appearance.fontSizeBy(8)
    }
  }
}
