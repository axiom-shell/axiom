pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.components.reusable

// A bar widget's hover tooltip: after hovering for a moment, on the bar's
// inner side, in a window of its own (StyledToolTip), built only while
// `widget` is hovered, `shown` and there's text
LazyLoader {
  id: root

  required property BarWidget widget
  property string text: ""
  property bool shown: true
  // The text is rich text (StyledToolTip.rich)
  property bool rich: false

  active: root.widget.hovered && root.shown && root.text !== ""

  StyledToolTip {
    target: root.widget
    text: root.text
    rich: root.rich
    edges: root.widget.innerEdges
  }
}
