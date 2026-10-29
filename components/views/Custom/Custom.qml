pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.hosts.overlay
import qs.components.views.base

// A view assembled from config: its modules, each in its place on a grid
// of quarter cards (eighths with a double grid, `layout.grid.fine`: laid out at
// its card size, OverlayConfig.pageUnit).
BaseView {
  id: root

  // viewConfig: { id, type: "Custom", name, icon, layout: { grid: { fine }, modules: [...] } }
  property var modules: root.viewConfig?.layout?.modules ?? []

  property OverlayGrid fineGrid: OverlayGrid {
    availableWidth: root.grid?.roomWidth ?? 0
    availableHeight: root.grid?.roomHeight ?? 0
    fixedUnit: OverlayConfig.pageUnit(root.viewConfig, root.grid?.unit ?? 0)
  }

  ModuleGrid {
    modules: root.modules
    grid: root.viewConfig?.layout?.grid?.fine ? root.fineGrid : root.grid
    stream: true
    // Module borders off: no card boxes, the content keeping its padding
    host: ({
        "kind": "overlay",
        "bare": !OverlayConfig.moduleBorders,
        "padded": true
      })
  }
}
