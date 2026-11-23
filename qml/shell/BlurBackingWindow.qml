pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.hosts.popout
import qs.components.methods
import qs.components.reusable

// One backing window (BlurBacking): click-through, keeping a copy of each
// of `shapes` (every BlurShape on its screen) and drawing those it `draws`,
// fill and stroke in painter's order (PaintOrder), as one image
// (ChromeComposite), with their shadows cast once per look, from the
// shapes' outlines (fill and stroke), and kept outside every shape's
// outline, its own and those the other backing window draws. `part` keeps
// one of the two: where the compositor blurs every pixel that isn't clear,
// the shadows go to a window it doesn't blur (BlurBacking).
// The copies are keyed (KeyedModel): one coming or going adds or removes
// only its own, so the others aren't remade (and don't restart).
// Where the compositor blurs only what a window asks (niri:
// supports.blurRegion), it asks for its shapes alone, as drawn: with no
// alpha threshold there, the whole window would blur, its shadows too.
PanelWindow {
  id: backing
  // Every shape on its screen: it keeps a copy of each and draws its own
  // (`draws`), so the overlay opening builds and destroys none
  required property var shapes
  // It's the window over the overlay ("-overlay")
  property bool over: false
  // The overlay's windows exist and draw (BlurBacking.overlayWindows), and
  // the main window has given the Overlay-layer shapes up
  // (BlurBacking.overlayGivenUp): which window draws a shape
  property bool overlayWindows: false
  property bool overlayGivenUp: false
  // Shapes another backing window may draw over this one (the overlay's):
  // those it gives way to, erased where they stand, never drawn
  property var erasers: []
  // Whether it draws `shape` now (the other backing window on its screen
  // draws the rest; `over` names which window is asked about); its shadows
  // are cut by the shapes the other one draws all the same: a shadow never
  // falls on a surface joined to the one casting it
  function draws(shape, over = backing.over) {
    return over ? backing.overlayWindows && shape.overlayLayer : !(backing.overlayGivenUp && shape.overlayLayer);
  }
  // What it draws: "all", the "fills" alone or the "shadows" alone
  property string part: "all"
  // Whether shadows are cut by `union` rather than their own group (never
  // captured while it draws no shadows)
  readonly property bool cutByUnion: backing.part !== "fills" && (groups.count > 1 || backing.overlayWindows)

  // Which shadow a shape casts with: shapes of one look cast theirs
  // together; "none" for no shadow
  function shadowKey(shape) {
    const look = shape?.shadow ?? null;
    if (!look || !look.shadow)
      return "none";
    return [look.shadowColor, look.shadowSize].join("|");
  }

  // Its namespace and layer, set here so its LayerSlot can read them
  required property string layerNamespace
  property int stackLayer: WlrLayer.Top
  // Whether it draws (BlurManager.backingOn). Where the compositor stacks
  // by map order alone (SwayFX) it stays mapped while not (held), a pixel
  // drawing nothing, so it keeps its place under the chrome: mapped later
  // it would land over the bars and cover their content
  property bool wanted: true
  property bool held: true

  // Its watchdog has warned (once per window)
  property bool _warned: false
  // Chrome is backed here but this window isn't shown (a seam: the chrome
  // shows without its fill): a moment's grace, then it says so, once
  Timer {
    interval: 1000
    running: backing.wanted && backing.shapes.length > 0 && !layerSlot.shown
    onTriggered: {
      if (backing._warned)
        return;
      backing._warned = true;
      console.warn(`${backing.layerNamespace} on ${backing.screen?.name ?? ""}: chrome is backed but its backing window isn't shown`);
    }
  }

  visible: layerSlot.shown
  LayerSlot {
    id: layerSlot
    window: backing
    namespace: backing.layerNamespace
    layer: backing.stackLayer
    wanted: backing.wanted
    held: backing.held
  }

  // Drawn whenever backed, blurred only where the compositor is asked
  // (regionsOn). Its shapes as its blur region, where the compositor
  // blurs only that (supports.blurRegion): each shape's pieces as drawn,
  // at its place on the screen and cut to its clipRect; none while it
  // draws nothing
  readonly property bool regionBlur: CompositorManager.supports.blurRegion === true && backing.part !== "shadows" && backing.wanted && BlurManager.regionsOn(backing.screen)
  readonly property var regionPieces: backing.regionBlur ? [].concat(...backing.shapes.filter(shape => backing.draws(shape)).map(shape => backing._piecesOf(shape))) : []

  // reads: a shape's source (AttachedSurface, Rectangle, RoundedBorders)
  function _piecesOf(shape) {
    const src = shape?.source ?? null;
    if (!src || !shape.shown)
      return [];
    // None while its fill is drawn under the blur threshold, fading or
    // faded out (an AttachedSurface's `fade`, a dock fading as it hides, a
    // shape's `fade`, as a toast's or a menu tile's), or its fill's alpha,
    // BlurShape.color (an attached surface's own fillColor): the alpha the
    // copy draws, as BoxBlurRegion and Hyprland's ignore_alpha compare it
    if (Appearance.surfaceAlpha * shape.color.a * (shape.fade ?? 1) * (src.shownOpacity ?? 1) * (src.hostOpacity ?? 1) < Appearance.blurThreshold)
      return [];
    const clip = shape.clipRect ?? {
      "x": 0,
      "y": 0,
      "width": backing.width,
      "height": backing.height
    };
    if (shape.kind === "frame") {
      // The screen less the stroke's inner side, as frameMirror draws it
      return SurfaceOutline.placeRegion(src.blurPieces(backing.width, backing.height), 0, 0, clip);
    }
    const pieces = shape.kind === "rect" ? [
      {
        "x": 0,
        "y": 0,
        "width": src.width,
        "height": src.height,
        "topLeft": src.topLeftRadius,
        "topRight": src.topRightRadius,
        "bottomLeft": src.bottomLeftRadius,
        "bottomRight": src.bottomRightRadius
      }
    ] : src.blurPieces();
    return SurfaceOutline.placeRegion(pieces, shape.x, shape.y, clip);
  }

  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => backing.regionBlur ? blurRegion : null)
  BlurRegion {
    id: blurRegion
    pieces: backing.regionPieces
  }

  WlrLayershell.namespace: backing.layerNamespace
  WlrLayershell.layer: backing.stackLayer
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  mask: Region {}

  anchors {
    top: true
    bottom: !layerSlot.idle
    left: true
    right: !layerSlot.idle
  }
  implicitWidth: 1
  implicitHeight: 1

  // Shown as drawn, whatever Hyprland held on to (see FrameNudge)
  FrameNudge {
    id: nudge
  }

  // The shadows, under the fills
  Item {
    id: shadows
    anchors.fill: parent
    visible: backing.part !== "fills"
  }

  // Every shape's fill and stroke in painter's order, as the two captures
  // ChromeComposite reads (a window drawing only shadows draws neither): the
  // colour premultiplied, and the alpha in grey, each stroke blended over
  // what is under it. Sampled 1:1: the window's buffer in device pixels
  Copies {
    id: colorCopies
    screen: backing.screen
    shapes: backing.part !== "shadows" ? backing.shapes : []
    erasers: backing.part !== "shadows" ? backing.erasers : []
    draws: "chrome"
    drawsOnly: shape => backing.draws(shape)
    onChanged: nudge.burst()
  }
  Copies {
    id: alphaCopies
    screen: backing.screen
    shapes: backing.part !== "shadows" ? backing.shapes : []
    erasers: backing.part !== "shadows" ? backing.erasers : []
    draws: "chrome"
    drawsOnly: shape => backing.draws(shape)
    asAlpha: true
  }
  ShaderEffectSource {
    id: colorCapture
    anchors.fill: parent
    visible: false
    sourceItem: backing.part !== "shadows" && backing.shapes.length > 0 ? colorCopies : null
    hideSource: true
    smooth: false
    textureSize: Qt.size(Math.ceil(backing.width * backing.devicePixelRatio), Math.ceil(backing.height * backing.devicePixelRatio))
  }
  ShaderEffectSource {
    id: alphaCapture
    anchors.fill: parent
    visible: false
    sourceItem: backing.part !== "shadows" && backing.shapes.length > 0 ? alphaCopies : null
    hideSource: true
    smooth: false
    textureSize: colorCapture.textureSize
  }
  ChromeComposite {
    anchors.fill: parent
    colorSource: colorCapture
    alphaSource: alphaCapture
    visible: backing.part !== "shadows"
  }

  // Every shape, as the shadows' cut: each is kept outside them all,
  // so none falls on a surface joined to the one casting it. Captured
  // (and kept off screen) only once there are several groups or shapes
  // to cut by; never drawn otherwise (a fills-only window would draw the
  // other window's shapes over what they belong to)
  Item {
    id: unionShapes
    anchors.fill: parent
    visible: backing.cutByUnion

    // The other window's shapes, for the cut alone
    Item {
      id: cutShapes
      anchors.fill: parent
      visible: backing.overlayWindows

      // (none for a fills-only window, which never reads them)
      Copies {
        screen: backing.screen
        shapes: backing.part !== "fills" ? backing.shapes : []
        draws: "outline"
        drawsOnly: shape => backing.draws(shape, !backing.over)
        onChanged: nudge.burst()
      }
    }
  }
  ShaderEffectSource {
    id: union
    anchors.fill: parent
    visible: false
    sourceItem: backing.cutByUnion ? unionShapes : null
    hideSource: true
  }

  KeyedModel {
    id: groupModel
    keys: backing.shapes.map(shape => backing.shadowKey(shape)).filter((key, i, all) => all.indexOf(key) === i)
  }

  // The shapes casting one shadow: their outlines copied once and captured (a hidden layer isn't drawn, a
  // capture with hideSource is), drawn into `union` from the capture, and
  // casting from it
  Repeater {
    id: groups
    model: groupModel.model

    delegate: Item {
      id: group
      required property string key
      readonly property var members: backing.shapes.filter(shape => backing.shadowKey(shape) === group.key)
      readonly property var lead: group.members[0] ?? null
      anchors.fill: parent

      Item {
        id: shapes
        anchors.fill: parent

        Copies {
          screen: backing.screen
          shapes: group.members
          draws: "outline"
          drawsOnly: shape => backing.draws(shape)
          onChanged: nudge.burst()
        }
      }

      ShaderEffectSource {
        id: copied
        anchors.fill: parent
        visible: false
        sourceItem: shapes
        hideSource: true
      }

      ShaderEffect {
        property var source: copied
        parent: unionShapes
        anchors.fill: parent
        visible: backing.cutByUnion
      }

      SurfaceShadow {
        parent: shadows
        anchors.fill: parent
        visible: group.key !== "none" && group.lead !== null
        source: copied
        cut: true
        cutSource: backing.cutByUnion ? union : copied
        autoPaddingEnabled: false
        look: group.lead?.shadow ?? BarStyle.look
      }
    }
  }
}
