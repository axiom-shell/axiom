pragma ComponentBehavior: Bound
import Quickshell
import qs.config

import qs.components.surfaces.prompt

// The shared prompt (PromptManager's shown request: polkit, Bluetooth
// pairing), on every screen: each dims, and the one focused when the
// request came to the front shows the card
Scope {
  Variants {
    model: General.outputs
    delegate: PromptWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
