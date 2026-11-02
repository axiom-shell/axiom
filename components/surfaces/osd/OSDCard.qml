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
  // The text's width: its own, the longer line's, between a least (a
  // short title doesn't make a stub of a card) and a most (a long one
  // ends in "…"). A Text's implicit width ignores its eliding, so this
  // reads the lines' own widths
  readonly property int minTextWidth: Widget.px(160)
  readonly property int maxTextWidth: Widget.px(360)
  readonly property int textWidth: Math.round(Math.max(root.minTextWidth, Math.min(root.maxTextWidth, Math.max(titleText.implicitWidth, subtitleText.visible ? subtitleText.implicitWidth : 0))))
  // The empty margin round what shows across `vertical` edges' depth
  // (its width) or else its height (round the picture): a host spacing
  // it by what shows reads it
  function inset(vertical) {
    return vertical ? Widget.spacing * 2 : (root.implicitHeight - root.pictureSize) / 2;
  }
  // Its width with the text at its most: the room a host keeps for it
  readonly property real maxWidth: root.implicitWidth - root.textWidth + root.maxTextWidth

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
        id: titleText
        Layout.fillWidth: true
        text: root.title
        textSize: Appearance.fontSizeLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      StyledText {
        id: subtitleText
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
