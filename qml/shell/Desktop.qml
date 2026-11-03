pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.services.compositor
import qs.components.surfaces.desktop

// The desktop's modules on every screen whose layout has any
// (DesktopConfig.layoutFor), once the layer rules are in
Scope {
  Variants {
    model: CompositorManager.surfacesReady ? General.outputs.filter(screen => (DesktopConfig.layoutFor(screen.name)?.modules.length ?? 0) > 0) : []
    delegate: DesktopWindow {
      id: desktop
      required property ShellScreen modelData
      screen: desktop.modelData
      layout: DesktopConfig.layoutFor(desktop.modelData?.name ?? "")
    }
  }
}
