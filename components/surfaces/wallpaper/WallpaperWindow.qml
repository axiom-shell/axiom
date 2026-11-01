pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

// A screen's wallpaper (WallpaperView: its transitions), sliding with the
// workspaces when the parallax is on
PanelWindow {
  id: root

  readonly property string name: screen?.name ?? ""
  // Where the parallax puts it for the output's active workspace
  readonly property var _shift: Appearance.wallpaperParallax ? WallpaperFill.parallax(CompositorManager.output(root.name)?.activeWorkspaceId ?? 0, {
    "grid": WorkspacesConfig.grid,
    "columns": WorkspacesConfig.columns,
    "rows": WorkspacesConfig.rows,
    "size": WorkspacesConfig.size,
    "base": CompositorManager.workspaceBase(root.name),
    "dynamic": CompositorManager.supports.dynamicWorkspaces === true,
    "vertical": CompositorManager.supports.verticalWorkspaces === true,
    "ids": CompositorManager.workspaces.filter(w => w.output === root.name).map(w => w.id)
  }) : ({
      "x": 0,
      "y": 0
    })

  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.namespace: "axiom-wallpaper"
  exclusionMode: ExclusionMode.Ignore
  color: Theme.background
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  WallpaperView {
    anchors.fill: parent
    source: ThemeManager.wallpaperFor(root.name)
    zoom: Appearance.wallpaperParallax ? 1 + Appearance.wallpaperParallaxStrength / 100 : 1
    shiftX: root._shift.x
    shiftY: root._shift.y

    Behavior on shiftX {
      NumberAnimation {
        duration: Appearance.animSlow
        easing.type: Appearance.easing
      }
    }
    Behavior on shiftY {
      NumberAnimation {
        duration: Appearance.animSlow
        easing.type: Appearance.easing
      }
    }
  }
}
