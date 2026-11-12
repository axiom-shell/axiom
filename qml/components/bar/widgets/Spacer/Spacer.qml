pragma ComponentBehavior: Bound
import QtQuick

import qs.components.bar.widgets.base

// Layout helper for the bar: empty room between widgets, splitting a
// section into groups. On a side of the bar it takes the free room there,
// shared with that side's other spacers, keeping at least its minimum gap
// (BarLayout.allocate); in the center it pushes the groups outside the one
// kept centered out to the sides (BarLayout.centerSplit).
BarWidget {
  id: root

  // Room, not content: no background of its own
  hasBackground: false
  // Room, not a widget: its WidgetGroup draws no divider beside it
  divides: true
  // It fills the room its section is given past its widgets
  fills: true

  // BarWidgetHost sizing contract
  sizePolicy: "fixed"
  preferredSize: properties.minGap

  implicitWidth: isVertical ? root.barConfig.thickness : properties.minGap
  implicitHeight: isVertical ? properties.minGap : root.barConfig.thickness
}
