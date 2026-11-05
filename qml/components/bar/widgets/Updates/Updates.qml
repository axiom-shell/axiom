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
// packages, or why the check failed. Stacked: the count over the AUR's share.
// A failed check shows an error icon in place of the count, in the error
// colour, and its reason in the popout (the tooltip with the popout off).
ValueStyleWidget {
  id: root

  // [{ name, from, to }], checked by the shared UpdatesManager
  readonly property var repoPackages: UpdatesManager.repoPackages
  readonly property var aurPackages: UpdatesConfig.includeAur && UpdatesManager.hasAur ? UpdatesManager.aurPackages : []
  readonly property int count: repoPackages.length + aurPackages.length
  readonly property bool failed: UpdatesManager.error !== ""

  // News: the count rose since the last check. Unknown until a check
  // ends here (the first one only records it)
  property bool _checked: false
  Connections {
    target: UpdatesManager
    function onCheckingChanged() {
      if (!UpdatesManager.checking)
        root._checked = true;
    }
  }
  attentionLevel: root._checked ? root.count : -1

  // Shown while a check fails, so its popout can say why
  hidden: !UpdatesManager.supported || (properties.hideWhenEmpty && count === 0 && !failed)

  // Failed: the icon style, with the error icon after its own
  appearance: failed ? Object.assign({}, properties.appearance, {
    "style": "icon"
  }) : properties.appearance
  icon: !failed ? "download" : isVertical ? "download\nerror" : "download error"
  text: String(count)
  minimumText: "00"

  subtext: aurPackages.length > 0 ? I18n.tr("{0} AUR", aurPackages.length) : I18n.tr("updates")
  accentColor: failed ? Theme.error : Theme.resolveColor(count >= properties.manyThreshold ? properties.manyColor : properties.backgroundColor)

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
      UpdatesManager.upgrade();
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Updates"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }

  // With its popout off, the tooltip says why the check failed
  BarToolTip {
    widget: root
    shown: root.failed && !root.properties.popout.enabled
    text: I18n.tr("Couldn't check for updates: {0}", UpdatesManager.error)
  }
}
