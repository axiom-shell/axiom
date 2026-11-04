pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.bar.widgets.base

// Layout helper for the bar: a divider (a line, dot, slash or chevron),
// taking exactly `size` px along the bar (empty room is a Spacer).
BarWidget {
  id: root

  readonly property color color: Theme.resolveColor(properties.color)

  // Already a divider: its WidgetGroup draws none beside it
  readonly property bool divides: true

  // BarWidgetHost sizing contract
  readonly property string sizePolicy: "fixed"
  readonly property real preferredSize: properties.size

  implicitWidth: isVertical ? root.barConfig.thickness : properties.size
  implicitHeight: isVertical ? properties.size : root.barConfig.thickness

  // Across the bar, so it divides the modules on either side
  SeparatorMark {
    anchors.centerIn: parent
    style: root.properties.style
    color: root.color
    thickness: root.properties.thickness
    length: root.barConfig.thickness * root.properties.length / 100
    vertical: root.isVertical
  }
}
