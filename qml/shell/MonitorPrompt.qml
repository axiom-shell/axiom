pragma ComponentBehavior: Bound
import Quickshell
import qs.config

import qs.components.surfaces.monitors

// The Monitors page's prompts, on every screen: "keep this layout?" after
// Apply (not in the overlay, whose screen may be the one that changed), and
// each screen's name while identifying
Scope {
  Variants {
    model: General.outputs
    delegate: MonitorPromptWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
