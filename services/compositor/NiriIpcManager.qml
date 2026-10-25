pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * niri's IPC socket ($NIRI_SOCKET), without a process per call: its event
 * stream, and requests. Only the Niri* services use it; the rest of the
 * shell asks NiriManager (docs/dev/compositor/niri-backend.md).
 *
 *   NiriIpcManager.request("Windows", windows => …)       // the Ok value, or null
 *   NiriIpcManager.action({ "FocusWindow": { "id": 4 } })  // in order
 *   NiriIpcManager.command({ "Output": { … } })            // any request, in order
 *   NiriIpcManager.event(…)                                // each event, parsed
 *
 * niri answers one request per connection, so each gets its own socket.
 * Actions and other commands run one at a time, in the order sent, so a
 * chain split over several calls can't overtake itself; requests for state
 * go at once. `streamStarted` comes before the stream's first events (the
 * full state, which holds a ConfigLoaded of its own).
 */
QtObject {
  id: root

  readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""

  // Each event of niri's event stream ({ "WindowsChanged": { … } }). The
  // stream starts with the full state (workspaces, windows, keyboard
  // layouts, …), again after it reconnects.
  signal event(var event)
  // The event stream (re)connected: what follows starts with the full state
  signal streamStarted

  // Sends `request` ("Windows", or an object) and calls back with its Ok
  // value, or null when niri refused it (logged) or didn't answer
  function request(request, callback) {
    root._send(request, callback);
  }

  // Runs an action ({ "FocusWorkspace": { … } }) after those sent before,
  // then calls back with whether niri took it
  function action(action, callback) {
    root.command({
      "Action": action
    }, callback);
  }

  // Sends a request that changes something ({ "Output": { … } }, an
  // action) after those sent before, then calls back with whether niri
  // took it
  function command(request, callback) {
    _queue.push({
      "request": request,
      "callback": callback
    });
    if (!_running)
      _next();
  }

  property var _queue: []
  property bool _running: false

  function _next() {
    const item = _queue.shift();
    if (!item) {
      _running = false;
      return;
    }
    _running = true;
    root._send(item.request, reply => {
      item.callback?.(reply !== null);
      root._next();
    });
  }

  function _send(request, callback) {
    if (root.socketPath === "") {
      callback?.(null);
      return;
    }
    const socket = root._socketComponent.createObject(root, {
      "request": JSON.stringify(request)
    });
    socket.finished.connect(line => {
      callback?.(root._okValue(socket.request, line));
      socket.destroy();
    });
    socket.connected = true;
  }

  // A reply line's Ok value, or null (an Err, logged, or nothing)
  function _okValue(request, line) {
    if (line === null)
      return null;
    try {
      const reply = JSON.parse(line);
      if (reply && "Ok" in reply)
        return reply.Ok;
      console.warn(`[NiriIpcManager] ${request.slice(0, 160)}: ${reply?.Err ?? line.slice(0, 200)}`);
    } catch (e) {
      console.warn(`[NiriIpcManager] ${request.slice(0, 160)}: not JSON:`, String(line).slice(0, 200));
    }
    return null;
  }

  property Component _socketComponent: Component {
    Socket {
      id: socket

      property string request
      property bool _done: false
      signal finished(var line)

      function _finish(line) {
        if (socket._done)
          return;
        socket._done = true;
        socket._timeout.stop();
        socket.finished(line);
      }

      path: root.socketPath
      parser: SplitParser {
        onRead: line => {
          socket._finish(line);
          socket.connected = false;
        }
      }
      onConnectionStateChanged: {
        if (socket.connected) {
          socket.write(socket.request + "\n");
          socket.flush();
          socket._timeout.start();
        } else {
          socket._finish(null);
        }
      }
      onError: error => {
        if (!socket.connected)
          socket._finish(null);
      }

      property Timer _timeout: Timer {
        interval: 5000
        onTriggered: {
          console.warn("[NiriIpcManager] No reply from niri to", socket.request.slice(0, 80));
          socket._finish(null);
          socket.connected = false;
        }
      }
    }
  }

  // The event stream: one connection kept open, which niri writes each
  // event to as a line. Connected again a second after it drops (niri
  // restarting).
  property Socket _stream: Socket {
    id: stream

    path: root.socketPath
    connected: root.socketPath !== ""
    parser: SplitParser {
      onRead: line => {
        let parsed = null;
        try {
          parsed = JSON.parse(line);
        } catch (e) {
          console.warn("[NiriIpcManager] event stream: not JSON:", String(line).slice(0, 200));
          return;
        }
        // The stream's first line answers the request itself
        if (parsed && !("Ok" in parsed) && !("Err" in parsed))
          root.event(parsed);
      }
    }
    onConnectionStateChanged: {
      if (stream.connected) {
        root.streamStarted();
        stream.write("\"EventStream\"\n");
        stream.flush();
      } else if (root.socketPath !== "") {
        root._reconnect.start();
      }
    }
    // A connection that never came up changes no state: try it again too
    onError: error => {
      if (!stream.connected && root.socketPath !== "")
        root._reconnect.start();
    }
  }

  property Timer _reconnect: Timer {
    interval: 1000
    onTriggered: stream.connected = true
  }
}
