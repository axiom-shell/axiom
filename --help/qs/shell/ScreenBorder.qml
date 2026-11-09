pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.services.compositor
import qs.components.surfaces.border

// The screen border on every screen (Appearance.screenBorder)
Scope {
  Variants {
    // Once the layer rules are in, so the bars land inside it
    model: Appearance.screenBorder && CompositorManager.surfacesReady ? General.outputs : []
    delegate: RoundedBorders {
      id: border
      required property ShellScreen modelData
      screen: border.modelData
    }
  }
}
