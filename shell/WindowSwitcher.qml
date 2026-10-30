pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.hosts.popout
import qs.components.surfaces.switcher

// The window switcher (WindowSwitcherManager): a box of window tiles on
// the monitor that was focused when it opened, placed as the launcher is
// (WindowSwitcherConfig): detached, a FloatingPopout `distance` across the
// free screen from its edge (FloatPlacement); else an EdgePopout growing
// out of the border or bar there. It takes no keyboard: the compositor
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

      readonly property bool wanted: WindowSwitcherManager.shown && screenScope.modelData.name === WindowSwitcherManager.screenName
      // The host in use: only it is created
      readonly property var host: WindowSwitcherConfig.detached ? floatingLoader.item : edgeLoader.item

      onWantedChanged: screenScope.sync()
      onHostChanged: screenScope.sync()

      function sync() {
        if (screenScope.wanted)
          screenScope.host?.show();
        else
          screenScope.host?.hide();
      }

      // Wraps to more rows past 80% of the screen's width, or 40% on a side
      // edge, where a long row would run across the screen from it
      Component {
        id: strip
        SwitcherStrip {
          maxWidth: screenScope.modelData.width * (WindowSwitcherConfig.edge === ScreenEdge.Left || WindowSwitcherConfig.edge === ScreenEdge.Right ? 0.4 : 0.8)
        }
      }

      LazyLoader {
        id: floatingLoader
        active: WindowSwitcherConfig.detached

        FloatingPopout {
          id: floating

          // Its centre at `position` along the edge, `distance` across
          readonly property FloatPlacement place: FloatPlacement {
            screen: screenScope.modelData
            edge: WindowSwitcherConfig.edge
            position: WindowSwitcherConfig.position
            distance: WindowSwitcherConfig.distance
          }

          screen: screenScope.modelData
          xFraction: floating.place.xFraction
          xAlign: floating.place.xAlign
          yFraction: floating.place.yFraction
          yAlign: floating.place.yAlign
          leftMargin: floating.place.leftMargin
          topMargin: floating.place.topMargin
          rightMargin: floating.place.rightMargin
          bottomMargin: floating.place.bottomMargin
          layerNamespace: "axiom-switcher"
          // Closes when the switcher does, not on hover loss
          autoDismiss: false
          // Closes whatever it covers (PopoutManager), ranked as the launcher
          claimKey: "switcher:" + screenScope.modelData.name
          content: strip
        }
      }

      LazyLoader {
        id: edgeLoader
        active: !WindowSwitcherConfig.detached

        EdgePopout {
          screen: screenScope.modelData
          edge: WindowSwitcherConfig.edge
          position: WindowSwitcherConfig.position
          triggerEnabled: false
          autoDismiss: false
          claimKey: "switcher:" + screenScope.modelData.name
          claimKind: "launcher"
          content: strip
        }
      }
    }
  }
}
