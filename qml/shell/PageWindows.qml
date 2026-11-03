pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.services.ui
import qs.components.hosts.window

// The overlay's tool pages popped out into windows of their own
// (PageWindowManager): one per page type that can be (`x-window`), made
// while it's out and in Overlay.items
Scope {
  Variants {
    model: OverlayConfig.windowTypes
    delegate: Scope {
      id: page
      required property string modelData

      LazyLoader {
        // In Overlay.items too: a reload can bring back a page taken out
        // of the config meanwhile
        active: PageWindowManager.isOpen(page.modelData) && OverlayConfig.viewEntry(page.modelData) !== null

        PageWindow {
          type: page.modelData
          screen: PageWindowManager.screenOf(page.modelData)
        }
      }
    }
  }
}
