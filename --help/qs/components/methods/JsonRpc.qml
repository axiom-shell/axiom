pragma Singleton
import QtQuick

// JSON-RPC 2.0, one message per line (NDJSON): how the shell talks to the
// axiom binary (BackendManager; docs/dev/backend/README.md). Frames
// requests and replies, and tells an incoming line apart.
QtObject {
  id: root

  function request(id, method, params) {
    const message = {
      "jsonrpc": "2.0",
      "id": id,
      "method": method
    };
    if (params !== undefined)
      message.params = params;
    return JSON.stringify(message) + "\n";
  }

  function result(id, value) {
    return JSON.stringify({
      "jsonrpc": "2.0",
      "id": id,
      "result": value === undefined ? null : value
    }) + "\n";
  }

  // An error reply, its kind in data as the binary's errors carry it
  function error(id, kind, message) {
    return JSON.stringify({
      "jsonrpc": "2.0",
      "id": id,
      "error": {
        "code": -32000,
        "message": message,
        "data": {
          "kind": kind
        }
      }
    }) + "\n";
  }

  // What a line is: { kind: "response" | "request" | "notification" |
  // "invalid", id, method, params, result, error: { kind, message, issues } }
  function parse(line) {
    let m;
    try {
      m = JSON.parse(line);
    } catch (e) {
      return {
        "kind": "invalid",
        "reason": "not JSON"
      };
    }
    if (m === null || typeof m !== "object" || Array.isArray(m) || m.jsonrpc !== "2.0")
      return {
        "kind": "invalid",
        "reason": "not JSON-RPC 2.0"
      };
    if (typeof m.method === "string")
      return {
        "kind": m.id === undefined || m.id === null ? "notification" : "request",
        "id": m.id,
        "method": m.method,
        "params": m.params
      };
    if (m.id === undefined)
      return {
        "kind": "invalid",
        "reason": "neither a call nor a reply"
      };
    if (m.error)
      return {
        "kind": "response",
        "id": m.id,
        "error": {
          "kind": m.error.data?.kind ?? "internal",
          "message": String(m.error.message ?? ""),
          "issues": m.error.data?.issues ?? []
        }
      };
    return {
      "kind": "response",
      "id": m.id,
      "result": m.result
    };
  }
}
