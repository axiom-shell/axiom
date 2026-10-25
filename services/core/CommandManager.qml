pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Shell commands polled for their output (e.g. a bar Button's label),
// shared by every widget asking for the same command: each distinct
// command runs once per interval (the shortest asked for), only while
// something has acquire()d it.
//   CommandManager.acquire(owner, { command, interval })
//   CommandManager.outputs[command]    // last stdout, trimmed
// Also runs one-off commands: runDetached for widgets (so the UI starts no
// processes of its own), and run() for services that want the output:
//   CommandManager.run(["cmd", "arg"], (exitCode, stdout, stderr) => ..., input)
// `input` (optional) is written to stdin, which is then closed: how secrets
// and clipboard text reach a command without going through argv.
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

  // Run a user-configured shell command once, detached (a widget's click
  // or middle-click command). An empty command does nothing.
  function runDetached(command) {
    if (command)
      Quickshell.execDetached(["sh", "-c", command]);
  }

  // Runs a command once and calls back with (exitCode, stdout, stderr).
  // With `input` (a string), it's written to stdin, then stdin is closed.
  function run(command, callback, input) {
    const process = root._oneShotComponent.createObject(root, {
      "command": command,
      "input": input ?? "",
      "stdinEnabled": input !== null && input !== undefined
    });
    process.done.connect((exitCode, out, err) => {
      callback?.(exitCode, out, err);
      process.destroy();
    });
    process.running = true;
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

  property Component _oneShotComponent: Component {
    Process {
      id: oneShot
      property string input: ""
      signal done(int exitCode, string out, string err)

      stdout: StdioCollector {
        id: oneShotOut
      }
      stderr: StdioCollector {
        id: oneShotErr
      }
      onStarted: {
        if (!oneShot.stdinEnabled)
          return;
        oneShot.write(oneShot.input);
        oneShot.input = "";
        oneShot.stdinEnabled = false; // closes stdin
      }
      onExited: exitCode => oneShot.done(exitCode, oneShotOut.text, oneShotErr.text)
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
