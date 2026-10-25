pragma ComponentBehavior: Bound
import Quickshell
import qs.config
import qs.services.compositor
import qs.components.surfaces.backdrop

// The backdrop window on every screen (BackdropManager): the dim
// background full-screen surfaces ask for (BackdropRequest)
Scope {
  Variants {
    // Once the layer rules are in, as the bars it sits under
    model: CompositorManager.surfacesReady ? General.outputs : []
    delegate: ScreenBackdrop {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
