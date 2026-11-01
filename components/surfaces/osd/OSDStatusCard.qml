pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// An OSD's card for a status (an OSDCard): its icon on the accent, a
// title, and under it what happened and a detail (OSDItems.card: an
// audio device switching, its name, what it's now used for and its
// profile; a VPN coming up, its name, Connected and its address; apps
// starting to use the camera or share the screen, their names and what
// they started; the charger plugged in, the level and the time to full;
// a Wi-Fi network joined, its name and signal). OSDContent shows it as
// the change comes.
OSDCard {
  id: root

  // OSDItems.card's, its role translated
  property var card: ({})

  title: root.card.title ?? ""
  subtitle: [root.card.role ?? "", root.card.detail ?? ""].filter(part => part !== "").join(" · ")

  picture: Rectangle {
    radius: Widget.radius
    color: Theme.accent

    StyledIcon {
      anchors.centerIn: parent
      text: root.card.icon ?? ""
      textSize: Appearance.fontSizeBy(8)
      textColor: Theme.background
    }
  }
}
