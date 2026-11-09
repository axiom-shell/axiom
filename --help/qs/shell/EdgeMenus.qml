pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.compositor
import qs.components.surfaces.edgemenu

// The edge menus (EdgeMenusConfig), one per enabled entry. Keyed on the
// stable id, so a config reload rebinds a menu instead of rebuilding it
// (an open integrated menu would otherwise drop its zone and come back).
Scope {
  Variants {
    // Once the layer rules are in (CompositorManager.surfacesReady)
    model: CompositorManager.surfacesReady ? EdgeMenusConfig.enabledMenus.map(menu => menu.id) : []

    delegate: EdgeMenu {
      required property string modelData
      menuId: modelData
    }
  }
}
