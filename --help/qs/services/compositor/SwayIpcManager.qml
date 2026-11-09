pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.I3
import qs.services.core

/*
 * Requests to sway that want a reply, through swaymsg: what Quickshell.I3
 * doesn't cover (its I3.dispatch runs a command with no reply, and it has no
 * window tree, inputs or outputs in full). Only the Sway* services use it;
 * the rest of the shell asks SwayManager (docs/dev/compositor/sway-backend.md).
 *
 *   SwayIpcManager.json("get_tree", tree => …)       // or null
 *   SwayIpcManager.command("[con_id=4] focus", ok => …)
 *   SwayIpcManager.dispatch("workspace number 2")      // no reply wanted
 *
 * Commands run one at a time, in the order sent, so a chain split over
 * several calls can't overtake itself. Reads run at once.
 */
QtObject {
  id: root

  // Calls back with the reply to a get_* request ("get_tree"), parsed, or
  // null when sway didn't answer
  function json(type, callback) {
    CommandManager.run(["swaymsg", "-r", "-t", type], (exitCode, out) => {
      let value = null;
      try {
        value = JSON.parse(out);
      } catch (e) {
        console.warn(`[SwayIpcManager] ${type}: no reply from sway`, String(out).slice(0, 200));
      }
      callback?.(value);
    }, null, true);
  }

  // Runs sway commands (`text`: one or several, split by ";" or ","), after
  // those sent before, then calls back with whether all of them succeeded.
  // Failures are logged with sway's error.
  function command(text, callback) {
    if (!text) {
      callback?.(true);
      return;
    }
    _queue.push({
      "text": text,
      "callback": callback
    });
    if (!_running)
      _next();
  }

  // Runs sway commands with no reply wanted: at once (I3.dispatch, no
  // process) when nothing sent before is still running, else after it, so
  // they keep their order with command()'s
  function dispatch(text) {
    if (_running)
      command(text);
    else
      I3.dispatch(text);
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
    CommandManager.run(["swaymsg", "-r", "--", item.text], (exitCode, out) => {
      let ok = false;
      try {
        const results = JSON.parse(out);
        // Criteria matching no window (`[all] border …` with none open) are
        // nothing to warn about
        const failed = (Array.isArray(results) ? results : [results]).filter(r => r?.success !== true && r?.error !== "No matching node.");
        failed.forEach(r => console.warn(`[SwayIpcManager] "${item.text.slice(0, 160)}": ${r?.error ?? "failed"}`));
        ok = failed.length === 0;
      } catch (e) {
        console.warn(`[SwayIpcManager] "${item.text.slice(0, 160)}": no reply from sway`);
      }
      item.callback?.(ok);
      root._next();
    });
  }
}
