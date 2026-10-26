pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.services.compositor
import qs.services.ui
import qs.config
import qs.components.bar

// The bars: one BarPanel per ScreenEdgeManager.bars entry.
Scope {
  id: root

  Variants {
    // Keyed on the stable bar id so a config reload rebinds the existing
    // PanelWindow instead of rebuilding it, and on its layer namespace
    // (BarsConfig.layerNamespace, after a "|"): its kind (solid, pills,
    // transparent, floating) and whether it lies along its screen's longer
    // edge pick it, and Hyprland reads its rule's `order` only as a surface
    // maps, so a bar changing either (a monitor rotated too) is remade to
    // be arranged in its place: a solid bar outside the border, any other
    // inside it, and the longer edge's bar after the shorter edge's of its
    // kind (BarEnds). A remade bar lands correctly once the rules are in
    // (layerRulesReady).
    model: CompositorManager.surfacesReady && General.outputs.length > 0 ? ScreenEdgeManager.bars.map(b => b.id + "|" + BarsConfig.layerNamespace(b)) : []
    delegate: BarPanel {
      required property string modelData
      readonly property string barId: modelData.replace(/\|[^|]*$/, "")
      barConfig: ScreenEdgeManager.bars.find(b => b.id === barId) ?? barConfig
    }
  }
}
