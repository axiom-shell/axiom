pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.surfaces.screenlayout

// A screen's desktop modules (a DesktopLayout, DesktopConfig.layoutFor),
// under the windows: on the Bottom layer, over the wallpaper. The grid is
// fitted inside what's reserved on each edge and Hyprland's gaps_out
// (DesktopManager.insetsFor), so it lines up with where tiled windows
// start. Only the modules take clicks (the input mask): the rest of the
// desktop is clicked through. The keyboard only on a click, and only
// while a module takes typing (x-keyboard, e.g. Notes): otherwise clicking
// a clock would take it from the focused window.
PanelWindow {
  id: root

  required property var layout

  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "axiom-desktop"
  WlrLayershell.keyboardFocus: view.wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region {
    regions: maskRegions.instances
  }

  Variants {
    id: maskRegions
    model: view.moduleRects
    delegate: Region {
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: modelData.width
      height: modelData.height
    }
  }

  ScreenLayoutView {
    id: view
    screen: root.screen
    layout: root.layout
    modules: root.layout?.modules ?? []
    // The modules sit on the wallpaper, frosting a copy of it in their
    // boxes (when they draw them)
    showBackdrop: false
    frost: root.layout?.moduleBorders ?? false
    wallpaper: root.screen ? ThemeManager.wallpaperFor(root.screen.name) : ""
    blurWallpaper: false
    hyprBlur: CompositorManager.blur
    insets: DesktopManager.insetsFor(root.screen)
    host: ({
        "kind": "desktop",
        "preview": false,
        "screen": root.screen?.name ?? "",
        "bare": !(root.layout?.moduleBorders ?? false)
      })
  }
}
