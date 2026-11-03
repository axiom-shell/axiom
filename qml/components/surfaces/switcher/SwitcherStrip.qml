pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.methods
import qs.components.reusable

// The switcher's windows as tiles in WindowSwitcherConfig.order, as many
// to a line as fit `maxWidth` (rows) or `maxHeight` (columns), wrapping
// only past that (WindowOrder.tileGrid). Modelled by count: the list is
// fixed while the switcher is open.
Item {
  id: root

  property real maxWidth: 0
  property real maxHeight: 0

  readonly property int count: WindowSwitcherManager.windows.length
  readonly property bool vertical: WindowSwitcherConfig.order === "topToBottom" || WindowSwitcherConfig.order === "bottomToTop"
  // Every tile is as tall (one title line), measured off the first
  property real tileHeight: 0
  // A tile and the gap after it, each way
  readonly property real pitchX: WindowSwitcherConfig.tileSize + Widget.spacing
  readonly property real pitchY: root.tileHeight + Widget.spacing
  readonly property int perLine: root.vertical ? (root.tileHeight > 0 ? Math.floor((root.maxHeight + Widget.spacing) / root.pitchY) : root.count) : Math.floor((root.maxWidth + Widget.spacing) / root.pitchX)
  readonly property var grid: WindowOrder.tileGrid(root.count, root.perLine, WindowSwitcherConfig.order)

  implicitWidth: root.count > 0 ? root.grid.columns * root.pitchX - Widget.spacing : empty.implicitWidth
  implicitHeight: root.count > 0 ? root.grid.rows * root.pitchY - Widget.spacing : empty.implicitHeight

  Repeater {
    model: root.count
    onItemAdded: (index, item) => {
      if (index === 0)
        root.tileHeight = Qt.binding(() => item.implicitHeight);
    }

    SwitcherTile {
      id: tile
      readonly property var cell: root.grid.cells[tile.index] ?? ({
          "column": 0,
          "row": 0
        })
      x: tile.cell.column * root.pitchX
      y: tile.cell.row * root.pitchY
      height: root.tileHeight
    }
  }

  StyledText {
    id: empty
    visible: root.count === 0
    text: I18n.tr("No windows")
    textColor: Theme.foregroundAlt
  }
}
