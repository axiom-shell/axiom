pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor

/**
 * Shared state machine for any "popout wrapper": open/close/reopen
 * queueing, switching in place, and centralized dismiss-on-hover-loss
 * timing.
 *
 * Concrete wrappers (BarPopouts, SubPopout, EdgePopout,
 * FloatingPopout, IntegratedEdgeMenu) use this as their root type and add
 * their own window, positioning, and content Loader as children, binding
 * `currentItem` to their Loader's item.
 *
 * Deliberately generic on (anchor, data) — no fixed signature per
 * subclass. If a subclass needs extra routing info (e.g. BarPopouts'
 * popout name), it travels as a field inside `data` rather than as an
 * extra positional argument, so this base never needs overriding.
 */
Item {
  id: root

  property var currentData: null
  property var currentAnchor: null
  property bool occupied: false
  property bool isClosing: false

  // Bind this in the subclass to your Loader's item, e.g.:
  //   currentItem: loader.item ?? null
  property Item currentItem: null

  property var pendingOpenData: null
  property var pendingOpenAnchor: null
  property bool hasPendingOpen: false

  // Hooks for a wrapper that can move an open popout to another payload in
  // place rather than closing it first (BarPopouts, to a neighbouring
  // widget): whether it will for (anchor, data), and what it does first,
  // calling `done` when ready (the payload waits as the pending open)
  property var canSwitchTo: (anchor, data) => false
  property var prepareSwitch: done => done()

  // Open and not on its way out
  readonly property bool isOpen: occupied && !isClosing

  // Opens with `data` as the payload ({ anchorItem } keeps it open while
  // that item is hovered), or restarts the countdown when already open
  function show(data) {
    if (isOpen) {
      updateDismissTimer();
      return;
    }
    safeOpenPopout(null, data ?? ({}));
  }

  function hide() {
    if (isOpen)
      requestDismiss();
  }

  // ---- Centralized dismiss logic ----
  // Content just exposes `hovered` (optionally folding in its own extra
  // "keep me alive" conditions, e.g. an active drag or an open submenu).
  // Timing and dismissal live here, once, for every popout type.
  // `keepAlive` lets a wrapper add hover sources of its own (e.g. an edge
  // trigger strip) without the content having to know about them.
  // dismissDelay/autoDismiss default to the content's values but can be
  // overridden by the wrapper.
  // The widget that opened the popout (`anchorItem` in the payload) counts
  // too, so the popout stays up while the pointer is still on it.
  property bool keepAlive: false
  readonly property bool anchorHovered: currentData?.anchorItem?.hovered ?? false
  // Hovered itself (its content or anchor), or kept alive by its wrapper
  readonly property bool ownHovered: (currentItem?.hovered ?? false) || anchorHovered || keepAlive
  // The window showing it
  property var window: null
  // A wrapper with a submenu (BarPopouts, EdgePopout) sets its
  // SubmenuHost: the submenu (SubPopout), which a PopoutAnchor in its
  // content opens, and the side it opens to (the tray reads it)
  property var submenuHost: null
  readonly property var submenu: root.submenuHost?.submenu ?? null
  readonly property bool openToLeft: root.submenuHost?.openToLeft ?? false
  // Its submenu open keeps it up too
  property bool childOpen: root.submenuHost?.open ?? false
  readonly property bool contentHovered: ownHovered || childOpen
  property int dismissDelay: currentItem?.dismissDelay ?? PopoutsConfig.dismissDelay
  property bool autoDismiss: currentItem?.autoDismiss ?? true

  onContentHoveredChanged: updateDismissTimer()

  // A popup that maps over its anchor takes the pointer before its input
  // mask applies. Once it does, the pointer is back over
  // the bar, but Hyprland sends the bar no enter until it moves, so nothing
  // reads as hovered and the popout would close under a still pointer. So
  // a popout notes the cursor when its anchor loses hover, and before
  // dismissing checks it: if it hasn't moved, hover was lost under it, not
  // by leaving, and the popout stays until the next hover change (or the
  // cursor moving, checked every parkCheckInterval). Only the anchor's: any
  // other hover lost (the content's, a submenu closing, `keepAlive`) is
  // nothing mapping under the pointer, and a pointer still since leaving
  // would otherwise hold the popout open. Hovering anything again forgets it.
  property var _lostCursor: null
  readonly property int parkCheckInterval: 1000

  onAnchorHoveredChanged: {
    if (!anchorHovered && occupied && !isClosing)
      _noteLostCursor();
  }

  function _noteLostCursor() {
    _lostCursor = null;
    const data = currentData;
    if (!data?.anchorItem)
      return;
    CompositorManager.withCursorPos(pos => {
      if (root.currentData === data && !root.contentHovered)
        root._lostCursor = pos;
    });
  }

  function _tryDismiss() {
    if (!occupied || isClosing || contentHovered)
      return;
    const lost = _lostCursor;
    if (lost === null) {
      requestDismiss();
      return;
    }
    const data = currentData;
    CompositorManager.withCursorPos(pos => {
      // Reopened, closed or hovered again meanwhile
      if (root.currentData !== data || !root.occupied || root.isClosing || root.contentHovered)
        return;
      if (pos !== null && pos.x === lost.x && pos.y === lost.y)
        parkTimer.restart();
      else
        root.requestDismiss();
    });
  }

  function updateDismissTimer() {
    // Nothing to dismiss while closed (content can stay loaded and hover
    // sources can change without the popout being open)
    if (!occupied || !autoDismiss) {
      dismissTimer.stop();
      parkTimer.stop();
      return;
    }
    parkTimer.stop();
    if (contentHovered) {
      dismissTimer.stop();
      _lostCursor = null;
    } else {
      dismissTimer.restart();
    }
  }

  // Subclasses that need to do something extra on dismiss connect via:
  //   onAboutToDismiss: { ... }
  signal aboutToDismiss

  function requestDismiss() {
    parkTimer.stop();
    aboutToDismiss();
    closePopout();
  }
  // ---- end centralized dismiss logic ----

  function closePopout() {
    if (isClosing)
      return;
    isClosing = true;
    closeDelayTimer.restart();
  }

  function openPopout(anchor, data) {
    if (isClosing)
      return;
    // Drop any stale countdown from whatever was here before. This must
    // come first: setting `occupied` loads the content synchronously, and
    // stopping afterwards cancelled the countdown its onLoaded started,
    // leaving a popout the pointer never entered open forever.
    dismissTimer.stop();
    parkTimer.stop();
    _lostCursor = null;
    currentAnchor = anchor;
    currentData = data;
    occupied = true;
    updateDismissTimer();
  }

  function safeOpenPopout(anchor, data) {
    if (occupied && canSwitchTo(anchor, data)) {
      pendingOpenData = data;
      pendingOpenAnchor = anchor;
      hasPendingOpen = true;
      // Leaving is called off: it stays to take the new payload
      closeDelayTimer.stop();
      isClosing = false;
      prepareSwitch(() => root._openPending());
    } else if (occupied && !isClosing) {
      pendingOpenData = data;
      pendingOpenAnchor = anchor;
      hasPendingOpen = true;
      requestDismiss();
    } else if (!occupied && !isClosing) {
      openPopout(anchor, data);
    } else {
      pendingOpenData = data;
      pendingOpenAnchor = anchor;
      hasPendingOpen = true;
    }
  }

  Timer {
    id: dismissTimer
    interval: root.dismissDelay
    repeat: false
    onTriggered: root._tryDismiss()
  }

  Timer {
    id: parkTimer
    interval: root.parkCheckInterval
    repeat: false
    onTriggered: root._tryDismiss()
  }

  Timer {
    id: closeDelayTimer
    interval: Appearance.animNormal
    repeat: false
    onTriggered: {
      root.occupied = false;
      root.isClosing = false;
      root.currentAnchor = null;
      root.currentData = null;
      root._lostCursor = null;
      root._openPending();
    }
  }

  // Opens the pending payload, unless it's closing (which opens it once
  // closed)
  function _openPending() {
    if (!root.hasPendingOpen || root.isClosing)
      return;
    root.hasPendingOpen = false;
    const data = root.pendingOpenData;
    const anchor = root.pendingOpenAnchor;
    root.pendingOpenData = null;
    root.pendingOpenAnchor = null;
    root.openPopout(anchor, data);
  }
}
