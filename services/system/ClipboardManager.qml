pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.services.core

/*
 * The clipboard history the launcher searches (":" or /clipboard), while
 * Launcher.clipboard is on, and copying for the whole shell. The axiom
 * daemon keeps both (internal/clipboard, on the compositor's data
 * control): the history in memory only (gone on restart), text and
 * images, skipping clips a password manager marks sensitive.
 * `entries` is [{ id, text, time, image }], newest first; text is the
 * clip's first 1000 characters. An image also has `format` (png, jpeg,
 * …), `dimensions` ("1920x1080", when known), `size` ("1.2 MiB") and
 * `image`, its file's url. HTML that is just an image (a browser's copy)
 * has `html` set and `image` from its src. Copying back goes through the
 * daemon, never through argv.
 *
 * `pins` are text clips the user pinned ([{ id, text, preview, time,
 * pinned: true }], newest first): the one part written to disk
 * ($XDG_STATE_HOME/axiom/ui/clipboardPins.json), kept through clear() and
 * restarts. A clip is fetched whole to pin it; the pin keeps the row's
 * text as `preview`, which is how its row is matched. Images can't be
 * pinned. Created from shell.qml's `_services`.
 */
Singleton {
  id: root

  readonly property bool enabled: LauncherConfig.clipboard
  // The compositor offers clipboard control (ext or wlr data control)
  readonly property bool available: WaylandManager.clipboard !== ""
  // It offers none (false until the daemon has said)
  readonly property bool unsupported: WaylandManager.known && !root.available

  property var entries: []
  property var pins: []

  function copy(entry) {
    if (!entry)
      return;
    if (entry.pinned)
      copyText(entry.text);
    else
      _call("clipboard.copy", {
        "id": entry.id
      });
  }

  // Puts text on the clipboard
  function copyText(text) {
    _call("clipboard.copy", {
      "text": String(text ?? "")
    });
  }

  // Puts a file on the clipboard as mime (a screenshot)
  function copyFile(path, mime) {
    _call("clipboard.copy", {
      "path": path,
      "mime": mime
    });
  }

  function remove(entry) {
    if (!entry)
      return;
    root.entries = root.entries.filter(e => e.id !== entry.id);
    _call("clipboard.remove", {
      "id": entry.id
    });
  }

  // Whether a clip can be pinned (text, not an image), and whether it is
  function canPin(entry) {
    return !!entry && !entry.format && !entry.html;
  }

  function isPinned(entry) {
    return !!entry && (entry.pinned === true || root.pins.some(p => root._pinMatches(p, entry)));
  }

  function pin(entry) {
    if (!canPin(entry) || isPinned(entry))
      return;
    if (entry.pinned)
      return root._addPin(entry.text, "");
    BackendManager.call("clipboard.text", {
      "id": entry.id
    }, (error, result) => {
      if (!error)
        root._addPin(result.text, entry.text);
    });
  }

  // A pin, or a history row's pin (matched as isPinned does)
  function unpin(entry) {
    if (!entry)
      return;
    root.pins = root.pins.filter(p => entry.pinned ? p.id !== entry.id : !root._pinMatches(p, entry));
    _pinState.save(root.pins);
  }

  function togglePin(entry) {
    if (isPinned(entry))
      unpin(entry);
    else
      pin(entry);
  }

  function clear() {
    root.entries = [];
    _call("clipboard.clear", {});
  }

  // --- The daemon's history ---

  function _show(state) {
    root.entries = (state?.entries ?? []).map(e => e.format ? Object.assign({}, e, {
        "image": "file://" + e.image
      }) : e);
  }

  function _fetch() {
    BackendManager.call("clipboard.get", {}, (error, state) => {
      if (!error)
        root._show(state);
    });
  }

  function _call(method, params) {
    BackendManager.call(method, params, error => {
      if (error)
        console.warn("[ClipboardManager]", method, "failed:", error.message);
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._fetch();
    }
  }

  // --- Pins ---

  property var _pinState: StateManager.createStateHandler("clipboardPins")

  // Whether `pin` is the history row `entry`: by its text, or for a long
  // clip (the row shows its start) by the row it was pinned from
  function _pinMatches(pin, entry) {
    return pin.text === entry.text || (!!pin.preview && pin.preview === entry.text);
  }

  // `preview`: the row's text it was fetched from, else ""
  function _addPin(text, preview) {
    if (text.trim() === "" || root.pins.some(p => p.text === text))
      return;
    root.pins = [
      {
        "id": "pin" + Date.now(),
        "text": text,
        "preview": preview,
        "time": Date.now(),
        "pinned": true
      }
    ].concat(root.pins);
    _pinState.save(root.pins);
  }

  Component.onCompleted: {
    root.pins = _pinState.load([]);
    BackendManager.listen("clipboard.state", state => root._show(state));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }
}
