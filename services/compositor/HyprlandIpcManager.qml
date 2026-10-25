pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

import qs.components.methods

/*
 * Requests on Hyprland's request socket, as hyprctl makes them but without
 * a process each: what Quickshell.Hyprland doesn't cover (options, Lua
 * evals, binds, devices, layers, the cursor, reloads). Only the Hyprland*
 * services use it; the rest of the shell asks HyprlandManager.
 *
 * Hyprland answers one request per connection, then closes it. Each
 * request gets its own socket, closed by us as soon as the reply is
 * complete (HyprReply.complete): Quickshell warns when the other side
 * closes first.
 *
 *   HyprlandIpcManager.json("clients", clients => …)       // j/clients
 *   HyprlandIpcManager.evalLua("hl.config({ … })", reply => …)  // "ok" or the error
 */
QtObject {
  id: root

  // Sends `command` as hyprctl would ("j/clients", "reload",
  // "switchxkblayout all next") and calls back with the reply, or null when
  // Hyprland didn't answer (no socket, or nothing within 5 s)
  function request(command, callback) {
    const socket = root._socketComponent.createObject(root, {
      "request": command
    });
    socket.finished.connect(reply => {
      callback?.(reply);
      socket.destroy();
    });
    socket.connected = true;
  }

  // `command`'s JSON reply ("clients" asks j/clients), or null
  function json(command, callback) {
    request("j/" + command, reply => {
      const value = reply === null ? null : HyprReply.parse(reply);
      if (reply !== null && value === null)
        console.warn(`[HyprlandIpcManager] ${command}: not JSON:`, reply.slice(0, 200));
      callback?.(value);
    });
  }

  // Several JSON replies in one request (["getoption general:gaps_out",
  // "animations"]), each a value or null
  function jsonBatch(commands, callback) {
    request(HyprReply.batch(commands.map(command => "j/" + command)), reply => {
      callback?.(HyprReply.splitBatch(reply ?? "", commands.length).map(text => HyprReply.parse(text)));
    });
  }

  // Runs a Lua chunk in Hyprland (hl.*) and calls back with its reply,
  // trimmed: "ok", or the error ("" when Hyprland didn't answer)
  function evalLua(lua, callback) {
    request("eval " + lua, reply => callback?.(String(reply ?? "").trim()));
  }

  property Component _socketComponent: Component {
    Socket {
      id: socket

      property string request
      property string _reply: ""
      property bool _done: false
      signal finished(var reply)

      function _finish(reply) {
        if (socket._done)
          return;
        socket._done = true;
        socket._timeout.stop();
        socket.finished(reply);
      }

      path: Hyprland.requestSocketPath
      parser: SplitParser {
        // Everything as it comes: a marker would hold back the last piece,
        // which is only let go on the next marker
        splitMarker: ""
        onRead: data => {
          socket._reply += data;
          if (HyprReply.complete(socket.request, socket._reply))
            socket.connected = false;
        }
      }
      onConnectionStateChanged: {
        if (socket.connected) {
          socket.write(socket.request);
          socket.flush();
          socket._timeout.start();
        } else {
          socket._finish(socket._reply);
        }
      }
      onError: error => {
        if (!socket.connected)
          socket._finish(socket._reply !== "" ? socket._reply : null);
      }

      property Timer _timeout: Timer {
        interval: 5000
        // Finished first: disconnecting finishes with what came, "" at most
        onTriggered: {
          console.warn("[HyprlandIpcManager] No reply from Hyprland to", socket.request.slice(0, 80));
          socket._finish(null);
          socket.connected = false;
        }
      }
    }
  }
}
