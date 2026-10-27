pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

// The docks' shared state and actions (the docks themselves are
// shell/Dock): which apps a dock shows on a screen (its pinned ones, then
// running ones, windows grouped by desktop entry), what a click does
// (launch, focus, cycle), pinning (written to Dock.docks at once), whether
// a window covers a dock (intellihide), and the `dock` IPC target.
QtObject {
  id: root

  // Always-shown docks hidden by hand ({ id: true }), shared by every
  // screen's copy
  property var hidden: ({})

  // A hover dock should slide in, or out (every screen's copy of it)
  signal revealRequested(string id)
  signal concealRequested(string id)
  signal toggleRequested(string id)

  // Window class -> desktop entry id, for the classes that have one
  property var _classCache: ({})

  // An app's key: its desktop entry id, else its window class
  function appKey(win) {
    const cls = win.appId || win.initialAppId || "";
    if (!cls)
      return "";
    const cached = root._classCache[cls];
    if (cached)
      return cached;
    const entry = DesktopEntries.heuristicLookup(cls);
    if (!entry)
      return cls;
    root._classCache[cls] = entry.id;
    return entry.id;
  }

  function entryFor(key) {
    return DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key);
  }

  function iconFor(key, win) {
    const entry = root.entryFor(key);
    if (entry?.icon)
      return Quickshell.iconPath(entry.icon, "application-x-executable");
    return IconResolver.resolveWindowIcon(win?.appId ?? key, win?.title ?? "");
  }

  function nameFor(key, win) {
    return root.entryFor(key)?.name || win?.appId || key;
  }

  // The dock's items on a screen ([{ key, pinned, windows }], see
  // DockLayout.buildItems), windows counted by its windowScope
  function itemsFor(dock, screen) {
    if (!dock)
      return [];
    const output = CompositorManager.outputFor(screen);
    const workspaceId = output?.activeWorkspaceId ?? -1;
    const windows = CompositorManager.windows.filter(w => DockLayout.inScope(w, dock.running.scope, output?.name ?? "", workspaceId));
    return DockLayout.buildItems(DockConfig.pinnedOf(dock), windows, w => root.appKey(w), dock.running.show);
  }

  readonly property string focusedId: CompositorManager.windows.find(w => w.focusRank === 0)?.id ?? ""

  // A click: start the app when it has no windows, else focus its most
  // recent one, or the next when one of them is focused
  function activate(item) {
    if (item.windows.length === 0)
      return root.launch(item.key);
    CompositorManager.focusWindow(DockLayout.clickTarget(item.windows, root.focusedId));
  }

  function focus(id) {
    CompositorManager.focusWindow(id);
  }

  // A new instance (middle click, the menu's New window)
  function launch(key) {
    const entry = root.entryFor(key);
    if (!entry) {
      console.warn(`[DockManager] No desktop entry for "${key}"`);
      return;
    }
    LauncherManager.launchApp(entry);
  }

  function closeWindows(item) {
    item.windows.forEach(w => CompositorManager.closeWindow(w.id));
  }

  // --- Pinning (saved at once) ---

  // Changes the pinned apps of a dock ([key] → [key]): its own with
  // pinnedOwn, else the shared Apps.pinned
  function _editPinned(dockId, change) {
    const docks = Utils.clone(DockConfig.docks);
    const dock = docks.find(d => d.id === dockId);
    if (!dock)
      return;
    if (!dock.pinnedOwn) {
      SettingsManager.commitValues({
        "Apps.pinned": change(Apps.pinned.slice())
      });
      return;
    }
    dock.pinned = change(dock.pinned);
    SettingsManager.commitValues({
      "Dock.items": docks
    });
  }

  // Pins an app at `index` (the end when -1), moving it there when it's
  // already pinned
  function pin(dockId, key, index) {
    root._editPinned(dockId, list => {
      const pinned = list.filter(k => k !== key);
      pinned.splice(index < 0 ? pinned.length : Math.min(index, pinned.length), 0, key);
      return pinned;
    });
  }

  function unpin(dockId, key) {
    root._editPinned(dockId, list => list.filter(k => k !== key));
  }

  // --- Reserved space ---

  // What each shown dock reserves, by "<screen>:<edge>:<dock id>" (edge
  // "top" | "bottom" | "left" | "right"): EdgePopouts (the OSD, edge
  // menus) reach past it to the border, so a dock doesn't push them in
  property var zones: ({})

  function setZone(screenName, edge, dockId, size) {
    const key = `${screenName}:${edge}:${dockId}`;
    if ((root.zones[key] ?? 0) === size)
      return;
    const zones = Object.assign({}, root.zones);
    if (size > 0)
      zones[key] = size;
    else
      delete zones[key];
    root.zones = zones;
  }

  // The space docks reserve on a screen edge, together
  function zoneOn(screenName, edge) {
    const prefix = `${screenName}:${edge}:`;
    return Object.keys(root.zones).filter(key => key.startsWith(prefix)).reduce((sum, key) => sum + root.zones[key], 0);
  }

  // --- Showing and hiding ---

  // The space reserved on each side of a screen, [left, top, right,
  // bottom]: where its work area starts (the output's `reserved`)
  function reservedOf(screen) {
    const reserved = CompositorManager.outputFor(screen)?.reserved;
    return reserved ? [reserved.left, reserved.top, reserved.right, reserved.bottom] : [0, 0, 0, 0];
  }

  // Quickshell only re-reads Hyprland's monitors on monitor events, and
  // Hyprland sends none when windows retile around a reserved zone that
  // changed, so both are re-read when a layer surface (a bar, a dock)
  // comes or goes, or a dock's zone changes (refreshSoon)
  function refreshSoon() {
    root._refresh.restart();
  }

  property Timer _refresh: Timer {
    interval: 200
    onTriggered: {
      CompositorManager.refresh();
    }
  }

  // Only while a dock is built: nothing else reads the refreshed state,
  // and every popout, OSD and toast opens a layer
  readonly property bool _active: DockConfig.shownIds.length > 0
  on_ActiveChanged: {
    if (root._active)
      CompositorManager.refresh();
  }

  property Connections _layers: Connections {
    target: CompositorManager
    enabled: root._active

    function onLayersChanged() {
      root.refreshSoon();
    }
    function onConfigReloaded() {
      root.refreshSoon();
    }
  }

  // Whether a window on the screen's active workspace covers `rect`
  // (screen-local), where it is or (supports.windowCover) where it surely
  // is. Never where the compositor doesn't say where windows are: the dock
  // then stays shown rather than hiding behind nothing
  function obscured(screen, rect) {
    if (CompositorManager.supports.windowGeometry !== true && CompositorManager.supports.windowCover !== true)
      return false;
    const output = CompositorManager.outputFor(screen);
    const workspaceId = output?.activeWorkspaceId ?? -1;
    if (workspaceId === -1)
      return false;
    // An open special workspace sits over the regular one
    const specialId = output.specialWorkspaceId;
    const windows = CompositorManager.windows.filter(w => !w.hidden && (w.workspaceId === workspaceId || (specialId !== 0 && w.workspaceId === specialId)));
    return DockLayout.covered({
      "x": rect.x + screen.x,
      "y": rect.y + screen.y,
      "width": rect.width,
      "height": rect.height
    }, windows);
  }

  function _ids(id) {
    return id ? [id] : DockConfig.shownIds;
  }

  function _setHidden(id, value) {
    const next = Object.assign({}, root.hidden);
    if (value)
      next[id] = true;
    else
      delete next[id];
    root.hidden = next;
  }

  // Empty ids act on every dock
  function show(id) {
    root._ids(id).forEach(each => {
      root._setHidden(each, false);
      root.revealRequested(each);
    });
  }

  function hide(id) {
    root._ids(id).forEach(each => {
      if (DockConfig.dockById(each)?.visibility === "always")
        root._setHidden(each, true);
      else
        root.concealRequested(each);
    });
  }

  function toggle(id) {
    root._ids(id).forEach(each => {
      if (DockConfig.dockById(each)?.visibility === "always")
        root._setHidden(each, !root.hidden[each]);
      else
        root.toggleRequested(each);
    });
  }

  // --- Preview (the settings card's Show) ---

  // A dock as its card edits it (a DockEntry, saved or not), which
  // shell/Dock slides in over the overlay for a moment on `previewScreen`
  // (where the dock would show), in a window of its own: the dock itself
  // is put away under the overlay. Kept once it's over, so the window
  // dropped then never reads null.
  property var previewDock: null
  property bool previewActive: false
  property string previewScreen: ""
  // Whether it's in; out, it slides away before it's dropped
  property bool previewShown: false

  function preview(dock) {
    if (!dock)
      return;
    root._previewEnd.stop();
    root.previewDock = Utils.clone(dock);
    root.previewScreen = ShellManager.targetFor(dock.screen);
    root.previewShown = true;
    root.previewActive = true;
    root._previewHold.restart();
  }

  // Whether the dock's own copy on the preview's screen hides behind it
  function previewing(id, screen) {
    return root.previewActive && root.previewDock?.id === id && root.previewScreen === (screen?.name ?? "");
  }

  // An always-shown dock reserving its strip shows beside the overlay, so
  // the preview lands on it and is dropped at once, the dock showing again
  function _landsInPlace(dock) {
    return dock.visibility === "always" && dock.reserveSpace && !root.hidden[dock.id] && DockConfig.shownIds.includes(dock.id);
  }

  property Timer _previewHold: Timer {
    interval: 2000
    onTriggered: {
      if (root._landsInPlace(root.previewDock)) {
        root.previewShown = false;
        root.previewActive = false;
        return;
      }
      root.previewShown = false;
      root._previewEnd.restart();
    }
  }

  property Timer _previewEnd: Timer {
    interval: Appearance.animNormal + 50
    onTriggered: root.previewActive = false
  }

  Component.onCompleted: {
    if (root._active)
      CompositorManager.refresh();
  }

  property IpcTarget _ipc: IpcTarget {
    target: "dock"

    function toggle(id: string): void {
      root.toggle(id);
    }

    function open(id: string): void {
      root.show(id);
    }

    function close(id: string): void {
      root.hide(id);
    }
  }
}
