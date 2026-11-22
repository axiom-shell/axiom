pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.components.reusable
import qs.components.hosts.overlay

// One overlay per screen Overlay.monitors puts it on (see
// General.screensFor): its panel, over the backdrop that dims the whole
// monitor under the bars. Pages only load while it's open
Scope {
  Variants {
    model: General.screensFor(OverlayConfig.screen)
    delegate: Scope {
      id: overlay
      required property ShellScreen modelData

      BackdropRequest {
        screen: overlay.modelData
        shown: panel.isOpen && !panel.steppedAside && OverlayConfig.showBackdrop
        slide: OverlayConfig.animation === "fade" ? "" : OverlayConfig.animation
        fillOpacity: OverlayConfig.backdrop
      }

      OverlayPanel {
        id: panel
        screen: overlay.modelData
      }
    }
  }
}
