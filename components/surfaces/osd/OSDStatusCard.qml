pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

import qs.config
import qs.components.reusable

// An OSD's card for a status (an OSDCard): its icon on the accent, a
// title, and under it what happened and a detail (OSDItems.card: an
// audio device switching, its name, what it's now used for and its
// profile; a VPN coming up, its name, Connected and its address; apps
// starting to use the camera or share the screen, their names and what
// they started; the charger plugged in, the level and the time to full;
// a Wi-Fi network joined, its name and signal; something done to a
// drive, which takes a click; the battery dropping to low or critical,
// its level and time left, on the warning colour when critical; a monitor
// connected or removed, its name and resolution; a screenshot taken, the
// picture in place of the icon, which takes a click; a message, its text
// and second line, on the warning colour for a refusal). OSDContent shows
// it as the change comes.
OSDCard {
  id: root

  // OSDItems.card's, its role translated
  property var card: ({})

  // A click on a card that takes one (card.clickable)
  signal clicked

  title: root.card.title ?? ""
  subtitle: [root.card.role ?? "", root.card.detail ?? ""].filter(part => part !== "").join(" · ")

  picture: Rectangle {
    radius: Widget.radius
    color: root.card.tone === "warning" ? Theme.warning : Theme.accent

    StyledIcon {
      anchors.centerIn: parent
      visible: !shot.visible
      text: root.card.icon ?? ""
      textSize: Appearance.fontSizeBy(8)
      textColor: Theme.background
    }

    // A picture in its place (a screenshot's), cropped to the square
    ClippingRectangle {
      id: shot
      anchors.fill: parent
      radius: Widget.radius
      color: Theme.backgroundAlt
      visible: (root.card.image ?? "") !== ""

      Image {
        anchors.fill: parent
        source: root.card.image ?? ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Decoded at its size, not the screen's
        sourceSize.width: root.pictureSize * 2
        sourceSize.height: root.pictureSize * 2
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.card.clickable === true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
