pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// An OSD's card for an audio device switch (an OSDCard): the device's
// icon on the accent, its name, and under it what it's now used for and
// its profile. `tile` is its status's (OSDItems.tile of audio or
// microphone); OSDContent shows it as the device switches.
OSDCard {
  id: root

  property var tile: ({})
  // Output, Input, or Output and input (both switched to it)
  property string role: ""

  title: root.tile.name ?? ""
  subtitle: [root.role, root.tile.detail ?? ""].filter(part => part !== "").join(" · ")

  picture: Rectangle {
    radius: Widget.radius
    color: Theme.accent

    StyledIcon {
      anchors.centerIn: parent
      text: root.tile.icon ?? ""
      textSize: Appearance.fontSizeBy(8)
      textColor: Theme.background
    }
  }
}
