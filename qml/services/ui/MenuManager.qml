pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

// Which menus (MenusConfig) are open and which are pinned. The
// menus themselves (shell/Menus) follow this and report back when they
// close on their own. Kept across QML reloads, so a reload doesn't close an
// integrated menu and reflow the windows. Pins are also saved to
// $XDG_STATE_HOME/axiom/ui/menus.json (read from its old name,
// edgemenus.json, while it isn't there), and a pinned menu opens again
// when qs starts.
// An edge menu with `popOutButton` can pop out (popOut): it shows in the
// free host where its box was, held open as if pinned, until it closes,
// which docks it (dock); nothing of it is kept, and a reload docks it
// closed.
// The layouts editor's working copy of Menus is OverlayManager.menus
// (MenuEditor).
//
//   axiom ipc menu toggle <id>   (edgeMenu: its old name, still answered)
Singleton {
  id: root

  // { id: true } for each open / pinned menu
  readonly property var openMenus: root._parse(_run.open)
  readonly property var pinnedMenus: root._parse(_run.pinned)
  // { id: { screen, x, y } } for each popped-out menu: its box's top-left
  // on its screen as it popped out (FreeMenuPlace.spot's popOut)
  readonly property var poppedOut: root._parseObject(_run.poppedOut)

  // What opened each menu (a bar button), which keeps a floating menu open
  // while hovered, as a bar popout's anchor does. Not kept across reloads.
  property var anchors: ({})
  // How each open menu ranks in PopoutManager (its PopoutClaim's kind):
  // "bar" when a widget's PopoutAnchor opened it as that widget's popout,
  // else "menu". Set with its anchor, as it opens.
  property var claimKinds: ({})

  // Where each running menu's modules can sit on its screen, by id, as the
  // menu reports it (IntegratedEdgeMenu, FloatingEdgeMenu), for the
  // layouts editor. In px: { screen (its name), startPad, endPad (the
  // least room between the modules and the edge's ends), across (from the
  // screen edge to the modules), before (across, taken by what's on the
  // edge outside the menu: bars, the border), after (from the modules to
  // the menu's inner side), reserves (whether the menu reserves its strip) }
  readonly property var frames: root._frames
  property var _frames: ({})

  function setFrame(id, frame) {
    if (id && JSON.stringify(root._frames[id]) !== JSON.stringify(frame))
      root._frames = Utils.withEntry(root._frames, id, frame);
  }

  function clearFrame(id, screenName) {
    if (root._frames[id]?.screen === screenName)
      root._frames = Utils.withEntry(root._frames, id, undefined);
  }

  // A menu's frame (see `frames`): its running one's, else (a disabled
  // menu, or one not yet reported) its stroke (an integrated one's frame,
  // as IntegratedEdgeMenu's) and padding all round
  function frameOf(menu) {
    const screenName = MenusConfig.screenFor(menu)?.name ?? "";
    const live = root.frames[menu?.id ?? ""];
    if (live && live.screen === screenName)
      return live;
    const integrated = menu?.placement === "strip";
    const pad = (integrated ? MenusConfig.outerPadOf(menu) : Appearance.borderWidth) + PopoutsConfig.padding;
    return {
      "screen": screenName,
      "startPad": pad,
      "endPad": pad,
      "across": pad,
      "before": 0,
      "after": pad + (integrated ? MenusConfig.innerStroke : 0),
      "reserves": integrated
    };
  }

  PersistentProperties {
    id: _run
    reloadableId: "axiomMenus"
    // JSON lists of ids
    property string open: "[]"
    property string pinned: "[]"
    // { id: { screen, x, y } }: the popped-out menus, at the spot (their
    // box's top-left) they popped out at (kept here only so a reload can
    // dock them, closed)
    property string poppedOut: "{}"
    // False only on the first load after qs starts
    property bool started: false

    onLoaded: {
      // A reload docks a popped-out menu, closed (read from the text: the
      // maps bound to it aren't up to date yet)
      const popped = Object.keys(root._parseObject(_run.poppedOut));
      if (popped.length > 0) {
        _run.open = JSON.stringify(Object.keys(root._parse(_run.open)).filter(id => !popped.includes(id)));
        _run.poppedOut = "{}";
      }
      if (_run.started)
        return;
      _run.started = true;
      const pinned = root._loadPins();
      if (!Array.isArray(pinned))
        return;
      const ids = pinned.filter(id => MenusConfig.menuById(id));
      _run.pinned = JSON.stringify(ids);
      _run.open = JSON.stringify(ids);
    }
  }

  readonly property var _state: StateManager.createStateHandler("menus")
  // The file's name before edge menus became menus (v104)
  readonly property var _oldState: StateManager.createStateHandler("edgemenus")

  // The saved pins: menus.json's, else (once: it's written at once) the
  // old file's
  function _loadPins() {
    const saved = root._state.load(null);
    if (saved)
      return saved.pinned;
    const old = root._oldState.load(null);
    if (!old)
      return undefined;
    root._state.save({
      "pinned": Array.isArray(old.pinned) ? old.pinned : []
    });
    return old.pinned;
  }

  // Where each free menu was dragged to, for this login session: { id:
  // { screen, x, y (its box's top-left in px on that screen), anchor (the
  // freeAnchor it was dragged from, FreeMenuPlace.anchorKey) } }. A bind,
  // IPC or a pin reopening opens it there instead of at its freeAnchor
  // (FreeMenuPlace.spot), until its freeAnchor changes, its screen goes,
  // or it's reset. Kept in $XDG_RUNTIME_DIR (StateManager's session
  // handler): through qs reloads and restarts, gone at logout; never in
  // config.
  property var positions: ({})
  readonly property var _session: StateManager.createSessionHandler("menu-positions")
  Component.onCompleted: {
    const saved = root._session.load({}).positions;
    root.positions = saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {};
  }

  // A free menu's box was dropped at `spot` ({ screen, x, y }), opened on
  // its own (FreeMenuPlace.keepsDrag): it opens there this session
  function storePosition(id, spot) {
    const menu = MenusConfig.menuById(id);
    if (!MenusConfig.isFree(menu) || !spot)
      return;
    root._savePositions(Utils.withEntry(root.positions, id, {
      "screen": spot.screen,
      "x": Math.round(spot.x),
      "y": Math.round(spot.y),
      "anchor": FreeMenuPlace.anchorKey(menu.freeAnchor)
    }));
  }

  // Back to its freeAnchor (the menu's Reset position, IPC resetPosition):
  // its session spot forgotten, and an open one dragged since it opened
  // goes back too (positionReset)
  signal positionReset(string id)
  function resetPosition(id) {
    if (root.positions[id] !== undefined)
      root._savePositions(Utils.withEntry(root.positions, id, undefined));
    root.positionReset(id);
  }

  function _savePositions(positions) {
    root.positions = positions;
    root._session.save({
      "positions": positions
    });
  }

  function _parse(json) {
    try {
      return JSON.parse(json).reduce((map, id) => {
        map[id] = true;
        return map;
      }, {});
    } catch (e) {
      return {};
    }
  }

  function _parseObject(json) {
    try {
      const value = JSON.parse(json);
      return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    } catch (e) {
      return {};
    }
  }

  function _set(map, id, on) {
    const ids = Object.keys(map).filter(key => key !== id);
    if (on)
      ids.push(id);
    return JSON.stringify(ids);
  }

  // True for a menu held open by the editor or popped out: it ignores
  // closeOnLeave and outside clicks, as a pinned one does (previewing a
  // free menu holds the menu it opens from, previewParent)
  function isHeld(id) {
    return root.isPinned(id) || root.isPoppedOut(id) || (id !== "" && (OverlayManager.menus.previewing === id || OverlayManager.menus.previewParent === id));
  }

  function isOpen(id) {
    return root.openMenus[id] === true;
  }
  function isPinned(id) {
    return root.pinnedMenus[id] === true;
  }
  function isPoppedOut(id) {
    return root.poppedOut[id] !== undefined;
  }

  // Asked to pop out (the menu's pop-out button): its edge host answers
  // with popOut, giving its box's spot
  signal popOutRequested(string id)

  // The pop-out button: an open edge menu that can pop out
  // (MenusConfig.canPopOut) asks its host to; a popped-out one docks,
  // closed
  function togglePoppedOut(id) {
    if (root.isPoppedOut(id))
      root.dock(id);
    else if (root.isOpen(id) && MenusConfig.canPopOut(MenusConfig.menuById(id)))
      root.popOutRequested(id);
  }

  // Shows open menu `id` in the free host, its box's top-left at `spot`
  // ({ screen, x, y }): its edge host goes once the free one has shown
  // (FreeMenuPlace.hosts)
  function popOut(id, spot) {
    if (!root.isOpen(id) || !spot || !MenusConfig.canPopOut(MenusConfig.menuById(id)))
      return;
    _run.poppedOut = JSON.stringify(Utils.withEntry(root.poppedOut, id, {
      "screen": spot.screen,
      "x": Math.round(spot.x),
      "y": Math.round(spot.y)
    }));
  }

  // Closes a popped-out menu, back on its edge: every close of one comes
  // here (its close button, the pop-out button, a bind or bar Button
  // toggle, IPC close, Escape). Closed first, so its edge host comes back
  // closed
  function dock(id) {
    if (!root.isPoppedOut(id))
      return;
    _run.open = root._set(root.openMenus, id, false);
    _run.poppedOut = JSON.stringify(Utils.withEntry(root.poppedOut, id, undefined));
  }

  // A module's host (Card/Panel.host) is an edge menu it can pin: an
  // edge, strip or free menu in its own host, not one shown in another
  // menu's submenu
  function canPin(host) {
    return host?.kind === "menu" && !!host.id && !host.submenu;
  }

  function _exists(id) {
    if (MenusConfig.menuById(id))
      return true;
    console.warn("[MenuManager] No menu with id", id);
    return false;
  }

  // `kind`: how it ranks (claimKinds), "menu" when left out
  // A popped-out menu stays where it is (no second copy), only brought
  // forward if a popout covered it
  function open(id, anchor, kind) {
    if (!root._exists(id))
      return;
    if (root.isPoppedOut(id)) {
      root.engageRequested(id);
      return;
    }
    const anchors = Object.assign({}, root.anchors);
    anchors[id] = anchor ?? null;
    root.anchors = anchors;
    const kinds = Object.assign({}, root.claimKinds);
    kinds[id] = kind ?? "menu";
    root.claimKinds = kinds;
    if (root.isOpen(id))
      root.engageRequested(id);
    _run.open = root._set(root.openMenus, id, true);
  }

  // Asked for while already open (a keybind, a bar Button, IPC): its host
  // takes it as engaged (EdgePopout.engage), so a pinned one ranks as a
  // menu again and comes forward over what covered it (PopoutManager)
  signal engageRequested(string id)
  // Open, but given way to a popout over it (pinned or previewing)
  function covered(id) {
    return PopoutManager.entry("menu:" + id)?.phase === "yielded";
  }

  // Menus opened for something outside them (the launcher, IPC): an edge
  // or strip menu warps the cursor into its box once shown
  // (CompositorManager.warpCursorToLayer; a free menu leaves it be), and
  // none closes on leave until it has been hovered. Not kept across
  // reloads.
  property var revealing: ({})

  // Opens a menu and moves the cursor into it (not a free menu's), so one
  // that closes when the pointer leaves stays open until it's hovered
  function reveal(id) {
    if (!root._exists(id) || root.isPoppedOut(id))
      return;
    root.revealing = root._parse(root._set(root.revealing, id, true));
    root.open(id, null);
  }

  // The menu was hovered, or closed
  function revealDone(id) {
    if (root.revealing[id] === true)
      root.revealing = root._parse(root._set(root.revealing, id, false));
  }

  // A popped-out one docks
  function close(id) {
    if (root.isPoppedOut(id)) {
      root.dock(id);
      return;
    }
    if (!root.isOpen(id))
      return;
    _run.open = root._set(root.openMenus, id, false);
  }

  // A menu's close button: closes it, unpinned first, so it stays
  // closed (a pin reopens it at the next start)
  function closeUnpinned(id) {
    if (root.isPinned(id))
      root.setPinned(id, false);
    root.close(id);
  }

  function toggle(id, anchor) {
    // Covered, it's brought forward rather than closed
    if (root.covered(id))
      root.open(id, anchor);
    else if (root.isOpen(id))
      root.close(id);
    else
      root.open(id, anchor);
  }

  function setPinned(id, pinned) {
    _run.pinned = root._set(root.pinnedMenus, id, pinned);
    root._state.save({
      "pinned": JSON.parse(_run.pinned)
    });
  }

  function togglePinned(id) {
    root.setPinned(id, !root.isPinned(id));
  }

  property IpcTarget _ipc: IpcTarget {
    id: ipc
    target: "menu"

    // Opened from outside it (a bind, a script), a closed menu is revealed,
    // so one that closes when the pointer leaves stays open
    function open(id: string): void {
      if (root.isOpen(id))
        root.open(id, null);
      else
        root.reveal(id);
    }

    function close(id: string): void {
      root.close(id);
    }

    function toggle(id: string): void {
      if (root.isOpen(id) && !root.covered(id))
        root.close(id);
      else
        ipc.open(id);
    }

    // A free menu opened by a bind or a script goes back to its freeAnchor
    // (it was dragged elsewhere this session)
    function resetPosition(id: string): void {
      root.resetPosition(id);
    }

    function pin(id: string): void {
      root.setPinned(id, true);
    }

    function unpin(id: string): void {
      root.setPinned(id, false);
    }

    // Opens the layouts editor on the menus
    function edit(): void {
      OverlayManager.editMenus();
      ShellManager.openOverlayPage("Layouts");
    }

    function list(): string {
      return MenusConfig.menus.map(menu => `${menu.id}${root.isOpen(menu.id) ? " (open)" : ""}${root.isPinned(menu.id) ? " (pinned)" : ""}${root.isPoppedOut(menu.id) ? " (popped out)" : ""}`).join("\n");
    }
  }

  // The target's old name (edge menus became menus, v104), for binds and
  // scripts written before: each call is the menu target's
  property IpcTarget _oldIpc: IpcTarget {
    target: "edgeMenu"

    function open(id: string): void {
      ipc.open(id);
    }

    function close(id: string): void {
      ipc.close(id);
    }

    function toggle(id: string): void {
      ipc.toggle(id);
    }

    function resetPosition(id: string): void {
      ipc.resetPosition(id);
    }

    function pin(id: string): void {
      ipc.pin(id);
    }

    function unpin(id: string): void {
      ipc.unpin(id);
    }

    function edit(): void {
      ipc.edit();
    }

    function list(): string {
      return ipc.list();
    }
  }
}
