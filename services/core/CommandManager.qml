pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Shell commands polled for their output (e.g. a bar Button's label),
// shared by every widget asking for the same command: each distinct
// command runs once per interval (the shortest asked for), only while
// something has acquire()d it.
//   CommandManager.acquire(owner, { command, interval })
//   CommandManager.outputs[command]    // last stdout, trimmed
// Also runs one-off commands: runDetached (a shell string or an argv) for
// widgets and services that don't wait on it (so they start no processes of
// their own), and run() for services that want the output:
//   CommandManager.run(["cmd", "arg"], (exitCode, stdout, stderr) => ..., input)
// `input` (optional) is written to stdin, which is then closed: how secrets
// and clipboard text reach a command without going through argv.
// One-off commands run in axiom (exec.run, exec.spawn: the session's
// `axiom run`, or the greeter's `axiom greeter`); a shell started by hand,
// with no axiom, runs none. The polling still runs here.
QtObject {
  id: root

  // command -> last output (trimmed)
  property var outputs: ({})

  function acquire(owner, request) {
    if (!request?.command) {
      release(owner);
      return;
    }
    _registry.acquire(owner, {
      "command": request.command,
      "interval": Math.max(500, request.interval ?? 5000)
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  // Run a command once, detached: a shell string (a widget's click or
  // middle-click command, run by sh -c) or an argv array, run as is. An
  // empty command does nothing.
  function runDetached(command) {
    if (!command?.length)
      return;
    const argv = Array.isArray(command) ? command : ["sh", "-c", command];
    BackendManager.call("exec.spawn", {
      "argv": argv
    }, error => {
      if (error)
        console.warn(`[CommandManager] ${argv[0]}: ${error.message}`);
    });
  }

  // Runs a command once and calls back with (exitCode, stdout, stderr).
  // With `input` (a string), it's written to stdin, then stdin is closed.
  // A command that can't run, or whose answer is lost (axiom re-exec'd
  // meanwhile), calls back with -1 and the reason as stderr.
  function run(command, callback, input) {
    BackendManager.call("exec.run", {
      "argv": command,
      "input": input ?? null
    }, (error, result) => {
      if (error && error.kind !== "unavailable")
        console.warn(`[CommandManager] ${command[0]}: ${error.message}`);
      if (error)
        callback?.(-1, "", error.message);
      else
        callback?.(result.exitCode, result.stdout, result.stderr);
    });
  }

  // Run a command again now (after an action that may change its output)
  function refresh(command) {
    _runners[command]?.run();
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property var _requests: _registry.requests
  on_RequestsChanged: _sync()

  // command -> runner
  property var _runners: ({})

  property Component _runnerComponent: Component {
    QtObject {
      id: runner
      property string command
      property int interval: 5000

      function run() {
        if (!process.running)
          process.running = true;
      }

      property Timer _timer: Timer {
        interval: runner.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: runner.run()
      }

      property Process _process: Process {
        id: process
        command: ["sh", "-c", runner.command]
        stdout: StdioCollector {
          onStreamFinished: {
            const output = text.trim();
            if (root.outputs[runner.command] !== output)
              root.outputs = Object.assign({}, root.outputs, {
                [runner.command]: output
              });
          }
        }
      }
    }
  }

  function _sync() {
    const intervals = {};
    for (const r of root._requests)
      intervals[r.command] = Math.min(intervals[r.command] ?? r.interval, r.interval);
    const next = {};
    for (const command in intervals) {
      const runner = root._runners[command] ?? root._runnerComponent.createObject(root, {
        "command": command
      });
      runner.interval = intervals[command];
      next[command] = runner;
    }
    for (const command in root._runners) {
      if (!(command in next))
        root._runners[command].destroy();
    }
    root._runners = next;
  }
}
