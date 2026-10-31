pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Pending package updates from UpdatesManager: repo packages the way this
// distribution checks them (`checkupdates` on Arch, `dnf check-update` on
// Fedora; hidden on one UpdatesManager can't check), plus AUR packages via
// paru/yay when enabled on Arch (UpdatesConfig). Left click opens a
// terminal to upgrade, right click checks again now; hovering lists the
// packages. Stacked: the count over the AUR's share.
ValueStyleWidget {
  id: root

  // [{ name, from, to }], checked by the shared UpdatesManager
  readonly property var repoPackages: UpdatesManager.repoPackages
  readonly property var aurPackages: UpdatesConfig.includeAur && UpdatesManager.hasAur ? UpdatesManager.aurPackages : []
  readonly property int count: repoPackages.length + aurPackages.length

  hidden: !UpdatesManager.supported || (properties.hideWhenEmpty && count === 0)
  readonly property string upgradeCommand: UpdatesConfig.upgradeCommand || UpdatesManager.upgradeCommand(UpdatesConfig.activeAurHelper)

  icon: "download"
  text: String(count)
  minimumText: "00"

  subtext: aurPackages.length > 0 ? I18n.tr("{0} AUR", aurPackages.length) : I18n.tr("updates")
  accentColor: Theme.resolveColor(count >= properties.manyThreshold ? properties.manyColor : properties.backgroundColor)

  // Re-acquiring replaces the old request
  readonly property var updatesRequest: ({
      "interval": root.properties.interval,
      "aurHelper": UpdatesConfig.activeAurHelper
    })
  onUpdatesRequestChanged: UpdatesManager.acquire(root, updatesRequest)
  Component.onCompleted: UpdatesManager.acquire(root, updatesRequest)
  Component.onDestruction: UpdatesManager.release(root)

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => {
    if (button === Qt.RightButton)
      UpdatesManager.refresh();
    else
      UpdatesManager.upgrade(root.upgradeCommand, UpdatesConfig.terminal);
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Updates"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
    extraData: ({
        "repoPackages": root.repoPackages,
        "aurPackages": root.aurPackages
      })
  }
}
