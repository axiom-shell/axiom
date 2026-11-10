pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.services.core
import qs.services.compositor

/*
 * Page windows: overlay tool pages (`x-window`) popped out into windows of
 * their own (shell/PageWindows, hosts/window/PageWindow). A page is built
 * in one place at a time, as its state lives in singletons: while it's in
 * a window, the overlay shows a box in its place (PoppedOutCard).
 *   popOut(type)   closes the overlay and opens the page in a window
 *   popIn(type)    closes the window and opens the page in the overlay
 *   focus(type)    closes the overlay and goes to the page's window (its
 *                  workspace too)
 *   opened(key)    a request for a page by type or name: focuses its
 *                  window and answers true when it's popped out, so the
 *                  overlay doesn't open (OverlayPanel.openPage)
 * Which pages are out survives a QML reload (not a restart); each page's
 * window size is kept for good (StateManager).
 */
Singleton {
  id: root

  // The popped out page types, in the order they were popped out
  readonly property var open: root._windows.map(each => each.type)
  // [{ type, screen }]: each window and the screen it opened on (the
  // overlay's, as it was popped out), whose card size it keeps
  readonly property var _windows: JSON.parse(_kept.open)
  // The page whose window has the keyboard, "" for none (each window
  // reports it): where a link followed from it came from
  readonly property string activeType: root._activeType
  property string _activeType: ""

  function isOpen(type) {
    return root.open.includes(type);
  }

  // A page's window title, which focus() finds it by
  function titleOf(type) {
    return I18n.tr("{0} — axiom", OverlayConfig.viewLabel({
      "type": type
    }, 0));
  }

  // Whether a page can be popped out here: one that can (`x-window`), in
  // Overlay.items, whose compositor needs (`x-needs`) are met
  function canOpen(type) {
    const needs = OverlayConfig.viewInfo(type)?.needs ?? "";
    return OverlayConfig.isWindowable(type) && OverlayConfig.viewEntry(type) !== null && (needs === "" || CompositorManager.supports[needs] === true);
  }

  function popOut(type) {
    if (!root.canOpen(type) || root.isOpen(type))
      return;
    ShellManager.closeOverlay();
    root._setOpen(root._windows.concat([
      {
        "type": type,
        "screen": ShellManager.targetFor(OverlayConfig.screen)
      }
    ]));
  }

  // The screen a page's window opened on (one of General.outputs), else
  // the first
  function screenOf(type) {
    const name = root._windows.find(each => each.type === type)?.screen ?? "";
    return General.outputs.find(screen => screen.name === name) ?? General.outputs[0] ?? null;
  }

  // Back into the overlay: `show` opens it there (the window's button), else
  // the overlay already showing its box just builds the page in its place
  function popIn(type, show) {
    root.closed(type);
    if (show)
      ShellManager.openOverlayPage(type);
  }

  // The window was closed (its own close, or popIn): the page is back in
  // the overlay, its unsaved edits kept in their drafts
  function closed(type) {
    if (root.isOpen(type))
      root._setOpen(root._windows.filter(each => each.type !== type));
    if (root._activeType === type)
      root._activeType = "";
  }

  function setActive(type, active) {
    if (active)
      root._activeType = type;
    else if (root._activeType === type)
      root._activeType = "";
  }

  // The compositor's window for a page: ours (this shell's app id) by its
  // title, null before it's mapped
  function _windowOf(type) {
    const title = root.titleOf(type);
    return CompositorManager.windows.find(win => win.title === title && win.appId === Quickshell.appId) ?? null;
  }

  // The overlay closes first: it would cover the window and keep the
  // keyboard
  function focus(type) {
    ShellManager.closeOverlay();
    const win = root._windowOf(type);
    if (win)
      CompositorManager.focusWindow(win.id);
  }

  function opened(key) {
    const type = OverlayConfig.typeOfPage(key);
    if (type === "" || !root.isOpen(type))
      return false;
    root.focus(type);
    return true;
  }

  // A window's size, [w, h] in px, or null before it first opened. Kept
  // in place, never notified: a window reads it once, as it opens, so its
  // own resizes don't feed back into its size
  function sizeOf(type) {
    return root._sizes[type] ?? null;
  }

  function keepSize(type, width, height) {
    const size = [Math.round(width), Math.round(height)];
    const old = root._sizes[type];
    if (old && old[0] === size[0] && old[1] === size[1])
      return;
    root._sizes[type] = size;
    _saveSizes.restart();
  }

  // --- Private ---

  function _setOpen(windows) {
    _kept.open = JSON.stringify(windows);
  }

  // A page taken out of Overlay.items is out of a window too: it doesn't
  // come back in one when it's put back
  property Connections _items: Connections {
    target: OverlayConfig
    function onViewsChanged() {
      const kept = root._windows.filter(each => OverlayConfig.viewEntry(each.type) !== null);
      if (ConfigManager.available && kept.length !== root._windows.length)
        root._setOpen(kept);
    }
  }

  // Kept across a QML reload (a restart starts with none out)
  PersistentProperties {
    id: _kept
    reloadableId: "axiomPageWindows"
    property string open: "[]"
  }

  readonly property var _state: StateManager.createStateHandler("pageWindows")
  property var _sizes: ({})

  // A resize drag reports every step: written once it settles
  property Timer _saveSizes: Timer {
    interval: 1000 // a resize settling
    onTriggered: root._state.save({
      "sizes": root._sizes
    })
  }

  Component.onCompleted: {
    const saved = root._state.load({});
    root._sizes = saved.sizes && typeof saved.sizes === "object" ? saved.sizes : {};
  }

  property IpcTarget _ipc: IpcTarget {
    target: "pages"
    enabled: !Paths.greeter

    // Opens a page (its type, any case: "settings", "BarEditor") in a
    // window, or goes to its window when it's already in one: the desktop
    // entries' command
    function window(page: string): bool {
      const type = OverlayConfig.windowTypes.find(each => each.toLowerCase() === page.toLowerCase()) ?? "";
      if (!root.canOpen(type))
        return false;
      if (root.isOpen(type))
        root.focus(type);
      else
        root.popOut(type);
      return true;
    }

    // Puts a page's window back into the overlay (without opening it)
    function close(page: string): void {
      const type = OverlayConfig.windowTypes.find(each => each.toLowerCase() === page.toLowerCase()) ?? "";
      if (type !== "")
        root.closed(type);
    }

    // The popped out pages, one per line
    function list(): string {
      return root.open.join("\n");
    }
  }
}
