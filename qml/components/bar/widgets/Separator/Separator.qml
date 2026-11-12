pragma ComponentBehavior: Bound
import QtQuick

import qs.components.reusable
import qs.components.bar.widgets.base

// Layout helper for the bar: a divider (a line, dot, slash or chevron),
// taking exactly `size` px along the bar (empty room is a Spacer).
BarWidget {
  id: root

  // Layout, not content: no background of its own
  hasBackground: false

  // Already a divider: its WidgetGroup draws none beside it
  divides: true

  // BarWidgetHost sizing contract
  sizePolicy: "fixed"
  preferredSize: properties.size

  implicitWidth: isVertical ? root.barConfig.thickness : properties.size
  implicitHeight: isVertical ? properties.size : root.barConfig.thickness

  // Across the bar, so it divides the modules on either side
  SeparatorMark {
    anchors.centerIn: parent
    style: root.properties.style
    color: root.paint.line("color")
    thickness: root.properties.thickness
    length: root.barConfig.thickness * root.properties.length / 100
    vertical: root.isVertical
  }
}
