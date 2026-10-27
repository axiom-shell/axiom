pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.core

/*
 * The night light (the NightLight section): warmer colors, set by the
 * axiom daemon on the compositor's color transform or gamma ramps
 * (nightlight.set: internal/nightlight), or, where the compositor offers
 * neither (niri), by wlsunset, started and stopped by axiom. On a
 * schedule it turns on at `startAt` and off at `endAt` (DailySchedule); a
 * switch by hand (the quick action, /nightlight, the `nightLight` IPC
 * target or bind) lasts until the next of those. A new temperature or
 * gamma is applied while it's on.
 *
 * `active` is what axiom last set, kept across QML reloads; at startup
 * it's what the daemon holds, or whether wlsunset already runs. Created
 * from shell.qml's `_services`.
 *
 *   axiom ipc nightLight toggle
 */
Singleton {
  id: root

  // "axiom" | "wlsunset" | "" (neither); undefined until known
  readonly property var tool: {
    if (WaylandManager.nightLight !== "")
      return "axiom";
    // Not wlsunset before the daemon has said it can't (it would run
    // beside the daemon's)
    if (BackendManager.active && !WaylandManager.known)
      return undefined;
    const found = DependencyManager.found.wlsunset;
    return found === true ? "wlsunset" : found === false ? "" : undefined;
  }
  readonly property bool available: !!root.tool
  readonly property bool active: _run.active
  // Another program holds the screens' colors (the daemon's state)
  readonly property bool blocked: root._daemonState?.blocked === true

  function setActive(on) {
    if (!root.available) {
      console.log("[NightLightManager] No way to warm the screens here: the compositor has no color transform or gamma control, and wlsunset isn't installed");
      return;
    }
    _run.active = on;
    root._apply();
  }

  function toggle() {
    root.setActive(!root.active);
  }

  // --- Private ---

  PersistentProperties {
    id: _run
    reloadableId: "axiomNightLight"
    property bool active: false
    property bool probed: false
    // The settings axiom last applied, so a reload doesn't apply them again
    property string started: ""
  }

  property var _daemonState: null

  // wlsunset only runs a day/night cycle, so both ends of it get the
  // temperature
  readonly property var _command: ["wlsunset", "-t", String(NightLight.temperature), "-T", String(NightLight.temperature + 1), "-S", "06:00", "-s", "18:00", "-g", String(NightLight.gamma / 100)]
  readonly property string _settings: root.tool === "wlsunset" ? root._command.join(" ") : `${NightLight.temperature}|${NightLight.gamma}`

  // Stop any running one (waiting up to a second), then start ours
  readonly property string _startScript: 'pkill -x "$1"; for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$1" >/dev/null || break; sleep 0.1; done; shift; setsid -f "$@" >/dev/null 2>&1'
  readonly property string _stopScript: 'pkill -x "$1"; true'

  function _apply() {
    if (!root.available)
      return;
    _run.started = _run.active ? root._settings : "";
    if (root.tool === "axiom") {
      BackendManager.call("nightlight.set", {
        "on": _run.active,
        "temperature": NightLight.temperature,
        "gamma": NightLight.gamma
      }, error => {
        if (error)
          console.warn("[NightLightManager] Could not set the night light:", error.message);
      });
      return;
    }
    if (root._applying) {
      root._again = true;
      return;
    }
    console.log("[NightLightManager]", _run.active ? "On:" : "Off", _run.active ? root._settings : "");
    root._applying = true;
    CommandManager.run(_run.active ? ["sh", "-c", root._startScript, "sh", "wlsunset"].concat(root._command) : ["sh", "-c", root._stopScript, "sh", "wlsunset"], () => {
      root._applying = false;
      if (root._again) {
        root._again = false;
        root._apply();
      }
    });
  }

  property bool _applying: false
  property bool _again: false

  // Whether it's already on (a restart of qs; wlsunset started before
  // axiom managed it), once per qs launch; the schedule waits for it
  property bool _probing: false
  function _probeOnce() {
    if (!root.available || _run.probed || root._probing)
      return;
    if (root.tool === "axiom") {
      BackendManager.call("nightlight.get", {}, (error, state) => {
        root._daemonState = error ? null : state;
        _run.active = !error && state.on;
        _run.probed = true;
      });
      return;
    }
    root._probing = true;
    CommandManager.run(["pgrep", "-x", "wlsunset"], exitCode => {
      root._probing = false;
      console.log("[NightLightManager] Probed wlsunset running:", exitCode === 0);
      _run.active = exitCode === 0;
      _run.probed = true;
    });
  }
  onAvailableChanged: root._probeOnce()

  property DailySchedule _schedule: DailySchedule {
    name: "nightLight"
    enabled: NightLight.schedule
    // Not before the probe, which would overwrite what it sets
    ready: root.available && _run.probed
    startAt: NightLight.startAt
    endAt: NightLight.endAt
    onDue: on => root.setActive(on)
  }

  // A new temperature or gamma while it's on: the daemon takes it as the
  // slider moves; wlsunset restarts, debounced
  on_SettingsChanged: if (_run.active && _run.probed && root._settings !== _run.started)
    _change.restart()
  property Timer _change: Timer {
    interval: root.tool === "axiom" ? 30 : 400
    onTriggered: if (_run.active)
      root._apply()
  }

  property Connections _backend: Connections {
    target: BackendManager
    // A daemon re-exec'd or restarted has forgotten it
    function onGreeted() {
      if (root.tool === "axiom" && _run.probed && _run.active)
        root._apply();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("nightlight.state", state => root._daemonState = state);
    DependencyManager.check(["wlsunset"]);
    root._probeOnce();
  }

  property IpcTarget _ipc: IpcTarget {
    target: "nightLight"

    function toggle(): void {
      root.toggle();
    }

    function enable(): void {
      root.setActive(true);
    }

    function disable(): void {
      root.setActive(false);
    }

    function status(): bool {
      return root.active;
    }
  }
}
