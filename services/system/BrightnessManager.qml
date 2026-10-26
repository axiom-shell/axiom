pragma Singleton

import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.compositor

// Screen brightness per monitor: a laptop panel through its sysfs backlight
// (written with brightnessctl, which goes through logind), an external
// monitor over DDC/CI (ddcutil, VCP 0x10). Monitors are found once at
// startup and again when the screens change; values are read then and when
// the OSD opens (`refresh`), never polled. Writes show at once and are
// coalesced per monitor, so held brightness keys don't queue slow DDC calls.
QtObject {
  id: root

  // { screenName: { kind: "backlight" | "ddc", device, bus, max, value } },
  // value 0-1. Replaced on every change, so bindings on it update.
  property var displays: ({})

  // A monitor's brightness was set through axiom (not found on a refresh)
  signal brightnessChanged(string name)

  readonly property real step: 0.05

  // The monitors with a controller, by name; a string, so it only
  // notifies when one comes or goes (not on every value)
  readonly property string namesKey: Object.keys(displays).sort().join(",")
  readonly property var names: namesKey === "" ? [] : namesKey.split(",")

  // The mean brightness of these monitors (those with a controller), 0
  // with none
  function average(names) {
    const known = names.filter(name => available(name));
    return known.length > 0 ? known.reduce((sum, name) => sum + valueFor(name), 0) / known.length : 0;
  }

  // Every one of these monitors to `value`
  function setMany(names, value, silent) {
    for (const name of names)
      set(name, value, silent);
  }

  function available(name) {
    return displays[name] !== undefined;
  }

  function valueFor(name) {
    return displays[name]?.value ?? 0;
  }

  // A silent set doesn't emit brightnessChanged, so the OSD stays shut
  function set(name, value, silent) {
    const display = displays[name];
    if (!display)
      return;
    const clamped = Math.max(0, Math.min(1, value));
    _update(name, clamped);
    if (!silent)
      brightnessChanged(name);
    if (_writing[name])
      _pending[name] = clamped;
    else
      _write(name, clamped);
  }

  // Idle dimming (the daemon's idle steps, through IPC): every monitor down to `fraction`
  // (darker ones stay), or with `relative` down by `fraction` of its own
  // brightness, then back to what each was on undim()
  function dim(fraction, relative) {
    for (const name of Object.keys(displays)) {
      if (_dimmed[name] !== undefined)
        continue;
      const value = valueFor(name);
      _dimmed[name] = value;
      const target = relative ? value * (1 - fraction) : fraction;
      if (value > target)
        set(name, target, true);
    }
  }

  function undim() {
    for (const name of Object.keys(_dimmed))
      set(name, _dimmed[name], true);
    _dimmed = {};
  }

  // { screenName: value before dim() }
  property var _dimmed: ({})

  function stepBy(name, delta) {
    if (available(name))
      set(name, valueFor(name) + delta);
  }

  // Reads the monitor's current value, for changes made outside axiom
  function refresh(name) {
    const display = displays[name];
    if (!display || _writing[name])
      return;
    if (display.kind === "backlight") {
      const raw = parseInt(FileManager.read(`/sys/class/backlight/${display.device}/brightness`));
      if (isFinite(raw))
        _update(name, raw / display.max);
      return;
    }
    _run(["ddcutil", "--bus", String(display.bus), "getvcp", "10", "--terse"], text => {
      // "VCP 10 C <current> <max>"
      const match = text.match(/VCP 10 C (\d+) (\d+)/);
      if (match && !root._writing[name])
        root._update(name, parseInt(match[1]) / Math.max(1, parseInt(match[2])), parseInt(match[2]));
    });
  }

  function _focused() {
    return CompositorManager.focusedOutput;
  }

  function _update(name, value, max) {
    const display = displays[name];
    if (!display || (display.value === value && (max === undefined || display.max === max)))
      return;
    const next = Object.assign({}, displays);
    next[name] = Object.assign({}, display, {
      "value": value
    }, max === undefined ? {} : {
      "max": max
    });
    displays = next;
  }

  property var _writing: ({})
  property var _pending: ({})

  function _write(name, value) {
    const display = displays[name];
    _writing[name] = true;
    // A backlight at 0 turns the panel off, so it stops at one step
    const command = display.kind === "backlight" ? ["brightnessctl", "-q", "-d", display.device, "set", String(Math.max(1, Math.round(value * display.max)))] : ["ddcutil", "--bus", String(display.bus), "--noverify", "setvcp", "10", String(Math.round(value * display.max))];
    _run(command, (text, exitCode) => {
      if (exitCode !== 0)
        console.warn(`[BrightnessManager] ${command[0]} failed for ${name} (exit ${exitCode})`);
      const pending = root._pending[name];
      delete root._pending[name];
      root._writing[name] = false;
      if (pending !== undefined && root.displays[name])
        root._write(name, pending);
    });
  }

  // Runs a command once and hands its stdout and exit code to `done`
  function _run(command, done) {
    CommandManager.run(command, (code, out) => done(out, code));
  }

  // -- Detection --

  function detect() {
    // Backlights as "backlight <name> <type> <brightness> <max>", then
    // ddcutil's display list
    _run(["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && echo \"backlight ${d##*/} $(cat \"$d/type\") $(cat \"$d/brightness\") $(cat \"$d/max_brightness\")\"; done; command -v ddcutil >/dev/null && ddcutil detect --terse 2>/dev/null; true"], text => root._parseDetect(text));
  }

  function _parseDetect(text) {
    const found = {};
    // Several backlights can drive one panel: prefer firmware over
    // platform over raw, as systemd-backlight does
    const priority = {
      "firmware": 0,
      "platform": 1,
      "raw": 2
    };
    const backlights = text.split("\n").filter(line => line.startsWith("backlight ")).map(line => line.split(" ")).sort((a, b) => (priority[a[2]] ?? 3) - (priority[b[2]] ?? 3));
    const panel = General.outputs.map(screen => screen.name).find(name => /^(eDP|LVDS|DSI)-/.test(name));
    if (panel && backlights.length > 0) {
      const [, device, , raw, max] = backlights[0];
      found[panel] = {
        "kind": "backlight",
        "device": device,
        "max": Math.max(1, parseInt(max)),
        "value": parseInt(raw) / Math.max(1, parseInt(max))
      };
    }
    // "Display N / I2C bus: /dev/i2c-9 / DRM connector: card1-DP-1"
    for (const block of text.split(/^Display \d+/m).slice(1)) {
      const bus = block.match(/I2C bus:\s*\/dev\/i2c-(\d+)/)?.[1];
      const connector = block.match(/DRM connector:\s*card\d+-(\S+)/)?.[1];
      if (bus !== undefined && connector && !found[connector])
        found[connector] = {
          "kind": "ddc",
          "bus": parseInt(bus),
          "max": 100,
          "value": displays[connector]?.value ?? 0.5
        };
    }
    displays = found;
    console.log("[BrightnessManager] Found", JSON.stringify(found));
    for (const name of Object.keys(found)) {
      if (found[name].kind === "ddc")
        refresh(name);
    }
  }

  // ddcutil needs a moment after a monitor is plugged in
  property Timer _redetect: Timer {
    interval: 2000
    onTriggered: root.detect()
  }

  property Connections _screens: Connections {
    target: Quickshell

    function onScreensChanged() {
      root._redetect.restart();
    }
  }

  Component.onCompleted: detect()

  // Brightness keys (keybind actions brightnessUp, ...), on the focused
  // monitor: the OSD shows the change
  property IpcTarget _ipc: IpcTarget {
    target: "brightness"

    function up(): void {
      root.stepBy(root._focused(), root.step);
    }

    function down(): void {
      root.stepBy(root._focused(), -root.step);
    }

    function set(percent: int): void {
      root.set(root._focused(), percent / 100);
    }

    // Every monitor, without the OSD (the Idle settings' dim step)
    function dim(percent: int): void {
      root.dim(Math.max(0, Math.min(100, percent)) / 100);
    }

    // Every monitor down by `percent` of its own brightness, so it always dims
    function dimBy(percent: int): void {
      root.dim(Math.max(0, Math.min(100, percent)) / 100, true);
    }

    function undim(): void {
      root.undim();
    }
  }
}
