pragma ComponentBehavior: Bound
import QtQuick

import qs.services.ui

// What opens one OSD host (an EdgePopout) on its screen: its systems' own
// changes (OSDHost's poke: levels, tiles, cards, a message from `axiom
// message` too) and the settings page's Show button. Where it gives way
// to other popouts is its host's (EdgePopout.claimKey, PopoutManager).
QtObject {
  id: root

  // Its EdgePopout
  required property var host
  // The OSD's entry (OSDConfig.osds)
  required property var osd

  // Open (or keep open) on the target screen, or on every screen in "all"
  // mode; restarts the countdown
  function poke(force) {
    if (root.host.isOpen)
      root.host.updateDismissTimer();
    else if (force && ShellManager.showsOn(root.host.screen, root.osd.screen))
      root.host.show();
  }

  readonly property Connections _shell: Connections {
    target: ShellManager

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.poke(true);
    }
  }
}
