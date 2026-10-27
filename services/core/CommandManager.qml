pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// Shell commands watched for their output (e.g. a bar Button's label),
// shared by every widget asking for the same command: axiom runs each
// distinct command once per interval (the shortest asked for), only while
// something has acquire()d it (exec.watch, pushed back as exec.outputs).
//   CommandManager.acquire(owner, { command, interval, mode, format })
//   CommandManager.outputs[command]    // last stdout, trimmed
//   CommandManager.values[command]     // with format "json": it parsed
// Also runs one-off commands: runDetached (a shell string or an argv) for
// widgets and services that don't wait on it (so they start no processes of
// their own), and run() for services that want the output:
//   CommandManager.run(["cmd", "arg"], (exitCode, stdout, stderr) => ..., input)
// `input` (optional) is written to stdin, which is then closed: how secrets
// and clipboard text reach a command without going through argv.
// Every command runs in axiom (the session's `axiom run`, or the
// greeter's `axiom greeter`); a shell started by hand, with no axiom, runs
// none.
QtObject {
  id: root

  // command -> last output (trimmed)
  readonly property var outputs: _outputs
  // command -> its output parsed, for a command acquired with format
  // "json" (absent while the output isn't JSON)
  readonly property var values: _values

  // request: { command, interval (ms, default 5000, at least 500), mode
  // ("poll"; "once": run once, then on refresh; "stream": run for as long
  // as it's acquired, each line it prints an output, restarted when it
  // exits), format ("text", or "json": values[command] too) }
  function acquire(owner, request) {
    if (!request?.command) {
      release(owner);
      return;
    }
    _registry.acquire(owner, {
      "command": request.command,
      "interval": request.interval ?? 5000,
      "mode": request.mode ?? "poll",
      "format": request.format ?? "text"
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  // Run a command once, detached: a shell string (a widget's click or
  // middle-click command, run by sh -c) or an argv array, run as is,
  // started in `cwd` when given. An empty command does nothing. Apps start
  // here too, never as qs's children, which inherit its huge pages opt-out
  // (docs/dev/core/memory.md).
  function runDetached(command, cwd) {
    if (!command?.length)
      return;
    // Array.from: a desktop entry's command is a list<string>, not an Array
    const argv = typeof command === "string" ? ["sh", "-c", command] : Array.from(command);
    BackendManager.call("exec.spawn", {
      "argv": argv,
      "cwd": cwd ?? ""
    }, error => {
      if (error)
        console.warn(`[CommandManager] ${argv[0]}: ${error.message}`);
    });
  }

  // Runs a command once and calls back with (exitCode, stdout, stderr).
  // With `input` (a string), it's written to stdin, then stdin is closed.
  // A command that can't run, or whose answer is lost (axiom re-exec'd
  // meanwhile), calls back with -1, the reason as stderr and the error
  // (its `kind` "unavailable" when the answer was lost) as a fourth
  // argument; -1 without it is a command killed by a signal.
  function run(command, callback, input) {
    BackendManager.call("exec.run", {
      "argv": command,
      "input": input ?? null
    }, (error, result) => {
      if (error && error.kind !== "unavailable")
        console.warn(`[CommandManager] ${command[0]}: ${error.message}`);
      if (error)
        callback?.(-1, "", error.message, error);
      else
        callback?.(result.exitCode, result.stdout, result.stderr);
    });
  }

  // Run a command again now (after an action that may change its output)
  function refresh(command) {
    if (command in root._watched)
      BackendManager.call("exec.refresh", {
        "command": command
      }, root._logFailure);
  }

  // -- Private --
  property var _outputs: ({})
  property var _values: ({})
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property var _requests: _registry.requests
  on_RequestsChanged: _sync()

  // command -> { interval, mode, format } as axiom watches it
  property var _watched: ({})

  // One watch per command: the shortest interval, streamed if anyone
  // streams, else polled if anyone polls, parsed if anyone asked for json
  function _sync() {
    const next = {};
    for (const r of root._requests) {
      const w = next[r.command];
      next[r.command] = w ? {
        "interval": Math.min(w.interval, r.interval),
        "mode": [w.mode, r.mode].includes("stream") ? "stream" : [w.mode, r.mode].includes("poll") ? "poll" : "once",
        "format": w.format === "json" || r.format === "json" ? "json" : "text"
      } : {
        "interval": r.interval,
        "mode": r.mode,
        "format": r.format
      };
    }
    const last = root._watched;
    root._watched = next;
    for (const command in next) {
      if (JSON.stringify(next[command]) !== JSON.stringify(last[command]))
        root._watch(command);
    }
    for (const command in last) {
      if (!(command in next) && BackendManager.ready)
        BackendManager.call("exec.unwatch", {
          "command": command
        }, root._logFailure);
    }
  }

  // Sent once greeted (onGreeted watches them all then)
  function _watch(command) {
    if (!BackendManager.ready)
      return;
    const w = root._watched[command];
    BackendManager.call("exec.watch", {
      "command": command,
      "interval": w.interval,
      "mode": w.mode,
      "format": w.format
    }, root._logFailure);
  }

  function _logFailure(error) {
    if (error && error.kind !== "unavailable")
      console.warn(`[CommandManager] ${error.message}`);
  }

  // Each push carries every watched command's output
  Component.onCompleted: {
    BackendManager.listen("exec.outputs", state => {
      const outputs = {};
      const values = {};
      for (const command in state.outputs) {
        const entry = state.outputs[command];
        outputs[command] = entry.text;
        if (entry.value !== undefined)
          values[command] = entry.value;
      }
      root._outputs = outputs;
      root._values = values;
    });
  }
  // A new connection: axiom knows nothing of the watches yet
  property Connections _greeted: Connections {
    target: BackendManager
    function onGreeted() {
      Object.keys(root._watched).forEach(command => root._watch(command));
    }
  }
}
