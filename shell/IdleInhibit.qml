pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.session

// Keeps the session awake while IdleInhibitManager.enabled (caffeine). The
// Wayland idle inhibitor needs a mapped surface, so while it's on this maps
// a 1 px transparent, click-through window on the primary monitor to hold
// it, whatever bars or widgets are configured.
Scope {
  LazyLoader {
    active: IdleInhibitManager.enabled && General.outputs.length > 0

    PanelWindow {
      id: holder

      screen: General.screensNamed(General.primaryMonitor)[0]
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "axiom-idle-inhibit"
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      implicitWidth: 1
      implicitHeight: 1
      anchors {
        top: true
        left: true
      }
      mask: Region {}

      IdleInhibitor {
        window: holder
        enabled: true
      }
    }
  }
}
