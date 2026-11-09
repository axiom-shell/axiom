pragma ComponentBehavior: Bound
import QtQuick

// A bar switcher cell's line in the underline widget style, along the side
// the bar's widget lines take, filling its parent's length: WorkspaceCell's,
// and the one ActiveCellIndicator slides
Rectangle {
  id: root

  required property var barConfig

  readonly property bool isVertical: barConfig.vertical
  // The look's line ({ width, farSide }), or null: not underline
  readonly property var _line: barConfig.look.line
  readonly property real lineWidth: _line?.width ?? 0
  readonly property bool farSide: _line?.farSide ?? false

  visible: _line !== null
  radius: lineWidth / 2
  x: isVertical && farSide ? parent.width - lineWidth : 0
  y: !isVertical && farSide ? parent.height - lineWidth : 0
  width: isVertical ? lineWidth : parent.width
  height: isVertical ? parent.height : lineWidth
}
