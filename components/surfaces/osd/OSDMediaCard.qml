pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import qs.config
import qs.services.system
import qs.components.reusable

// An OSD's now playing card: the cover (the player's note without one),
// the title and artist, and whether it plays or is paused. Reads MediaManager as it
// is; OSDStatusSource says when to show it.
Item {
  id: root

  readonly property string artSource: MediaManager.artDownloaded && MediaManager.artVersion >= 0 ? "file://" + MediaManager.artFilePath : ""

  implicitWidth: row.implicitWidth + Widget.spacing * 4
  implicitHeight: Widget.px(64)

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Widget.spacing * 2
    spacing: Widget.spacing * 3

    ClippingRectangle {
      Layout.preferredWidth: Widget.px(48)
      Layout.preferredHeight: Widget.px(48)
      radius: Widget.radius
      color: Theme.backgroundAlt

      StyledIcon {
        anchors.centerIn: parent
        text: "music_note"
        textSize: Appearance.fontSizeBy(6)
        color: Theme.foregroundInactive
        visible: root.artSource === ""
      }

      // A new cover fades in over the old once it has loaded
      CrossFade {
        anchors.fill: parent
        value: root.artSource
        delegate: Image {
          required property var value
          readonly property bool ready: status !== Image.Loading
          source: value
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: status === Image.Ready
        }
      }
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
