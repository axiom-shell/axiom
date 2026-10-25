pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.reusable

// The switcher's windows as tiles, as many to a row as fit `maxWidth`.
// Modelled by count: the list is fixed while the switcher is open.
Item {
  id: root

  property real maxWidth: 0

  readonly property int count: WindowSwitcherManager.windows.length
  // A tile and the gap after it
  readonly property real pitch: WindowSwitcherConfig.tileSize + Widget.spacing
  readonly property int columns: Math.max(1, Math.min(root.count, Math.floor((root.maxWidth + Widget.spacing) / root.pitch)))

  implicitWidth: root.count > 0 ? root.columns * root.pitch - Widget.spacing : empty.implicitWidth
  implicitHeight: root.count > 0 ? flow.implicitHeight : empty.implicitHeight

  TileFlow {
    id: flow
    width: root.implicitWidth
    minTileWidth: WindowSwitcherConfig.tileSize

    Repeater {
      model: root.count

      SwitcherTile {
        tileWidth: flow.tileWidth
      }
    }
  }

  StyledText {
    id: empty
    visible: root.count === 0
    text: I18n.tr("No windows")
    textColor: Theme.foregroundAlt
  }
}
