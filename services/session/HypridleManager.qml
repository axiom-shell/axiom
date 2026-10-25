pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/*
 * hypridle, run by axiom (the Idle section). While Idle.enabled, axiom
 * renders its own config (components/methods/HypridleConf) to
 * $XDG_STATE_HOME/axiom/hypridle.conf and runs `hypridle -c` on it,
 * stopping any other hypridle; the user's ~/.config/hypr/hypridle.conf is
 * never touched. hypridle doesn't watch its config, so a change restarts
 * it. Turned off, axiom stops its own and starts a plain `hypridle` again
 * when the user has a config for one.
 *
 * Nothing is polled: the process is looked up on each apply, and once more
 * 15 s after startup for a plain hypridle a user's own autostart launched
 * after qs. Created from shell.qml's `_services`.
 */
Singleton {
  id: root

  readonly property string configPath: Paths.userStatePath + "hypridle.conf"
  readonly property string userConfigPath: Paths.hyprlandPath + "hypridle.conf"

  // undefined until DependencyManager has looked
  readonly property var installed: DependencyManager.found.hypridle
  // "off" | "missing" | "running" | "stopped"
  readonly property string status: !Idle.enabled ? "off" : installed === false ? "missing" : _ours > 0 ? "running" : "stopped"
  // axiom had to stop a hypridle that wasn't its own (a user's autostart)
  readonly property bool replacedOther: _replacedOther
  property bool _replacedOther: false
  property int _ours: 0
  property int _all: 0

  // How hypridle locks: through axiom's locker, or the user's own command
  // in "none" mode (except loginctl lock-session, which would loop)
  readonly property string lockCmd: {
    if (LockscreenConfig.mode !== "none")
      return `${Paths.shellCommand} lock`;
    const command = LockscreenConfig.lockCommand.trim();
    return command === "loginctl lock-session" ? "" : command;
  }

  // reads: Idle.* (the whole reader, handed to HypridleConf.render)
  readonly property string configText: HypridleConf.render(Idle, {
    "lockCmd": root.lockCmd,
    "shellCommand": Paths.shellCommand,
    "dpmsOff": CompositorManager.dpmsCommand(false),
    "dpmsOn": CompositorManager.dpmsCommand(true)
  })

  // Writes the config if it changed and makes sure axiom's hypridle is
  // the one running; turned off, stops it
  function apply() {
    if (!Idle.enabled) {
      _probe(() => {
        if (root._ours > 0)
          root._run(_stop, [root.configPath, root.userConfigPath]);
      });
      return;
    }
    if (FileManager.read(configPath) !== configText) {
      makeDir.running = true;
      return;
    }
    _probe(() => {
      // Another one beside ours: something else starts hypridle too
      if (root._ours > 0 && root._all > root._ours)
        root._replacedOther = true;
      if (root._ours === 0 || root._all > root._ours)
        root.restart();
    });
  }

  // Starts axiom's hypridle, stopping any running one
  function restart() {
    if (Idle.enabled)
      _run(_start, [configPath]);
  }

  // --- Processes ---

  // Stop every hypridle (waiting up to a second), start ours
  readonly property string _start: 'command -v hypridle >/dev/null || exit 0; pkill -x hypridle; for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x hypridle >/dev/null || break; sleep 0.1; done; setsid -f hypridle -c "$1" >/dev/null 2>&1'
  // Stop ours; bring the user's own back if they have a config for it
  readonly property string _stop: 'pkill -xf "hypridle -c $1"; sleep 0.3; if [ -f "$2" ] && ! pgrep -x hypridle >/dev/null; then setsid -f hypridle >/dev/null 2>&1; fi; true'

  function _run(script, args) {
    if (runner.running) {
      root._again = true;
      return;
    }
    runner.command = ["sh", "-c", script, "sh"].concat(args);
    runner.running = true;
  }

  property bool _again: false

  Process {
    id: runner
    onExited: {
      if (root._again) {
        root._again = false;
        root.apply();
        return;
      }
      // Let setsid's child start before counting
      root._probeLater.restart();
    }
  }

  property Timer _probeLater: Timer {
    interval: 500
    onTriggered: root._probe(null)
  }

  // Counts axiom's hypridle and all of them, then calls `then`
  function _probe(then) {
    root._probeThen = then;
    if (!probe.running)
      probe.running = true;
  }

  property var _probeThen: null

  Process {
    id: probe
    command: ["sh", "-c", 'echo "$(pgrep -xcf "hypridle -c $1") $(pgrep -xc hypridle)"', "sh", root.configPath]
    stdout: StdioCollector {
      onStreamFinished: {
        const [ours, all] = text.trim().split(/\s+/).map(Number);
        root._ours = ours || 0;
        root._all = all || 0;
        const then = root._probeThen;
        root._probeThen = null;
        if (then)
          then();
      }
    }
  }

  // --- Writing the config ---

  Process {
    id: makeDir
    command: ["mkdir", "-p", Paths.userStatePath]
    onExited: code => {
      if (code !== 0) {
        console.warn("[HypridleManager] Could not create", Paths.userStatePath);
        return;
      }
      writer.path = root.configPath;
      writer.setText(root.configText);
    }
  }

  FileView {
    id: writer
    atomicWrites: true
    printErrors: false
    onSaved: root.restart()
    onSaveFailed: error => console.warn("[HypridleManager] Could not write", root.configPath, error)
  }

  // --- Driving it ---

  readonly property string _inputs: [Idle._json, configText].join("|")
  on_InputsChanged: _debounce.restart()

  property Timer _debounce: Timer {
    interval: 300
    onTriggered: root.apply()
  }

  // A plain hypridle the user's own autostart runs after qs
  property Timer _lateCheck: Timer {
    interval: 15000
    onTriggered: if (Idle.enabled)
      root.apply()
  }

  Component.onCompleted: {
    DependencyManager.check(["hypridle"]);
    _debounce.restart();
    _lateCheck.start();
  }
}
