pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// A workspace's number badge on the overview board, drawn over its windows
Rectangle {
  id: root

  property int number: 1
  // The monitor's active workspace
  property bool current: false
  // The cell's corner radius; the badge sits clear of its border (the
  // thicker, active one) and of the corner's curve
  property real cornerRadius: Widget.radius
  readonly property real _edge: Appearance.borderWidth * 2 + 2
  // Its inset from the cell's corner (placed by OverviewGrid): past the
  // border along the edges, and far enough in that the pill's end circle
  // stays inside the corner's inner arc
  readonly property real margin: {
    const r = height / 2;
    const inner = root.cornerRadius - root._edge;
    const corner = root.cornerRadius - r - (inner - r) / Math.SQRT2;
    return Math.max(root._edge, corner);
  }

  width: Math.max(height, label.implicitWidth + Widget.padding)
  height: label.implicitHeight + Widget.px(4)
  radius: height / 2
  color: root.current ? Theme.accent : Qt.alpha(Theme.background, 0.75)

  StyledText {
    id: label
    anchors.centerIn: parent
    text: root.number
    textSize: Appearance.fontSizeBy(-2)
    textColor: root.current ? Theme.background : Theme.foreground
    font.bold: root.current
  }
}
