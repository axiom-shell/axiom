pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core

// Which edge menus (EdgeMenusConfig) are open and which are pinned. The
// menus themselves (shell/EdgeMenus) follow this and report back when they
// close on their own. Kept across QML reloads, so a reload doesn't close an
// integrated menu and reflow the windows. Pins are also saved to
// $XDG_STATE_HOME/axiom/ui/edgemenus.json, and a pinned menu opens again when qs starts.
// The layouts editor's working copy of EdgeMenus is OverlayManager.menus
// (EdgeMenuEditor).
//
//   axiom ipc edgeMenu toggle <id>
Singleton {
  id: root

  // { id: true } for each open / pinned menu
  readonly property var openMenus: root._parse(_run.open)
  readonly property var pinnedMenus: root._parse(_run.pinned)

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
  // menu, or one not yet reported) its padding all round
  function frameOf(menu) {
    const screenName = EdgeMenusConfig.screenFor(menu)?.name ?? "";
    const live = root.frames[menu?.id ?? ""];
    if (live && live.screen === screenName)
      return live;
    const pad = Appearance.borderWidth + EdgeMenusConfig.paddingOf(menu);
    return {
      "screen": screenName,
      "startPad": pad,
      "endPad": pad,
      "across": pad,
      "before": 0,
      "after": pad,
      "reserves": menu?.mode === "integrated"
    };
  }

  PersistentProperties {
    id: _run
    reloadableId: "axiomEdgeMenus"
    // JSON lists of ids
    property string open: "[]"
    property string pinned: "[]"
    // False only on the first load after qs starts
    property bool started: false

    onLoaded: {
      if (_run.started)
        return;
      _run.started = true;
      const pinned = root._state.load({}).pinned;
      if (!Array.isArray(pinned))
        return;
      const ids = pinned.filter(id => EdgeMenusConfig.menuById(id));
      _run.pinned = JSON.stringify(ids);
      _run.open = JSON.stringify(ids);
    }
  }

  readonly property var _state: StateManager.createStateHandler("edgemenus")

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

  function _set(map, id, on) {
    const ids = Object.keys(map).filter(key => key !== id);
    if (on)
      ids.push(id);
    return JSON.stringify(ids);
  }

  // True for a menu held open by the editor: it ignores closeOnLeave and
  // outside clicks, as a pinned one does (previewing a submenu menu holds
  // the menu it opens from, previewParent)
  function isHeld(id) {
    return root.isPinned(id) || (id !== "" && (OverlayManager.menus.previewing === id || OverlayManager.menus.previewParent === id));
  }

  function isOpen(id) {
    return root.openMenus[id] === true;
  }
  function isPinned(id) {
    return root.pinnedMenus[id] === true;
  }

  // A module's host (Card/Panel.host) is an edge menu it can pin
  function canPin(host) {
    return host?.kind === "edgeMenu" && !!host.id && !host.submenu;
  }

  function _exists(id) {
    if (EdgeMenusConfig.menuById(id))
      return true;
    console.warn("[EdgeMenuManager] No edge menu with id", id);
    return false;
  }

  // `kind`: how it ranks (claimKinds), "menu" when left out
  function open(id, anchor, kind) {
    if (!root._exists(id))
      return;
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

  // Menus opened for something outside them (the launcher, IPC) that take
  // the cursor: the menu warps it into its box once shown
  // (CompositorManager.warpCursorToLayer), and doesn't close on leave until
  // it has been hovered. Not kept across reloads.
  property var revealing: ({})

  // Opens a menu and moves the cursor into it, so one that closes when the
  // pointer leaves stays open
  function reveal(id) {
    if (!root._exists(id))
      return;
    root.revealing = root._parse(root._set(root.revealing, id, true));
    root.open(id, null);
  }

  // The menu was hovered, or closed
  function revealDone(id) {
    if (root.revealing[id] === true)
      root.revealing = root._parse(root._set(root.revealing, id, false));
  }

  function close(id) {
    if (!root.isOpen(id))
      return;
    _run.open = root._set(root.openMenus, id, false);
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
    target: "edgeMenu"

    function open(id: string): void {
      root.open(id, null);
    }

    function close(id: string): void {
      root.close(id);
    }

    function toggle(id: string): void {
      root.toggle(id, null);
    }

    function pin(id: string): void {
      root.setPinned(id, true);
    }

    function unpin(id: string): void {
      root.setPinned(id, false);
    }

    // Opens the layouts editor on the edge menus
    function edit(): void {
      OverlayManager.editMenus();
      ShellManager.openOverlayPage("Layouts");
    }

    function list(): string {
      return EdgeMenusConfig.menus.map(menu => `${menu.id}${root.isOpen(menu.id) ? " (open)" : ""}${root.isPinned(menu.id) ? " (pinned)" : ""}`).join("\n");
    }
  }
}
