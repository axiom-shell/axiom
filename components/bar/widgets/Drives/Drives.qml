pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.system
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The removable drives plugged in (DrivesManager): an icon and their
// count, hidden with none (hideWhenEmpty). Hovering opens the Drives
// popout; left click opens the first drive (mounting it first), middle
// click ejects them all. Stacked: the count over how many are mounted.
ValueStyleWidget {
  id: root

  readonly property int count: DrivesManager.count
  readonly property int mounted: DrivesManager.mountedDrives.length

  hidden: properties.hideWhenEmpty && count === 0
  icon: "usb"
  text: String(count)
  minimumText: "0"
  labelShown: properties.showCount && count > 0
  subtext: I18n.tr("{0} mounted", mounted)
  accentColor: Theme.resolveColor(mounted > 0 ? properties.mountedColor : properties.idleColor)

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      DrivesManager.ejectAll();
    else
      DrivesManager.open(DrivesManager.drives[0] ?? null);
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Drives"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }
}
