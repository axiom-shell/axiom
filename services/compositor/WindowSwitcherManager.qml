pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

/**
 * The window switcher (Alt+Tab). The compositor reports each step, pick
 * and cancel to the backend's switcherKey: on Hyprland a switcher bind
 * enters the submap axiom's layer defines (render.SwitcherLua), so nothing here can miss
 * a quick release. sway's and niri's binds report steps only (`nop axiom
 * switcher`, `axiom ipc windowSwitcher`), so while it's open the daemon
 * holds the keyboard (switcher.hold): it sees the keys already down when
 * it takes it, so a modifier let go before then still picks, and pushes
 * switcher.key on the release, Return or Escape. The first step opens it on the focused
 * monitor with the windows most recently used first, fixed until it
 * closes; it only shows once held for WindowSwitcherConfig.showDelay, so a
 * tap swaps windows without drawing anything.
 */
Singleton {
  id: root

  // Open (stepped into, not yet picked or cancelled), drawn or not
  readonly property bool active: root._active
  // Past the show delay: the strip is drawn
  readonly property bool shown: root._shown
  // The compositor's windows, most recently focused first
  readonly property var windows: root._windows
  readonly property int index: root._index
  readonly property string screenName: root._screenName

  property bool _active: false
  property bool _shown: false
  property var _windows: []
  property int _index: 0
  property string _screenName: ""
  // The window focused when it opened, which picking leaves alone
  property string _focusedId: ""
  // The daemon holds the keyboard for it (no supports.switcherRelease)
  property bool _held: false

  // The modifiers the switcher binds are held by
  // (BindActions.switcherHeld), or the usual ones with none bound
  readonly property var _heldMods: {
    const held = [].concat(...KeybindsConfig.activeBinds.filter(bind => KeybindManager.actionTable?.switcherSteps?.[bind.action] !== undefined).map(bind => BindActions.switcherHeld(KeyNames.split(bind.key).mods)));
    return held.length > 0 ? held.filter((mod, i) => held.indexOf(mod) === i) : ["SUPER", "ALT", "CTRL"];
  }

  // Moves the selection `n` windows on, opening first when closed (the
  // first step from the current window is the last one used)
  function step(n) {
    if (!root._active)
      root._open();
    root._index = WindowOrder.stepIndex(root._index, n, root._windows.length);
  }

  // Focuses the selected window and closes (nothing while closed: a pick
  // can arrive after a cancel or a click)
  function commit() {
    if (!root._active)
      return;
    const win = root._windows[root._index];
    root._close();
    if (win && win.id !== root._focusedId)
      CompositorManager.focusWindow(win.id);
  }

  function cancel() {
    root._close();
  }

  // A tile clicked: focuses its window and leaves the submap and its
  // release listener (the modifier is likely still held)
  function pick(index) {
    root._index = index;
    root.commit();
    if (CompositorManager.supports.switcher)
      CompositorManager.backend.leaveSwitcher();
  }

  function _open() {
    const output = CompositorManager.focused;
    const scope = WindowSwitcherConfig.scope;
    root._focusedId = CompositorManager.activeWindowId;
    root._windows = WindowOrder.mru(CompositorManager.windows, win => DockLayout.inScope(win, scope, output?.name ?? "", output?.activeWorkspaceId ?? -1), root._focusedId);
    root._index = 0;
    root._screenName = ShellManager.targetFor("focused");
    root._active = true;
    showTimer.restart();
    if (CompositorManager.supports.switcher && !CompositorManager.supports.switcherRelease)
      root._hold();
  }

  function _hold() {
    root._held = true;
    BackendManager.call("switcher.hold", {
      "mods": root._heldMods
    }, error => {
      if (!error)
        return;
      // Nothing would see the release: a tap's pick
      console.warn("WindowSwitcherManager: can't hold the keyboard:", error.message);
      root._held = false;
      root.commit();
    });
  }

  function _close() {
    showTimer.stop();
    root._active = false;
    root._shown = false;
    if (root._held) {
      root._held = false;
      BackendManager.call("switcher.release", {}, null);
    }
  }

  // The held keyboard's pick or cancel (switcher.hold)
  Component.onCompleted: BackendManager.listen("switcher.key", key => {
    if (key.verb === "commit")
      root.commit();
    else if (key.verb === "cancel")
      root.cancel();
  })

  Timer {
    id: showTimer
    interval: WindowSwitcherConfig.showDelay
    onTriggered: root._shown = root._active
  }

  // The compositor holds the switcher's keys (Hyprland: the
  // switcher's submap; sway: `nop axiom switcher` binds, both axiom's layer)
  Connections {
    target: CompositorManager.supports.switcher ? CompositorManager.backend : null

    function onSwitcherKey(verb, argument) {
      if (verb === "step")
        root.step(parseInt(argument) || 1);
      else if (verb === "commit")
        root.commit();
      else if (verb === "cancel")
        root.cancel();
    }
  }

  // `axiom ipc windowSwitcher …`, for scripts and testing: it
  // doesn't enter Hyprland's submap, so nothing picks on a release there
  // (sway and niri: the daemon's hold does)
  IpcTarget {
    target: "windowSwitcher"

    function next(): void {
      root.step(1);
    }

    function previous(): void {
      root.step(-1);
    }

    function commit(): void {
      root.commit();
    }

    function cancel(): void {
      root.cancel();
    }
  }
}
