pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.methods
import qs.components.hosts.popout

// One screen's border (Appearance.screenBorder): an edge strip per side
// (BorderPanel), reserving `frameWidth`, and a concave corner piece
// (CornerPiece) in each corner joining their inner strokes. A solid bar's
// edge draws only the stroke, so the bar shows through.
Item {
  id: root

  property var screen: null
  property int frameWidth: Appearance.screenMargin
  property int innerBorderRadius: Appearance.borderRadius
  property color frameColor: Style.surfacePage
  property color innerStrokeColor: Style.frameStroke
  property int strokeWidth: Appearance.borderWidth
  // The corner's curve plus its stroke
  readonly property int cornerSize: FrameOutline.cornerSize(root._spec)

  // Corners sit in the space left once every edge is reserved, so bars
  // or a dock inside the border (reserving their own space) would push
  // them in past it. Pull them back out to the border's corners: past
  // what the bars inside the border take (BarEnds.edgeOf's insideTaken)
  // and the stroke they reach back onto.
  function _edge(edge) {
    return ScreenEdgeManager.edgeOn(root.screen, ScreenEdge.fromName(edge));
  }
  function cornerMargin(edge) {
    const docks = DockManager.zoneOn(root.screen?.name ?? "", edge);
    return -root._edge(edge).insideTaken - root.strokeWidth - docks;
  }
  // How far in from a screen edge the frame's inner edge lies: past the
  // solid bars reserving that edge (the strip is arranged after them, see
  // BarPanel), else the frame's own width
  function innerInset(edge) {
    return root._edge(edge).solidZone + root.frameWidth;
  }

  // A solid bar's strip lies over the innermost reserving solid bar's
  // inner part (BarEnds.placeStack): there it draws only its stroke, past
  // the bar, so the bar and its widgets show through
  function frameColorFor(edge) {
    return root.backed || root._edge(edge).strip ? "transparent" : root.frameColor;
  }

  // The blur window draws the frame's fill (BlurManager): the strips and
  // corners draw their strokes only
  readonly property bool backed: BlurManager.backsOn(root.screen, false)
  // The frame, for it: from past the integrated edge menus on each edge
  // (arranged outside the border) to the stroke's inner side, round the
  // corner pieces' arcs, in screen coordinates
  function _menuZone(edge) {
    return ScreenEdgeManager.zoneOn(root.screen?.name ?? "", edge);
  }
  readonly property real outerLeft: root._menuZone("left")
  readonly property real outerTop: root._menuZone("top")
  readonly property real outerRight: root._menuZone("right")
  readonly property real outerBottom: root._menuZone("bottom")
  readonly property real innerLeft: root.outerLeft + root.innerInset("left")
  readonly property real innerTop: root.outerTop + root.innerInset("top")
  readonly property real innerRight: root.outerRight + root.innerInset("right")
  readonly property real innerBottom: root.outerBottom + root.innerInset("bottom")
  // What FrameOutline reads: this frame's settings, and this screen's border openings
  readonly property var _spec: ({
      "width": root.screen?.width ?? 0,
      "height": root.screen?.height ?? 0,
      "outerLeft": root.outerLeft,
      "outerTop": root.outerTop,
      "outerRight": root.outerRight,
      "outerBottom": root.outerBottom,
      "innerLeft": root.innerLeft,
      "innerTop": root.innerTop,
      "innerRight": root.innerRight,
      "innerBottom": root.innerBottom,
      "innerBorderRadius": root.innerBorderRadius,
      "strokeWidth": root.strokeWidth
    })
  readonly property var _openings: SurfaceManager.borderOpenings.filter(o => o.screen === (root.screen?.name ?? ""))
  // The stroke's inner side, round the corner pieces' arcs, as an SVG
  // subpath in a window of w × h over the screen (FrameOutline.innerPath)
  function innerPath(w, h) {
    return FrameOutline.innerPath(root._spec, w, h);
  }
  // Its fill as blur region pieces in a window of w × h over the screen (FrameOutline.blurRegion)
  function blurPieces(w, h) {
    return FrameOutline.blurRegion(root._spec, w, h);
  }
  // Where the stroke is left open under what joins it (FrameOutline.strokeHoles)
  readonly property var strokeHoles: FrameOutline.strokeHoles(root._spec, root._openings)
  // The frame, filled odd-even, to innerPath (FrameOutline.framePath)
  function framePath(w, h, fromMenus) {
    return FrameOutline.framePath(root._spec, w, h, fromMenus);
  }

  BlurShape {
    source: root
    kind: "frame"
    color: root.frameColor
    strokeColor: root.innerStrokeColor
    paintRank: PaintOrder.rankOf("frame")
    screen: root.screen?.name ?? ""
    shown: root.backed
    // Cast evenly, inward, by the blur window in place of shadowWindow's
    shadow: BarStyle.look
  }

  // What the backing window's copy strokes the frame with, as these pieces
  // draw it on screen: the four strips' stroke rows, the four corner
  // windows' boxes (each with the corner it is)
  readonly property var strokeRects: Array.prototype.map.call(strips.instances, p => p.screenStroke)
  readonly property var cornerBoxes: Array.prototype.map.call(cornerWindows.instances, c => ({
        "box": c.screenBox,
        "isLeft": c.isLeft,
        "isTop": c.isTop
      }))

  // An edge strip per side
  Variants {
    id: strips
    model: ["top", "bottom", "left", "right"]

    delegate: BorderPanel {
      required property string modelData
      edge: modelData
      screen: root.screen
      frameWidth: root.frameWidth
      innerBorderRadius: root.innerBorderRadius
      frameColor: root.frameColorFor(modelData)
      endFillColor: root.backed ? "transparent" : root.frameColor
      innerStrokeColor: root.backed ? "transparent" : root.innerStrokeColor
      strokeWidth: root.strokeWidth
    }
  }

  // The border's shadow (the BarStyle section's, as the bars
  // cast): the frame's shape blurred and kept only inside it, so it falls
  // on the windows all the way round. One window over the whole screen,
  // so it runs unbroken past the strips and corners. Its layer rule
  // (`order = 11`) stacks it under every other axiom surface, the overlay
  // backdrop included, so bars inside the border stay clear of it.
  PanelWindow {
    id: shadowWindow

    readonly property var look: BarStyle.look

    // Backed, the blur window casts it, with the surfaces joined to the
    // frame (BlurShape.shadow): this one keeps its place at a pixel, no
    // buffer, drawing nothing.
    // Hyprland puts a layer mapped while a fullscreen window is shown over
    // it (CLayerSurface::onMap), and a fullscreen window is what unbacks it.
    // Held where the compositor stacks by map order alone: turning the
    // shadow on would otherwise map it after everything ordered under it
    // (the backdrop, the bars, the border, docks), which all map again
    // then (docs/dev/compositor/layer-arrangement.md). Idle, it's a pixel
    // drawing nothing.
    readonly property bool _casting: !shadowSlot.idle && !root.backed
    visible: shadowSlot.shown
    LayerSlot {
      id: shadowSlot
      window: shadowWindow
      namespace: "axiom-border-shadow"
      wanted: shadowWindow.look.shadow
      held: true
    }
    screen: root.screen
    anchors {
      left: true
      right: shadowWindow._casting
      top: true
      bottom: shadowWindow._casting
    }
    implicitWidth: 1
    implicitHeight: 1
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    aboveWindows: true
    WlrLayershell.namespace: "axiom-border-shadow"

    // The inside of the frame
    Item {
      id: interior
      anchors.fill: parent
      visible: false
      layer.enabled: shadowWindow._casting // style-exempt: no text

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: "black" // style-exempt: mask
          fillRule: ShapePath.OddEvenFill
          strokeColor: "transparent"
          strokeWidth: 0

          PathSvg {
            path: root.innerPath(shadowWindow.width, shadowWindow.height)
          }
        }
      }
    }

    Item {
      anchors.fill: parent
      visible: shadowWindow._casting
      layer.enabled: visible // style-exempt: no text
      layer.effect: MultiEffect { // style-exempt: no text
        maskEnabled: true
        maskSource: interior
      }

      // The frame, casting the shadow inward (it's cut away above)
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true // style-exempt: no text
        layer.effect: MultiEffect { // style-exempt: no text
          shadowEnabled: true
          shadowColor: Style.shadowColor(shadowWindow.look)
          shadowBlur: 1
          blurMax: shadowWindow.look.shadowSize
        }

        ShapePath {
          fillColor: "black" // style-exempt: mask
          fillRule: ShapePath.OddEvenFill
          strokeColor: "transparent"
          strokeWidth: 0

          PathSvg {
            path: root.framePath(shadowWindow.width, shadowWindow.height, false)
          }
        }
      }
    }
  }

  // A corner piece in each corner
  Variants {
    id: cornerWindows
    model: [
      {
        "isLeft": true,
        "isTop": true
      },
      {
        "isLeft": false,
        "isTop": true
      },
      {
        "isLeft": true,
        "isTop": false
      },
      {
        "isLeft": false,
        "isTop": false
      }
    ]

    delegate: PanelWindow {
      id: corner

      required property var modelData
      readonly property bool isLeft: modelData.isLeft
      readonly property bool isTop: modelData.isTop

      screen: root.screen
      anchors {
        left: corner.isLeft
        right: !corner.isLeft
        top: corner.isTop
        bottom: !corner.isTop
      }
      margins {
        left: corner.isLeft ? root.cornerMargin("left") : 0
        right: corner.isLeft ? 0 : root.cornerMargin("right")
        top: corner.isTop ? root.cornerMargin("top") : 0
        bottom: corner.isTop ? 0 : root.cornerMargin("bottom")
      }
      implicitWidth: root.cornerSize
      implicitHeight: root.cornerSize
      color: "transparent"
      mask: Region {}
      aboveWindows: true
      WlrLayershell.namespace: "axiom-border"
      visible: cornerSlot.shown
      LayerSlot {
        id: cornerSlot
        window: corner
        namespace: "axiom-border"
        // After the strips, over their ends
        rank: 1
      }

      // Where it is on screen: a stroke out from the frame's inner side,
      // past the integrated edge menus (cornerMargin is taken from what
      // they reserve)
      readonly property real _x: FrameOutline.cornerBox(root._spec, corner.isLeft, corner.isTop).x
      readonly property real _y: FrameOutline.cornerBox(root._spec, corner.isLeft, corner.isTop).y
      // Its box as the compositor shows it, on whole device px
      readonly property rect screenBox: FrameOutline.windowPixels(Qt.rect(corner._x, corner._y, root.cornerSize, root.cornerSize), corner.devicePixelRatio)
      CornerPiece {
        borderRadius: root.innerBorderRadius
        fillColor: root.backed ? "transparent" : root.frameColor
        strokeColor: root.backed ? "transparent" : root.innerStrokeColor
        strokeWidth: root.strokeWidth
        isLeft: corner.isLeft
        isTop: corner.isTop
      }
    }
  }
}
