pragma ComponentBehavior: Bound
import QtQuick

// The look's line (underline: look.line's { width, farSide }) along the side
// of its parent the bar's lines take, its whole length, in `color` or its
// slice of the bar's gradient (`slice`, BarGradient.gradientSlice): a
// widget's background's and a Workspaces cell's (LookBox). None where the
// look draws no line.
Rectangle {
  id: root

  // look.line, or null
  property var line: null
  property bool vertical: false
  property var slice: null

  readonly property real thickness: line?.width ?? 0
  // The side further from the bar's outer edge, in item coordinates
  readonly property bool farSide: line?.farSide ?? false

  visible: line !== null
  gradient: root.slice !== null ? sliceGradient : null
  radius: thickness / 2
  x: vertical && farSide ? parent.width - thickness : 0
  y: !vertical && farSide ? parent.height - thickness : 0
  width: vertical ? thickness : parent.width
  height: vertical ? parent.height : thickness

  RectSlice {
    id: sliceGradient
    slice: root.slice
    vertical: root.vertical
  }
}
