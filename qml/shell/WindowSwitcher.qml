pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.components.hosts.popout
import qs.components.surfaces.switcher

// The window switcher (WindowSwitcherManager): a box of window tiles on
// the monitor that was focused when it opened, in an EdgePopout placed as
// the launcher is (WindowSwitcherConfig): detached, held `distance` across
// the free screen from its edge, sliding or fading in; else growing out
// of the border or bar there. It takes no keyboard: the compositor
// holds the keys (Hyprland's submap), or the daemon does where the
// compositor can't tell their release (no supports.switcherRelease), so
// no window gets them until one is picked.
Scope {
  Variants {
    model: General.screensFor({
      "mode": "focused"
    })

    delegate: Scope {
      id: screenScope
      required property ShellScreen modelData

      // Its screen's name ("" once the screen is gone, before the delegate goes)
      readonly property string screenName: screenScope.modelData?.name ?? ""
      readonly property bool wanted: WindowSwitcherManager.shown && screenScope.screenName === WindowSwitcherManager.screenName

      onWantedChanged: screenScope.sync()
      // A screen added while it's open on it
      Component.onCompleted: screenScope.sync()

      function sync() {
        if (screenScope.wanted)
          popout.show();
        else
          popout.hide();
      }

      // Wraps to another row or column past 80% of the screen
      Component {
        id: strip
        SwitcherStrip {
          maxWidth: screenScope.modelData.width * 0.8
          maxHeight: screenScope.modelData.height * 0.8
        }
      }

      EdgePopout {
        id: popout
        screen: screenScope.modelData
        edge: WindowSwitcherConfig.edge
        position: WindowSwitcherConfig.position
        held: WindowSwitcherConfig.detached
        distance: WindowSwitcherConfig.distance
        fade: WindowSwitcherConfig.fade
        triggerEnabled: false
        // Closes when the switcher does, not on hover loss
        autoDismiss: false
        // Closes whatever it covers (PopoutManager), ranked as the launcher
        claimKey: "switcher:" + screenScope.screenName
        claimKind: "launcher"
        content: strip
      }
    }
  }
}
