pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods
import qs.components.reusable

// Puts a surface's pill (or island) stretch (EdgeAttach.place's `stretch`)
// on the bar it stands on (`container`, a BarContainer) under its own
// owner key, and takes it off again when it clears, the bar changes or
// this goes. Written by hand rather than by a Binding: its restore on
// deactivation brought back a stale stretch.
//
// The pace is the surface's own: the pill grows out to the stretch
// (`progress`, animFast) before the surface slides out onto it (`ready`),
// and draws back once the surface has gone (the stretch cleared), so the
// two never drift apart. The bar draws what it's sent, as sent: it
// animates none of it. A stretch changing while it's out (a switch in
// place, a resize) glides there.
QtObject {
  id: root

  property var container: null
  property var stretch: null
  // Where the surface covers the pill's (or island's) far stroke, along
  // the bar ({ start, end }), left open there (BarContainer.setRequest)
  property var opening: null
  // A pill asked to run from an end of the bar ({ atStart, to, straight },
  // BarLayout.endReaches), grown there if there's none: a surface joining
  // this bar from the perpendicular edge. Sent as given: it follows the
  // surface along its slide itself (PillBarJoin), so it holds nothing back.
  property var endReach: null
  // Unique per surface on a bar (a bar has one popout host, and any number
  // of edge popouts on its edge)
  required property string owner
  // Whether its surface is out over the stroke it stands on, sent with the
  // stretch (`covered`, BarContainer._flushEnds). Kept apart from `stretch`:
  // it follows the slide, which waits on `ready`, which reads `stretch`
  property bool covered: true
  // The stretch follows its surface along a slide by itself (a submenu's
  // pill reach, sent as its outer wall is drawn): shown as sent, at once
  property bool tracks: false

  // Whether its surface is to show (open, not closing): set by the host
  property bool open: false
  // Whether the pill has grown out to the stretch, so the surface may slide
  // out onto it. Once ready it holds while the surface stays open, so a
  // stretch changing meanwhile (a switch in place, a resize) never pulls
  // the surface back.
  readonly property bool ready: root._latched || (root._armed && root._readyNow)
  readonly property bool _readyNow: !root.container || !root.stretch || root.progress >= 1
  // Open for a turn of the event loop: a host's stretch comes in with its
  // content, in the same pass that opens it, so it's judged only after
  property bool _armed: false
  property bool _latched: false
  function _relatch() {
    // Gone meanwhile
    if (!root)
      return;
    if (!root.open) {
      root._armed = false;
      root._latched = false;
    } else if (root._armed && root._readyNow) {
      root._latched = true;
    }
  }
  onOpenChanged: {
    if (!root.open) {
      root._relatch();
      return;
    }
    // One sent just before it opened again, while drawing back
    root._take();
    Qt.callLater(() => {
      if (!root || !root.open)
        return;
      root._armed = true;
      root._relatch();
    });
  }
  // Later: it changes while `ready` is being evaluated
  on_ReadyNowChanged: Qt.callLater(root._relatch)

  // How far out the pill is toward the stretch it shows (0..1): out while
  // there's a stretch, back once it clears
  property real progress: root.stretch && root.container ? 1 : 0
  Glide on progress {
    enabled: !root.tracks
  }
  // Its ends glide to a new stretch once out: off where the surface's box
  // eases its own size (an edge popout's), so the pill follows it as sent
  // rather than chasing it with a second ease
  property bool glides: true
  // The stretch it shows: the one asked for, kept while it draws back
  // after that clears; its ends glide to a new one once out (`_settled`)
  property var _shown: null
  property real _shownStart: 0
  property real _shownEnd: 0
  readonly property bool _settled: root.progress >= 1 && !root.tracks
  Glide on _shownStart {
    enabled: root._settled && root.glides
  }
  Glide on _shownEnd {
    enabled: root._settled && root.glides
  }
  // A closing surface never moves, so neither does its stretch: one sent
  // while it closes is left out (its content unloading may move its box
  // for a pass, which drew the pill back toward another one), unless it
  // tracks its surface or nothing shows yet
  function _take() {
    if (!root.stretch || !root.open && !root.tracks && root._shown)
      return;
    root._shown = root.stretch;
    root._shownStart = root.stretch.start;
    root._shownEnd = root.stretch.end;
  }
  onStretchChanged: root._take()
  onProgressChanged: {
    if (root.progress <= 0 && !root.stretch)
      root._shown = null;
  }
  // As drawn: from the pill's own span out to the stretch, `progress` of
  // the way (EdgeAttach.progressStretch)
  readonly property var _drawn: {
    const shown = root._shown;
    if (!shown)
      return null;
    const rects = root.container?.pillRects ?? [];
    const rest = rects[BarLayout.pillIndex(rects, shown)] ?? null;
    return EdgeAttach.progressStretch(rest, Object.assign({}, shown, {
      "start": root._shownStart,
      "end": root._shownEnd,
      "covered": root.covered
    }), root.progress);
  }

  property var _target: null
  function _clear() {
    try {
      root._target?.setRequest(root.owner, null);
    } catch (e) {
      // The bar went first (a reload)
    }
    root._target = null;
  }
  function _push() {
    // Gone meanwhile
    if (!root)
      return;
    const target = root._drawn || root.opening || root.endReach ? root.container : null;
    if (root._target !== target)
      root._clear();
    if (!target)
      return;
    root._target = target;
    target.setRequest(root.owner, {
      "stretch": root._drawn,
      "opening": root.opening,
      "endReach": root.endReach
    });
  }
  // At the end of the pass: what it sends reshapes the pills it reads
  // (pillRects), and several changes in one pass go as one
  on_DrawnChanged: Qt.callLater(root._push)
  onOpeningChanged: Qt.callLater(root._push)
  onEndReachChanged: Qt.callLater(root._push)
  onContainerChanged: Qt.callLater(root._push)
  Component.onDestruction: root._clear()
}
