pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// The divider a switcher's after-parts (ActiveStrip, ScratchpadCells) start
// with: the bar's separator style (a line when that's none), across the
// bar as long as a cell is thick (shorter than it for a chevron's
// slant).
SeparatorMark {
  id: root

  required property var barConfig
  // A cell's thickness across the bar (CellLook.thickness)
  required property real cell

  style: root.barConfig.look.separators.style === "none" ? "line" : root.barConfig.look.separators.style
  color: Theme.resolveColor(root.barConfig.look.separators.color)
  thickness: root.barConfig.look.separators.thickness
  length: root.cell * (style === "chevron" ? 0.6 : 0.5)
  vertical: root.barConfig.vertical
  width: root.barConfig.vertical ? root.cell : implicitWidth
  height: root.barConfig.vertical ? implicitHeight : root.cell
}
