pragma ComponentBehavior: Bound
import Quickshell

import qs.components.surfaces.screenshot
import qs.services.apps
import qs.config

// The screenshot picker while ScreenshotManager is picking: on every screen
// for a region or window (each frozen, so nothing moves), only on the
// captured screen for an immediate `screen` shot
Scope {
  Variants {
    model: General.outputs

    LazyLoader {
      id: loader
      required property ShellScreen modelData
      active: ScreenshotManager.picking && (ScreenshotManager.request?.kind !== "screen" || ScreenshotManager.request?.screen === modelData.name)

      ScreenshotPickerWindow {
        screen: loader.modelData
      }
    }
  }
}
