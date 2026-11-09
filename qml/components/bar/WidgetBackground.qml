pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

import qs.config
import qs.components.methods
import qs.components.reusable

// What a bar widget sits on, in its bar's widget style (widgetStyle,
// widgetShape): a fill or outline shaped by its caps (BarShapes), or for
// underline a line along one side. Split fills its icon part over the
// label's (joined, cut by the divider) or draws a badge behind the icon.
// Its hover outline and the bar editor's highlight take the same shape. A
// tab (widgetShape tab) is set reaching out to the edge it hangs from by
// its WidgetGroup, which hands it what bounds its ends (`tabLimits`).
// WidgetGroup draws one under each widget
// with a background, and one under each merged run.
Item {
  id: root

  required property var barConfig
  // The colors to draw in (BarsConfig.widgetColors), or null for none
  property var colors: null
  property string startCap: "round"
  property string endCap: "round"
  // The start as it shows (BarShapes.segment): the hover outline and the
  // highlight trace what's in view, inside it, not the part a powerline
  // neighbour covers
  property string shownStart: startCap
  // Ends that meet a powerline neighbour edge to edge (BarShapes.segment)
  property bool seamStart: false
  property bool seamEnd: false
  // A clickable widget under the pointer (its hoverOutline)
  property bool hovered: false
  // A clickable widget being pressed: a tint in its shape
  property bool pressed: false
  // The bar editor's selected widget
  property bool highlighted: false
  // A level (0-1) filled in its shape along the bar, up a vertical one
  // (the module's `backgroundLevel`); -1 for none
  property real backgroundLevel: -1
  property color backgroundLevelColor: "transparent"
  // The caps the level is drawn in (BarShapes.segment's levelStartCap /
  // levelEndCap): in a merged run the widget's own, not the run's
  property string levelStartCap: startCap
  property string levelEndCap: endCap

  // A split widget's parts (BarWidgetHost.split): along it, the middle of
  // the gap between its icon part and its label, -1 when it doesn't split;
  // what the icon part holds, in its coordinates
  property real splitAt: -1
  property rect splitPart: Qt.rect(0, 0, 0, 0)

  // What bounds a tab's ends along the bar (BarShapes.tabLimits)
  property var tabLimits: [null, null]

  readonly property string _fill: barConfig.widgetStyle
  readonly property bool _boxed: barConfig.widgetBoxed
  // A tab's shape (BarShapes.tab), or null
  readonly property var _tab: barConfig.widgetShape === "tab" ? BarShapes.tab(barConfig.radius, barConfig.thickness, barConfig.tabFillet, !(barConfig.right || barConfig.bottom), tabLimits) : null

  // The shape in one fill and stroke: a Rectangle when both ends are
  // alike and rounded (or square), else a path
  component ShapedBox: Item {
    id: box

    required property var bar
    required property string startCap
    required property string endCap
    property bool seamStart: false
    property bool seamEnd: false
    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0
    // A tab's shape (BarShapes.tab): its stroke is left open along the
    // edge it hangs from
    property var tab: null

    readonly property bool vertical: bar.vertical
    readonly property real across: vertical ? width : height
    readonly property real length: vertical ? height : width
    readonly property real rectRadius: {
      if (startCap !== endCap || seamStart || seamEnd || tab)
        return -1;
      switch (startCap) {
      case "round":
        return box.bar.radius;
      case "capsule":
        return across / 2;
      case "flat":
        return 0;
      default:
        return -1;
      }
    }

    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      visible: box.rectRadius >= 0
      radius: Math.max(0, box.rectRadius)
      color: box.fillColor
      border.color: box.strokeColor
      border.width: box.strokeWidth
    }

    Loader {
      anchors.fill: parent
      active: box.visible && box.rectRadius < 0 && box.width > 0 && box.height > 0
      sourceComponent: Shape {
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: box.fillColor
          strokeColor: box.strokeWidth > 0 && !box.tab ? box.strokeColor : "transparent"
          strokeWidth: box.strokeWidth
          joinStyle: ShapePath.MiterJoin

          // Inset by half the stroke, which is centred on the path
          PathSvg {
            path: BarShapes.path(box.length, box.across, box.bar.radius, box.startCap, box.endCap, box.vertical, box.strokeWidth / 2, box.seamStart, box.seamEnd, box.tab)
          }
        }

        // A tab's stroke, open along its outer edge
        ShapePath {
          fillColor: "transparent"
          strokeColor: box.strokeWidth > 0 && box.tab ? box.strokeColor : "transparent"
          strokeWidth: box.strokeWidth
          joinStyle: ShapePath.MiterJoin

          PathSvg {
            path: box.tab ? BarShapes.path(box.length, box.across, box.bar.radius, box.startCap, box.endCap, box.vertical, box.strokeWidth / 2, false, false, box.tab, true) : ""
          }
        }
      }
    }
  }

  ShapedBox {
    visible: root._boxed && root.colors !== null
    bar: root.barConfig
    tab: root._tab
    startCap: root.startCap
    endCap: root.endCap
    seamStart: root.seamStart
    seamEnd: root.seamEnd
    fillColor: root.colors?.fill ?? "transparent"
    strokeColor: root.colors?.stroke ?? "transparent"
    strokeWidth: root._fill === "outline" ? root.barConfig.outlineWidth : 0

    // State changes (mute, a warning level) recolour smoothly
    ColorGlide on fillColor {}
    ColorGlide on strokeColor {}
  }

  // Split's icon part, joined: the shape from its start to the divider
  // (the bar's splitCap) centred in the gap to the label
  ShapedBox {
    readonly property real _length: root.splitAt + BarShapes.depth(root.barConfig.splitCap, root.barConfig.thickness) / 2

    visible: root.barConfig.splitIcon === "joined" && root.splitAt >= 0 && root.colors !== null
    anchors.fill: undefined
    width: root.barConfig.vertical ? root.width : _length
    height: root.barConfig.vertical ? _length : root.height
    bar: root.barConfig
    tab: root._tab
    startCap: root.startCap
    endCap: root.barConfig.splitCap
    fillColor: root.colors?.iconFill ?? "transparent"

    ColorGlide on fillColor {}
  }

  // Split's badge: the icon part's content with badgePad round it, at
  // least as long as it's thick (a circle for one icon under capsule), a
  // rounded square otherwise, its radius the widgets' scaled to its size
  Rectangle {
    readonly property bool vertical: root.barConfig.vertical
    readonly property real thickness: root.barConfig.thickness
    readonly property real pad: root.barConfig.badgePad
    readonly property real partAlong: vertical ? root.splitPart.height : root.splitPart.width
    readonly property real partAcross: vertical ? root.splitPart.width : root.splitPart.height
    readonly property real across: Math.min(thickness, partAcross + pad * 2)
    readonly property real along: Math.max(partAlong + pad * 2, across)
    readonly property real alongMiddle: vertical ? root.splitPart.y + partAlong / 2 : root.splitPart.x + partAlong / 2
    readonly property real acrossMiddle: vertical ? root.splitPart.x + partAcross / 2 : root.splitPart.y + partAcross / 2
    // Within the background across (a tab's reaches past the bar's thickness)
    readonly property real acrossStart: Math.max(0, Math.min((vertical ? root.width : root.height) - across, acrossMiddle - across / 2))

    visible: root.barConfig.splitIcon === "badge" && root.splitAt >= 0 && root.colors !== null
    x: vertical ? acrossStart : alongMiddle - along / 2
    y: vertical ? alongMiddle - along / 2 : acrossStart
    width: vertical ? across : along
    height: vertical ? along : across
    radius: root.barConfig.widgetShape === "capsule" ? across / 2 : Math.min(across / 2, root.barConfig.radius * across / thickness)
    color: root.colors?.iconFill ?? "transparent"

    ColorGlide on color {}
  }

  // Along the side toward the windows (inner) or the screen edge (outer)
  Rectangle {
    readonly property real thickness: root.barConfig.lineWidth
    readonly property bool vertical: root.barConfig.vertical
    // The side further from the bar's outer edge, in item coordinates
    readonly property bool farSide: (root.barConfig.lineSide === "inner") !== (root.barConfig.right || root.barConfig.bottom)

    visible: root._fill === "underline" && root.colors !== null
    color: root.colors?.indicator ?? "transparent"
    radius: thickness / 2
    x: vertical && farSide ? root.width - thickness : 0
    y: !vertical && farSide ? root.height - thickness : 0
    width: vertical ? thickness : root.width
    height: vertical ? root.height : thickness

    ColorGlide on color {}
  }

  // The level: the background's own shape (in a merged run, the one the
  // widget has alone) in the level's colour, seen from where the bar's run
  // starts (up a vertical bar, from the bottom) through a window ending on
  // a rounded edge (a capsule's, else the bar's radius). Clipped rather
  // than a shape of its own, so a low level stays inside the background's
  // ends instead of squeezing its corners square. The window overhangs
  // the start (and, full, the far end unless that's flat), so only its
  // leading edge rounds and never by less than its radius.
  ClippingRectangle {
    id: level
    readonly property bool vertical: root.barConfig.vertical
    readonly property real share: Math.max(0, Math.min(1, root.backgroundLevel))
    readonly property real across: vertical ? root.width : root.height
    // The cap at the far end, where a full level ends
    readonly property string farCap: vertical ? root.levelStartCap : root.levelEndCap
    readonly property real room: vertical ? root.height : root.width
    readonly property real shown: room * share + (share >= 1 && farCap !== "flat" ? across : 0)

    visible: root.backgroundLevel >= 0 && level.share > 0
    color: "transparent"
    // A Rectangle keeps it to half the thickness, which the window never
    // drops below
    radius: root.barConfig.widgetShape === "capsule" ? across / 2 : root.barConfig.radius
    x: vertical ? 0 : -across
    y: vertical ? root.height - shown : 0
    width: vertical ? root.width : shown + across
    height: vertical ? shown + across : root.height

    Glide on width {
      duration: Appearance.animNormal
    }
    Glide on height {
      duration: Appearance.animNormal
    }
    Glide on y {
      duration: Appearance.animNormal
    }

    ShapedBox {
      anchors.fill: undefined
      x: -level.x
      y: -level.y
      width: root.width
      height: root.height
      bar: root.barConfig
      tab: root._tab
      startCap: root.levelStartCap
      endCap: root.levelEndCap
      seamStart: root.seamStart
      seamEnd: root.seamEnd
      fillColor: root.backgroundLevelColor

      ColorGlide on fillColor {}
    }
  }

  ShapedBox {
    // Built only while it shows, fading out included
    visible: root._boxed && fillColor.a > 0
    bar: root.barConfig
    tab: root._tab
    startCap: root.shownStart
    endCap: root.endCap
    fillColor: Qt.alpha(root.colors?.text ?? Theme.foreground, root.pressed && root.colors !== null ? 0.2 : 0)

    ColorGlide on fillColor {}
  }

  ShapedBox {
    visible: root.highlighted
    bar: root.barConfig
    tab: root._tab
    startCap: root.shownStart
    endCap: root.endCap
    fillColor: Qt.alpha(Theme.accent, 0.15)
    strokeColor: Theme.accent
    strokeWidth: 2
  }

  ShapedBox {
    // Built only while it shows, fading out included
    visible: strokeColor.a > 0
    bar: root.barConfig
    tab: root._tab
    startCap: root.shownStart
    endCap: root.endCap
    strokeColor: root.hovered ? Theme.border : Qt.alpha(Theme.border, 0)
    strokeWidth: Appearance.borderWidth

    ColorGlide on strokeColor {
      duration: Appearance.animNormal
    }
  }
}
