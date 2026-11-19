pragma Singleton
import QtQuick
import qs.config
import qs.components.methods

// Small JSON state files: createStateHandler(name) gives a shared handler
// per name in Paths.statePath, written through axiom (FileManager.write),
// which makes the folder, 0700 (the clipboard pins are kept here).
// createSessionHandler(name) is the same for state that lasts the login
// session alone, in Paths.runtimePath (on $XDG_RUNTIME_DIR, gone at
// logout): it survives qs reloads and restarts. createFileHandler(path)
// is the same for a file elsewhere (a plain absolute path).
//
// A handler keeps the TEXT of its file, so after the first load (or any
// save) a load is a parse of the cache: a caller changing what load
// returned changes nothing, and an edit of the file by hand during a run
// isn't seen. A file that isn't JSON is kept as <file>.bad (once per run)
// and the fallback is used; JSON of another kind than the fallback's is
// the fallback too (StateShape).
//
// save/update write at once. saveLater is for frequent changes: it writes
// 500 ms after the last call, and a change in that window is lost if the
// shell reloads (a singleton's onDestruction doesn't run at a reload).
QtObject {
  id: root

  /**
     * @brief Creates a state handler for a specific service
     * @param serviceName The name of the service (e.g., "launcher")
     * @returns A handler with load/save/update/saveLater/flush, shared by
     *   every caller asking for the same name
     */
  function createStateHandler(serviceName) {
    return root.createFileHandler(Paths.statePath + serviceName + ".json");
  }

  // The same, kept for the login session alone (Paths.runtimePath +
  // "state/")
  function createSessionHandler(serviceName) {
    return root.createFileHandler(Paths.runtimePath + "state/" + serviceName + ".json");
  }

  // The same for the file at filepath (absolute, plain: no file://)
  function createFileHandler(filepath) {
    const known = root._handlers[filepath];
    if (known)
      return known;
    const handler = {
      // The file's text (null before the first load or save)
      "lastText": null,
      // saveLater's data (or a function building it), not yet in lastText
      "later": undefined,
      "stale": false,
      "pending": false,
      "badWritten": false,
      // The state: the file's content if it has the fallback's kind, else
      // the fallback
      "load": function (fallback) {
        handler._materialize();
        if (handler.lastText !== null)
          return StateShape.parse(handler.lastText, fallback).value;
        const text = FileManager.read(filepath);
        const parsed = StateShape.parse(text, fallback);
        if (!parsed.corrupt) {
          handler.lastText = text;
          return parsed.value;
        }
        if (!handler.badWritten) {
          handler.badWritten = true;
          FileManager.write(filepath + ".bad", text);
          console.warn(`[StateManager] ${filepath} isn't JSON: kept as ${filepath}.bad`);
        }
        return parsed.value;
      },
      // Writes data now; done(error) after, as FileManager.write
      "save": function (data, done) {
        handler._cancel();
        handler.lastText = JSON.stringify(data, null, 2);
        FileManager.write(filepath, handler.lastText, done);
      },
      // The state with patch's keys set, saved and returned
      "update": function (patch) {
        const next = Object.assign({}, handler.load({}), patch);
        handler.save(next);
        return next;
      },
      // Writes data (or what the function returns) 500 ms after the last
      // call; a load meanwhile sees it
      "saveLater": function (data) {
        handler.later = data;
        handler.stale = true;
        handler.pending = true;
        root._pending[filepath] = handler;
        root._saveTimer.restart();
      },
      // Writes a pending saveLater now
      "flush": function () {
        if (!handler.pending)
          return;
        handler._materialize();
        handler._cancel();
        FileManager.write(filepath, handler.lastText);
      },
      "_materialize": function () {
        if (!handler.stale)
          return;
        const later = handler.later;
        handler.lastText = JSON.stringify(typeof later === "function" ? later() : later, null, 2);
        handler.later = undefined;
        handler.stale = false;
      },
      "_cancel": function () {
        handler.later = undefined;
        handler.stale = false;
        handler.pending = false;
        delete root._pending[filepath];
      }
    };
    root._handlers[filepath] = handler;
    return handler;
  }

  // Writes every pending saveLater now
  function flushAll() {
    Object.keys(root._pending).forEach(path => {
      const handler = root._pending[path];
      if (handler)
        handler.flush();
    });
  }

  property var _handlers: ({})
  // Handlers with a saveLater waiting, by path
  property var _pending: ({})

  property Timer _saveTimer: Timer {
    interval: 500
    repeat: false
    onTriggered: root.flushAll()
  }

  // Best effort: it doesn't run at a reload, only at a normal exit
  Component.onDestruction: root.flushAll()
}
