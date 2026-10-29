pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import qs.components.methods

// The shell's connection to the axiom binary, its parent (`axiom run`,
// docs/dev/backend/README.md): JSON-RPC over the socket the binary names
// in $AXIOM_SOCKET. It says hello (the protocol and the schema read),
// relays what the binary pushes (notified), sends calls (queued until the
// hello is answered) and answers the binary's own calls (handle). It
// reconnects when the binary re-execs. Below every other service: it
// reads the environment only, so ConfigManager can stand on it.
// Started without $AXIOM_SOCKET (the shell run by hand, not by axiom), it
// stays inactive.
QtObject {
  id: root

  readonly property string socketPath: Quickshell.env("AXIOM_SOCKET") ?? ""
  readonly property bool active: socketPath !== ""
  // Connected and greeted: calls go out at once
  readonly property bool ready: _hello !== null
  // The binary's daemon.hello answer ({ protocol, version, schemaHash,
  // state, dirs, compatible, reason, … }), null until it came
  readonly property var hello: _hello
  // Set by the binary when it was built for other shell files: config
  // stays read-only and a notice says why (shell.qml). Cleared once axiom
  // says the config is writable (dev mode turned on), never set again
  // while the shell runs: that would take the desktop down
  readonly property string incompatible: _incompatible
  // Whether axiom takes config writes now (it follows dev mode)
  readonly property bool compatible: _compatible
  // Dev mode as axiom has it ({ enabled, available, unavailable,
  // building, lastBuild: { ok, at, output }, binary, installed }):
  // DevManager switches it
  readonly property var dev: _dev

  // A hello was answered (after the first connect and every reconnect)
  signal greeted

  // Calls fn(params) whenever the binary pushes method (config.changed,
  // config.state, schema.changed, …). Not a signal: a parsed object passed
  // through one comes back with its arrays as Qt lists (Array.isArray false)
  function listen(method, fn) {
    const list = root._listeners[method] ?? [];
    list.push(fn);
    root._listeners[method] = list;
  }

  // Calls method; done(error, result) with error null or { kind, message,
  // issues }. Waits for the hello when not connected yet. With options
  // { repeatable: true } (a call the caller knows is safe to send twice:
  // a whole-file write, a fetch), a call cut off by a lost connection is
  // sent again after the next hello instead of failing `unavailable`.
  function call(method, params, done, options) {
    if (!root.active || root._refused) {
      done?.(root._refused ?? {
        "kind": "unavailable",
        "message": "axiom isn't running this shell"
      }, null);
      return;
    }
    const id = root._nextId++;
    root._pending[id] = done ?? null;
    const line = JsonRpc.request(id, method, params);
    if (options?.repeatable)
      root._repeatable[id] = line;
    if (root.ready)
      root._send(line);
    else
      root._queue.push({
        "id": id,
        "line": line
      });
  }

  // Sends a notification (no reply)
  function notify(method, params) {
    if (!root.active)
      return;
    const line = JsonRpc.notification(method, params);
    if (root.ready)
      root._send(line);
    else
      root._queue.push({
        "id": null,
        "line": line
      });
  }

  // Subscribes to a polled topic ({ interval } in ms, plus what the
  // topic's own request carries): axiom fetches it at the shortest
  // interval anyone asked and pushes `<topic>.state` when it changes.
  // Called again, it replaces the request. Kept across reconnects; the
  // service owning the topic merges its consumers into one request
  // (ConsumerRegistry) and listens to the state
  function acquire(topic, request) {
    root._acquired[topic] = request ?? {};
    if (root.ready)
      root._subscribe(topic);
  }

  // Drops the subscription: with nobody else subscribed, axiom stops
  // fetching
  function release(topic) {
    if (!(topic in root._acquired))
      return;
    delete root._acquired[topic];
    if (root.ready)
      root.call(topic + ".unsubscribe", {}, root._logFailure(topic + ".unsubscribe"));
  }

  // Asks axiom to fetch an acquired topic now
  function refresh(topic) {
    if (topic in root._acquired && root.ready)
      root.call(topic + ".refresh", {}, root._logFailure(topic + ".refresh"));
  }

  // Answers the binary's calls of method with fn(params): a result, or a
  // thrown { kind, message }
  function handle(method, fn) {
    root._handlers[method] = fn;
  }

  property var _hello: null
  property string _incompatible: Quickshell.env("AXIOM_INCOMPATIBLE") ?? ""
  property bool _compatible: _incompatible === ""
  property var _dev: ({
      "enabled": false,
      "available": false
    })

  // The parts of the hello that change while axiom runs
  function _applyDaemonState(state) {
    root._compatible = !!state.compatible;
    if (state.compatible)
      root._incompatible = "";
  }
  // The hello's refusal ({ kind, message }): calls fail at once with it
  // until a later connection is greeted
  property var _refused: null
  property int _nextId: 1
  property var _pending: ({})
  // call's repeatable calls not answered yet: { id: line }
  property var _repeatable: ({})
  // Waiting for the hello: { id (null for a notification), line }
  property var _queue: []
  property var _handlers: ({
      "ipc.call": params => root._callTarget(params)
    })
  property var _listeners: ({})
  // acquire's topics: { topic: request }, subscribed again on each hello
  property var _acquired: ({})

  function _subscribe(topic) {
    root.call(topic + ".subscribe", root._acquired[topic], root._logFailure(topic + ".subscribe"));
  }

  function _logFailure(method) {
    return error => {
      if (error && error.kind !== "unavailable")
        console.warn("[BackendManager]", method, "failed:", error.message);
    };
  }
  // The shell's IPC targets (IpcTarget), several per name where each
  // screen has its own and only the enabled one answers
  property var _targets: []

  // IpcTarget's registration: each enabled target's functions (name and
  // argument count) go to axiom, calls come back as ipc.call
  function addTarget(target) {
    root._targets.push(target);
    targetsChanged();
  }

  function removeTarget(target) {
    root._targets = root._targets.filter(t => t !== target);
    targetsChanged();
  }

  function targetsChanged() {
    if (root.active && !root._registerQueued) {
      root._registerQueued = true;
      Qt.callLater(root._register);
    }
  }

  property bool _registerQueued: false

  function _register() {
    root._registerQueued = false;
    const seen = {};
    const targets = [];
    for (const target of root._targets) {
      if (!target.enabled || seen[target.target])
        continue;
      seen[target.target] = true;
      targets.push({
        "name": target.target,
        "functions": root._functions(target).map(name => ({
              "name": name,
              "args": target[name].length
            }))
      });
    }
    root.call("ipc.register", {
      "targets": targets
    }, null);
  }

  // A target's own functions: not its properties' change signals nor
  // its private (`_`) helpers
  function _functions(target) {
    const names = [];
    for (const key in target)
      if (typeof target[key] === "function" && !key.startsWith("_") && !key.endsWith("Changed"))
        names.push(key);
    return names;
  }

  function _callTarget(params) {
    const target = root._targets.find(t => t.target === params.target && t.enabled);
    if (!target)
      throw {
        "kind": "not_found",
        "message": "no enabled target " + params.target
      };
    const fn = target[params.function];
    if (root._functions(target).indexOf(params.function) < 0)
      throw {
        "kind": "not_found",
        "message": params.target + " has no function " + params.function
      };
    const result = fn.apply(target, params.args);
    return result === undefined ? null : result;
  }
  property int _retry: 0

  readonly property int _protocol: {
    const text = FileManager.read(Qt.resolvedUrl("../../config/json/backend.json"));
    try {
      return JSON.parse(text).protocol;
    } catch (e) {
      return 0;
    }
  }
  // The schema's identity, as the binary built it: the shell read this
  // file, and again after schema.changed (`axiom run --dev` rebuilt it),
  // whose hash the next hello then says
  property string _schemaHash: {
    const path = Quickshell.env("AXIOM_SCHEMA") ?? "";
    const text = path ? FileManager.read("file://" + path) : null;
    return text ? Qt.md5(text) : "";
  }

  Component.onCompleted: {
    root.listen("schema.changed", params => {
      if (params.hash)
        root._schemaHash = params.hash;
    });
    root.listen("daemon.state", params => root._applyDaemonState(params));
    root.listen("dev.state", params => root._dev = params);
    // A re-exec or quit closes the connection on purpose: closed from
    // this side first, it's no error (Quickshell's Socket warns on every
    // close it didn't make). Later, not inside the socket's own read
    root.listen("daemon.closing", params => Qt.callLater(root._closing, !!params.reexec));
    root._connect();
  }

  function _send(line) {
    root._socket?.write(line);
    root._socket?.flush();
  }

  function _greet() {
    const id = root._nextId++;
    root._pending[id] = (error, result) => {
      if (error) {
        console.error("[BackendManager] axiom refused the hello:", error.message);
        // Nothing queued would ever go: fail it, and what follows
        root._refused = error;
        root._failQueued(error);
        return;
      }
      root._retry = 0;
      root._greetedSinceDrop = true;
      root._refused = null;
      root._hello = result;
      root._applyDaemonState(result);
      if (result.dev)
        root._dev = result.dev;
      const queued = root._queue;
      root._queue = [];
      queued.forEach(entry => root._send(entry.line));
      // A new connection: axiom knows nothing of the targets or topics yet
      root._register();
      Object.keys(root._acquired).forEach(topic => root._subscribe(topic));
      root.greeted();
    };
    root._send(JsonRpc.request(id, "daemon.hello", {
      "protocol": root._protocol,
      "client": "shell",
      "schemaHash": root._schemaHash,
      "subscribe": true,
      "pid": Quickshell.processId
    }));
  }

  function _onLine(line) {
    const m = JsonRpc.parse(line);
    switch (m.kind) {
    case "response":
      {
        const done = root._pending[m.id];
        delete root._pending[m.id];
        delete root._repeatable[m.id];
        done?.(m.error ?? null, m.error ? null : m.result);
        break;
      }
    case "notification":
      // Each listener on its own: one that throws doesn't keep the push
      // from the rest
      (root._listeners[m.method] ?? []).forEach(fn => {
        try {
          fn(m.params ?? {});
        } catch (e) {
          console.warn("[BackendManager] a", m.method, "listener failed:", e?.message ?? e);
        }
      });
      break;
    case "request":
      root._answer(m);
      break;
    default:
      console.warn("[BackendManager] unreadable message from axiom:", m.reason);
    }
  }

  function _answer(m) {
    const fn = root._handlers[m.method];
    if (!fn) {
      root._send(JsonRpc.error(m.id, "not_found", "the shell has no " + m.method));
      return;
    }
    try {
      root._send(JsonRpc.result(m.id, fn(m.params ?? {})));
    } catch (e) {
      root._send(JsonRpc.error(m.id, e?.kind ?? "internal", String(e?.message ?? e)));
    }
  }

  // Calls in flight or queued when the connection went fail (a failed one
  // is never sent after all), but repeatable ones and queued
  // notifications wait for the next hello, which is said again
  function _dropped() {
    root._hello = null;
    root._failQueued({
      "kind": "unavailable",
      "message": "the connection to axiom closed"
    });
    // At once after a greeted connection: a re-exec hands its listening
    // socket over, so this connection waits for the new image. Any drop
    // after that, before the next hello (a daemon that accepts and then
    // closes), backs off like a failed attempt
    if (root._greetedSinceDrop) {
      root._greetedSinceDrop = false;
      root._connect();
    } else {
      root._reconnect.start();
    }
  }

  // A hello was answered since the last drop: the next drop reconnects
  // at once
  property bool _greetedSinceDrop: false

  // daemon.closing: let the connection go before axiom closes it. After a
  // re-exec the new image answers on the same socket: connect again once
  // the old one is gone. After a quit, back off as after any drop (a shell
  // run apart from `axiom run --no-shell` waits for the next daemon)
  function _closing(reexec) {
    const socket = root._socket;
    if (!socket || !socket.connected)
      return;
    root._retire(socket);
    root._hello = null;
    root._greetedSinceDrop = false;
    root._failQueued({
      "kind": "unavailable",
      "message": "the connection to axiom closed"
    });
    if (reexec)
      root._retry = 0;
    root._reconnect.start();
  }

  // A lost connection (`unavailable`) keeps the repeatable calls: one
  // already sent goes again first, ahead of the queue
  function _failQueued(error) {
    const pending = root._pending;
    root._pending = {};
    const unavailable = error.kind === "unavailable";
    const queued = root._queue.map(entry => String(entry.id));
    const resend = [];
    for (const id in pending) {
      if (!unavailable || !(id in root._repeatable))
        continue;
      root._pending[id] = pending[id];
      delete pending[id];
      if (queued.indexOf(id) < 0)
        resend.push({
          "id": Number(id),
          "line": root._repeatable[id]
        });
    }
    root._queue = unavailable ? resend.concat(root._queue.filter(entry => entry.id === null || entry.id in root._pending)) : [];
    for (const id in pending) {
      delete root._repeatable[id];
      // Through a const: V4 crashes compiling an optional call on a
      // computed member (docs/dev/core/qml-pitfalls.md)
      const done = pending[id];
      if (done)
        done(error, null);
    }
  }

  // One Socket per attempt: Quickshell's Socket keeps a connection that
  // failed and never tries it again (it reconnects only after a
  // `disconnected`, which a connection that never opened doesn't emit),
  // so each attempt gets a fresh one and a finished one is destroyed
  property Socket _socket: null

  property Component _socketComponent: Component {
    Socket {
      id: socket
      path: root.socketPath
      parser: SplitParser {
        onRead: line => {
          if (socket === root._socket)
            root._onLine(line);
        }
      }
      onConnectionStateChanged: {
        if (socket !== root._socket)
          return;
        if (connected) {
          root._greet();
        } else {
          root._retire(socket);
          root._dropped();
        }
      }
      onError: error => {
        if (socket !== root._socket || connected)
          return;
        root._retire(socket);
        root._reconnect.start();
      }
    }
  }

  // Known as _socket before it connects: a Socket opened on a listening
  // path connects (and says so) before `connected = true` returns, and a
  // socket that isn't _socket yet would never say hello
  function _connect() {
    if (!root.active || root._socket !== null)
      return;
    const socket = root._socketComponent.createObject(root);
    root._socket = socket;
    socket.connected = true;
  }

  // A socket whose connection ended or failed: it's let go before it
  // could connect again by itself
  function _retire(socket) {
    root._socket = null;
    socket.connected = false;
    socket.destroy();
  }

  // A re-exec or restart of the binary: try again, a little slower each
  // time, up to every 5 s
  property Timer _reconnect: Timer {
    interval: Math.min(5000, 200 * Math.pow(2, root._retry))
    onTriggered: {
      root._retry++;
      root._connect();
    }
  }
}
