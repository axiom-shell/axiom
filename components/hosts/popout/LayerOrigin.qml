pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor

// Where a layer-shell `window` is on its screen, as LayerManager works it
// out from how every window there asks to be laid out (and reports this
// one's): for surfaces whose fill the blur window draws, the joins in the
// border's stroke and popouts' footprints (PopoutClaim). A window that
// reserves space has an origin only while mapped; one that doesn't has
// one before it maps, where it will go.
QtObject {
  id: root

  required property var window
  required property string namespace
  // The window's edge: where it's estimated to be while it has no origin
  property int edge: Bar.Top
  // Its WlrLayershell.layer (an attached property, unreadable from here)
  property int layer: WlrLayer.Top
  // Where it most likely starts along its edge while it has no origin,
  // when its owner knows better than centred (a bar, BarManager.
  // barStartOn); NaN for centred
  property real estimatedStart: NaN

  // Its id in LayerManager, taken once
  property int _uid: 0
  readonly property string _output: root.window?.screen?.name ?? ""

  // How it asks to be laid out (LayerArrange.arrange's surfaces)
  readonly property var _spec: {
    const w = root.window;
    if (!w || root._output === "")
      return null;
    const a = w.anchors, m = w.margins;
    const anchors = {
      "left": !!a.left,
      "right": !!a.right,
      "top": !!a.top,
      "bottom": !!a.bottom
    };
    const vertical = anchors.left !== anchors.right;
    const zone = w.exclusionMode === ExclusionMode.Ignore ? -1 : w.exclusionMode === ExclusionMode.Auto ? (vertical ? w.implicitWidth : w.implicitHeight) : w.exclusiveZone;
    return {
      "output": root._output,
      "namespace": root.namespace,
      "layer": LayerManager.layerName(root.layer),
      "anchors": anchors,
      "margins": {
        "left": m.left,
        "right": m.right,
        "top": m.top,
        "bottom": m.bottom
      },
      // Stretched between the edges it's anchored to on both sides
      "w": anchors.left && anchors.right ? 0 : w.implicitWidth,
      "h": anchors.top && anchors.bottom ? 0 : w.implicitHeight,
      "zone": zone,
      "mapped": w.visible
    };
  }
  on_SpecChanged: {
    if (root._uid > 0)
      LayerManager.report(root._uid, root._spec);
  }
  Component.onCompleted: {
    root._uid = LayerManager.register();
    LayerManager.report(root._uid, root._spec);
  }
  Component.onDestruction: LayerManager.report(root._uid, null)

  readonly property var _rect: LayerManager.rectOf(root._uid, root._output)
  readonly property var origin: root._rect ? Qt.point(root._rect.x, root._rect.y) : null

  // Where it is, else where it most likely is: on its edge, centred along
  // it (what's reserved at either end roughly balancing). Close enough for
  // which popouts overlap (PopoutManager), never for drawing.
  readonly property point placed: root.origin ?? root._estimate
  readonly property point _estimate: {
    const sw = root.window?.screen?.width ?? 0, sh = root.window?.screen?.height ?? 0;
    const w = root.window?.width ?? 0, h = root.window?.height ?? 0;
    const vertical = root.edge === Bar.Left || root.edge === Bar.Right;
    const along = isNaN(root.estimatedStart) ? ((vertical ? sh - h : sw - w) / 2) : root.estimatedStart;
    return Qt.point(vertical ? (root.edge === Bar.Right ? sw - w : 0) : along, vertical ? along : (root.edge === Bar.Bottom ? sh - h : 0));
  }

  // Known, or given up on: a surface the blur window backs waits for this
  // before it shows (else its first frames fill and shadow themselves
  // beside backed ones), but never longer than a moment (a window on a
  // screen LayerManager doesn't lay out has no origin). Timed from when
  // the origin went missing, not from mapping: an edge popout waits for
  // this before its window maps.
  readonly property bool settled: root.origin !== null || root._timedOut
  property bool _timedOut: false
  property Timer _timeout: Timer {
    interval: 400
    running: root.origin === null && root.window !== null
    onTriggered: root._timedOut = true
  }
  onOriginChanged: {
    if (root.origin !== null)
      root._timedOut = false;
  }
}
