pragma ComponentBehavior: Bound
import QtQuick

import qs.components.bar.widgets.base

// Layout helper for the bar: empty room between widgets, splitting a
// section into groups. It takes its minimum gap along the bar.
BarWidget {
  id: root

  // Room, not a widget: its WidgetGroup draws no divider beside it
  readonly property bool divides: true

  // BarWidgetHost sizing contract
  readonly property string sizePolicy: "fixed"
  readonly property real preferredSize: properties.minGap

  implicitWidth: isVertical ? root.barConfig.thickness : properties.minGap
  implicitHeight: isVertical ? properties.minGap : root.barConfig.thickness
}
