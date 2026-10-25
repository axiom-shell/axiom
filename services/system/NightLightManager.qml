pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.apps

/*
 * The night light (the NightLight section): warmer colors through
 * hyprsunset, or wlsunset without it, started and stopped by axiom. On a
 * schedule it turns on at `startAt` and off at `endAt` (DailySchedule); a
 * switch by hand (the quick action, /nightlight, the `nightLight` IPC
 * target or bind) lasts until the next of those. A new temperature or
 * gamma restarts it while it's on.
 *
 * `active` is what axiom last set, kept across QML reloads; at startup it's
 * whether the tool is already running. Created from shell.qml's `_services`.
 *
 *   axiom ipc nightLight toggle
 */
Singleton {
  id: root

  // "hyprsunset" | "wlsunset" | "" (neither); undefined until looked up.
  // hyprsunset only under Hyprland: it drives Hyprland's own color
  // transform, so elsewhere it starts and does nothing
  readonly property var tool: {
    const found = DependencyManager.found;
    const hyprland = CompositorManager.kind === "hyprland";
    if (hyprland && found.hyprsunset === true)
      return "hyprsunset";
    if (found.wlsunset === true)
      return "wlsunset";
    return (!hyprland || found.hyprsunset === false) && found.wlsunset === false ? "" : undefined;
  }
  readonly property bool available: !!root.tool
  readonly property bool active: _run.active

  function setActive(on) {
    if (!root.available) {
      console.log("[NightLightManager] Neither hyprsunset nor wlsunset is installed");
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
    // The command axiom last started, so a reload doesn't restart it
    property string started: ""
  }

  // hyprsunset takes its settings as they are; wlsunset only runs a
  // day/night cycle, so both ends of it get the temperature
  readonly property var _command: {
    if (root.tool === "hyprsunset") {
      const command = ["hyprsunset", "-t", String(NightLight.temperature)];
      return NightLight.gamma < 100 ? command.concat(["-g", String(NightLight.gamma)]) : command;
    }
    if (root.tool === "wlsunset")
      return ["wlsunset", "-t", String(NightLight.temperature), "-T", String(NightLight.temperature + 1), "-S", "06:00", "-s", "18:00", "-g", String(NightLight.gamma / 100)];
    return [];
  }

  // Stop any running one (waiting up to a second), then start ours
  readonly property string _startScript: 'pkill -x "$1"; for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$1" >/dev/null || break; sleep 0.1; done; shift; setsid -f "$@" >/dev/null 2>&1'
  readonly property string _stopScript: 'pkill -x "$1"; true'

  function _apply() {
    if (!root.available)
      return;
    if (runner.running) {
      root._again = true;
      return;
    }
    console.log("[NightLightManager]", _run.active ? "On:" : "Off", _run.active ? root._settings : "");
    _run.started = _run.active ? root._settings : "";
    runner.command = _run.active ? ["sh", "-c", root._startScript, "sh", root.tool].concat(root._command) : ["sh", "-c", root._stopScript, "sh", root.tool];
    runner.running = true;
  }

  property bool _again: false
  property Process _runner: Process {
    id: runner
    onExited: {
      if (root._again) {
        root._again = false;
        root._apply();
      }
    }
  }

  // Whether the tool is already running (a restart of qs, or one started
  // before axiom managed it)
  property Process _probe: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        console.log("[NightLightManager] Probed", root.tool, "running:", text.trim() === "1");
        _run.active = text.trim() === "1";
        _run.probed = true;
      }
    }
  }
  // However the tool becomes known (it may be already at creation, when
  // no change would fire), once per qs launch; the schedule waits for it
  function _probeOnce() {
    if (!root.available || _run.probed || _probe.running)
      return;
    _probe.command = ["sh", "-c", 'pgrep -x "$1" >/dev/null && echo 1 || echo 0', "sh", root.tool];
    _probe.running = true;
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

  // A new temperature or gamma while it's on: restart it (debounced, since
  // the slider commits as it's dragged)
  readonly property string _settings: root._command.join(" ")
  on_SettingsChanged: if (_run.active && _run.probed && root._settings !== _run.started)
    _restart.restart()
  property Timer _restart: Timer {
    interval: 400
    onTriggered: if (_run.active)
      root._apply()
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

  Component.onCompleted: {
    DependencyManager.check(["hyprsunset", "wlsunset"]);
    root._probeOnce();
  }
}
