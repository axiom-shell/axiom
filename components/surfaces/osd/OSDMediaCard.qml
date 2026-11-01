pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// An OSD's now playing card: the cover (CoverArt), the title and artist,
// and whether it plays or is paused. Reads MediaManager as it is;
// OSDStatusSource says when to show it.
Item {
  id: root

  implicitWidth: row.implicitWidth + Widget.spacing * 4
  implicitHeight: Widget.px(64)

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Widget.spacing * 2
    spacing: Widget.spacing * 3

    CoverArt {
      Layout.preferredWidth: Widget.px(48)
      Layout.preferredHeight: Widget.px(48)
      source: MediaManager.artSource
    }

    ColumnLayout {
      spacing: 0
      Layout.preferredWidth: Widget.px(200)

      StyledText {
        Layout.fillWidth: true
        text: MediaManager.trackTitle
        textSize: Appearance.fontSizeLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      StyledText {
        Layout.fillWidth: true
        text: MediaManager.trackArtist || MediaManager.identity
        textColor: Theme.foregroundAlt
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: text !== ""
      }
    }

    StyledIcon {
      Layout.alignment: Qt.AlignVCenter
      // What it's doing, not a button
      text: MediaManager.isPlaying ? "play_arrow" : "pause"
      textSize: Appearance.fontSizeBy(8)
    }
  }
}
