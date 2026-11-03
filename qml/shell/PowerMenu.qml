pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.components.surfaces.powermenu

// A power menu per screen PowerMenu.monitors builds it on; the target
// screen's opens (on every one of them in "all")
Scope {
  Variants {
    model: General.screensFor(PowerMenuConfig.screen)
    delegate: PowerMenuWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
