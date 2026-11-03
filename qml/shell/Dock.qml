pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.surfaces.dock

// The docks (DockConfig), one per enabled entry, each on the screens its
// `monitors` puts it on: on the focused monitor only, it's rebuilt on the
// one focus moves to. Keyed by id, so editing a dock's settings updates it
// in place instead of rebuilding it. The settings card's Show is a
// preview copy over the overlay (DockManager.preview), on the screen it
// would show on.
Scope {
  Variants {
    // Once the layer rules are in (CompositorManager.surfacesReady)
    model: CompositorManager.surfacesReady ? DockConfig.shownIds : []

    delegate: Scope {
      id: entry
      required property string modelData
      readonly property var _found: DockConfig.dockById(modelData)
      // As last found, so its windows are never handed null as it's removed
      property LastFound _held: LastFound {
        source: entry._found
      }
      readonly property var dock: entry._held.value

      Variants {
        model: entry._found ? DockConfig.screensOf(entry._found).filter(screen => ShellManager.showsOn(screen, entry._found.screen)) : []

        delegate: DockWindow {
          required property ShellScreen modelData
          screen: modelData
          dock: entry.dock
        }
      }
    }
  }

  LazyLoader {
    id: previewLoader
    readonly property var screen: General.outputs.find(screen => screen.name === DockManager.previewScreen) ?? null
    active: CompositorManager.surfacesReady && DockManager.previewActive && previewLoader.screen !== null

    DockWindow {
      screen: previewLoader.screen
      dock: DockManager.previewDock
      preview: true
    }
  }
}
