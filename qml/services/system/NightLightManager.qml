pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.core
import qs.services.ui

/*
 * The night light (the NightLight section): warmer colors, set by the
 * axiom daemon on the compositor's color transform or gamma ramps
 * (nightlight.set: internal/nightlight), or, where the compositor offers
 * neither (niri), by wlsunset, started and stopped by the daemon
 * (nightlight.wlsunset: it stops the user's own, records it and starts it
 * again when axiom quits, and marks axiom's). On a
 * schedule it turns on at `startAt` and off at `endAt` (DailySchedule); a
 * switch by hand (the quick action, /nightlight, the `nightLight` IPC
 * target or bind) lasts until the next of those. A new temperature or
 * gamma is applied while it's on.
 *
 * `active` is what axiom last set, kept across QML reloads; at startup
 * it's what the daemon holds, or whether wlsunset already runs. Created
 * from shell.qml's `_services`.
 *
 * rpc: nightlight.set, nightlight.get, nightlight.wlsunset, nightlight.wlsunsetState
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
    BackendManager.call("nightlight.wlsunset", {
      "on": _run.active,
      "argv": root._command
    }, error => {
      if (error)
        console.warn("[NightLightManager] Could not run wlsunset:", error.message);
      root._applying = false;
      if (root._again) {
        root._again = false;
        root._apply();
      }
    });
  }

  property bool _applying: false
  property bool _again: false

  // Whether axiom's wlsunset is already on (a restart of qs), once per qs launch; the schedule waits for it
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
    BackendManager.call("nightlight.wlsunsetState", {}, (error, state) => {
      root._probing = false;
      const running = !error && state.running === true;
      console.log("[NightLightManager] Probed wlsunset running:", running);
      _run.active = running;
      _run.probed = true;
    });
  }
  onAvailableChanged: root._probeOnce()

  DailySchedule {
    id: _schedule
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

  // Whether the screens can be warmed here; says why not on the OSD (a
  // bind's or `axiom night-light`'s, which has no tile to hide)
  function _canWarm() {
    // Still looking: setActive says so in the log
    if (root.tool !== "")
      return true;
    ShellManager.refuse("nightlight", I18n.tr("Night light"), I18n.tr("Not available here"));
    return false;
  }

  property IpcTarget _ipc: IpcTarget {
    target: "nightLight"

    function toggle(): void {
      if (root._canWarm())
        root.toggle();
    }

    function enable(): void {
      if (root._canWarm())
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
