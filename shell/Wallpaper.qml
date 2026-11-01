pragma ComponentBehavior: Bound
import Quickshell

import qs.config
import qs.components.surfaces.wallpaper

// The wallpaper: one background window per screen
Scope {
  Variants {
    model: General.outputs
    delegate: WallpaperWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}
