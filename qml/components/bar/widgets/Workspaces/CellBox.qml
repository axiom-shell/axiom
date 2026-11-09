pragma ComponentBehavior: Bound
import QtQuick

import qs.components.reusable
import qs.components.bar.widgets.base

// A bar switcher cell's box in the boxed widget styles, filling its parent:
// its fill, and an outline's stroke in the bar's outlineStroke (a solid one
// the Rectangle's border, any other an OutlineStroke over it).
// WorkspaceCell's, and the one ActiveCellIndicator slides.
Item {
  id: root

  required property var barConfig
  property color fillColor: "transparent"
  property color strokeColor: "transparent"
  property real radius: 0
  // Color changes glide
  property bool animated: false

  readonly property bool _outline: barConfig.widgetStyle === "outline"
  readonly property bool _solid: barConfig.outlineStroke === "solid"

  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.fillColor
    border.color: root.strokeColor
    border.width: root._outline && root._solid ? root.barConfig.outlineWidth : 0

    ColorGlide on color {
      enabled: root.animated
    }
    ColorGlide on border.color {
      enabled: root.animated
    }
  }

  OutlineStroke {
    anchors.fill: parent
    visible: root._outline && !root._solid && color.a > 0
    stroke: root.barConfig.outlineStroke
    vertical: root.barConfig.vertical
    radius: root.radius
    color: root.strokeColor
    // A double outline's band is three lines wide: in a cell, half-width
    // lines, so the inner one keeps clear of the label
    lineWidth: root.barConfig.outlineStroke === "double" ? Math.max(1, Math.floor(root.barConfig.outlineWidth / 2)) : root.barConfig.outlineWidth

    ColorGlide on color {
      enabled: root.animated
    }
  }
}
