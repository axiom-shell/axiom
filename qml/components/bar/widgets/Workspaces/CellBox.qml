pragma ComponentBehavior: Bound
import QtQuick

import qs.components.reusable
import qs.components.bar.widgets.base

// A bar switcher cell's box in the boxed widget styles, filling its parent:
// its fill, and an outline's stroke in the look's stroke (a solid one
// the Rectangle's border, any other an OutlineStroke over it). As a segment
// of the bar's run (`shape`: the widget's Background off) it's a ShapedBox
// in the bar's widget shape instead, reaching back under the cell before
// and out to a tab's edge, which may take a slice of the bar's gradient.
// WorkspaceCell's, and the one ActiveCellIndicator slides.
Item {
  id: root

  required property var barConfig
  property color fillColor: "transparent"
  property color strokeColor: "transparent"
  property real radius: 0
  // Its shape as a segment of the bar's run (BarShapes.cellShape), or null
  property var shape: null
  // Its slice of the bar's gradient (BarGradient.gradientSlice) for its
  // fill or stroke, else null
  property var fillSlice: null
  property var strokeSlice: null
  // Color changes glide
  property bool animated: false

  // The look's outline ({ width, stroke }), or null: not outline
  readonly property var _outlineLook: barConfig.look.outline
  readonly property bool _outline: _outlineLook !== null
  readonly property string _stroke: _outlineLook?.stroke ?? "solid"
  readonly property bool _solid: _stroke === "solid"
  readonly property bool _vertical: barConfig.vertical
  // A double outline's band is three lines wide: in a cell, half-width
  // lines, so the inner one keeps clear of the label
  readonly property real _lineWidth: !_outline ? 0 : _stroke === "double" ? Math.max(1, Math.floor(_outlineLook.width / 2)) : _outlineLook.width

  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    visible: root.shape === null
    radius: root.radius
    color: root.fillColor
    border.color: root.strokeColor
    border.width: root._outline && root._solid ? root._outlineLook.width : 0

    ColorGlide on color {
      enabled: root.animated
    }
    ColorGlide on border.color {
      enabled: root.animated
    }
  }

  OutlineStroke {
    anchors.fill: parent
    visible: root.shape === null && root._outline && !root._solid && color.a > 0
    stroke: root._stroke
    vertical: root._vertical
    radius: root.radius
    color: root.strokeColor
    lineWidth: root._lineWidth

    ColorGlide on color {
      enabled: root.animated
    }
  }

  // As a segment: back under the cell before (its `back`) and across out
  // to a tab's edge (`reachStart`, `reachEnd`)
  Loader {
    readonly property var _segment: root.shape?.segment ?? null
    readonly property real _back: _segment?.back ?? 0
    readonly property real _near: root.shape?.reachStart ?? 0
    readonly property real _far: root.shape?.reachEnd ?? 0

    active: root.shape !== null
    x: root._vertical ? -_near : -_back
    y: root._vertical ? -_back : -_near
    width: root.width + (root._vertical ? _near + _far : _back)
    height: root.height + (root._vertical ? _back : _near + _far)

    sourceComponent: ShapedBox {
      readonly property var _segment: root.shape?.segment ?? null

      bar: root.barConfig
      startCap: _segment?.startCap ?? "round"
      endCap: _segment?.endCap ?? "round"
      seamStart: _segment?.seamStart ?? false
      seamEnd: _segment?.seamEnd ?? false
      tab: root.shape?.tab ?? null
      fillColor: root.fillColor
      strokeColor: root.strokeColor
      strokeWidth: root._outline ? root._lineWidth : 0
      stroke: root._stroke
      fillSlice: root.fillSlice
      strokeSlice: root.strokeSlice

      ColorGlide on fillColor {
        enabled: root.animated
      }
      ColorGlide on strokeColor {
        enabled: root.animated
      }
    }
  }
}
