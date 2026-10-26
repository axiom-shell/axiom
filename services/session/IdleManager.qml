pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.services.core

// Idle: what happens when you step away (the Idle section), run by the
// axiom daemon (idle.state: docs/dev/features/idle.md), and the caffeine
// switch that keeps the session awake. The Wayland idle inhibitor itself
// needs a mapped surface, so shell/IdleInhibit holds one while `caffeine`
// is on; the daemon is told too, as notifications that ignore inhibitors
// (Idle.respectInhibitors off) would ignore that surface. Caffeine is kept
// across QML reloads, but a restart always starts with idle allowed.
// Created from shell.qml's `_services`.
//
//   axiom ipc idleInhibit toggle
Singleton {
  id: root

  property alias caffeine: _run.caffeine

  // "off" | "running" | "inhibited" (an app holds idle off) |
  // "unsupported" (the compositor has no idle notifications) |
  // "unavailable" (no daemon to run it)
  readonly property string status: {
    if (!Idle.enabled)
      return "off";
    const state = root._state;
    if (!state || !state.enabled)
      return "unavailable";
    if (!state.notifier)
      return "unsupported";
    return state.inhibited ? "inhibited" : "running";
  }
  // What holds idle off: [{ source: "screensaver" | "logind" | "caffeine",
  // app, reason }]
  readonly property var inhibitors: root._state?.inhibitors ?? []
  // The program holding org.freedesktop.ScreenSaver instead of axiom, ""
  // when axiom or the compositor (which applies them itself) does: apps
  // asking it to keep the screen on aren't seen
  readonly property string screensaverHolder: {
    const ss = root._state?.screensaver;
    if (!ss || !ss.serving || ss.owned || ss.compositor || !ss.owner)
      return "";
    return ss.owner.name || I18n.tr("another program");
  }

  property var _state: null

  PersistentProperties {
    id: _run
    reloadableId: "axiomIdleInhibit"
    property bool caffeine: false
  }

  function toggle() {
    root.caffeine = !root.caffeine;
  }

  onCaffeineChanged: root._report()

  function _report() {
    BackendManager.call("idle.caffeine", {
      "on": root.caffeine
    }, null);
  }

  // Caffeine to the daemon, and its state back
  function _sync() {
    root._report();
    BackendManager.call("idle.get", {}, (error, state) => {
      if (!error)
        root._state = state;
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._sync();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("idle.state", state => root._state = state);
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._sync();
  }

  property IpcTarget _ipc: IpcTarget {
    target: "idleInhibit"

    function toggle(): void {
      root.toggle();
    }

    function enable(): void {
      root.caffeine = true;
    }

    function disable(): void {
      root.caffeine = false;
    }

    function status(): bool {
      return root.caffeine;
    }
  }
}
