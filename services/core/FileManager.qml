pragma Singleton
import QtQuick
import Quickshell.Io

// Files: synchronous whole-file reads, for the places that need a file's
// contents during a binding or initializer (config, schema, theme, state);
// atomic writes and watching through axiom (file.write, file.watch).
QtObject {
  id: root

  // Replaces the file at path (absolute) with text, atomically, making
  // its folders; done(error) after, error null or { kind, message }.
  // Writes to one path go out one at a time, in the order asked; one cut
  // off by axiom re-execing goes again once it's back
  function write(path, text, done) {
    const queue = root._writes[path];
    if (queue) {
      queue.push({
        "text": text,
        "done": done
      });
      return;
    }
    root._writes[path] = [];
    root._write(path, text, done);
  }

  // Calls fn() whenever path (absolute) changes on disk, except by a
  // write of its own, and fn(true) once after each hello (it may have
  // changed while the watch wasn't set); returns the watch, for
  // unwatch(watch)
  function watch(path, fn) {
    const watch = {
      "path": path,
      "fn": fn
    };
    const watches = root._watched[path] ?? [];
    watches.push(watch);
    root._watched[path] = watches;
    if (watches.length === 1)
      BackendManager.call("file.watch", {
        "path": path
      }, root._logFailure);
    return watch;
  }

  function unwatch(watch) {
    if (!watch)
      return;
    const watches = (root._watched[watch.path] ?? []).filter(other => other !== watch);
    if (watches.length > 0) {
      root._watched[watch.path] = watches;
      return;
    }
    delete root._watched[watch.path];
    BackendManager.call("file.unwatch", {
      "path": watch.path
    }, root._logFailure);
  }

  // Waiting writes by path ({ text, done }), while one is out
  property var _writes: ({})
  // Watchers by path
  property var _watched: ({})

  function _write(path, text, done) {
    BackendManager.call("file.write", {
      "path": path,
      "text": text
    }, error => {
      if (error)
        console.warn("[FileManager] Could not write", path + ":", error.message);
      done?.(error);
      const next = root._writes[path].shift();
      if (next)
        root._write(path, next.text, next.done);
      else
        delete root._writes[path];
    }, {
      "repeatable": true
    });
  }

  // A watch lost with the connection is sent again once greeted
  function _logFailure(error) {
    if (error && error.kind !== "unavailable")
      console.warn("[FileManager] Could not watch a file:", error.message);
  }

  property Connections _backend: Connections {
    target: BackendManager
    // A reconnect forgets the watches, and a change while they weren't
    // set pushed nothing: each watcher looks once (not one whose own
    // write is out, which may still hold the older text)
    function onGreeted() {
      Object.keys(root._watched).forEach(path => {
        BackendManager.call("file.watch", {
          "path": path
        }, root._logFailure);
        if (!(path in root._writes))
          root._watched[path].forEach(watch => watch.fn(true));
      });
    }
  }

  Component.onCompleted: BackendManager.listen("file.changed", change => (root._watched[change.path] ?? []).forEach(watch => watch.fn()))

  // Contents of a file (a file:// URL or an absolute path), or null if it
  // can't be read. A blocking FileView per read, so it needs no
  // QML_XHR_ALLOW_FILE_READ.
  function read(url) {
    const text = String(url);
    // A plain path may hold a "%" (a note's name)
    const path = text.startsWith("file://") ? decodeURIComponent(text.slice(7)) : text;
    const view = root._reader.createObject(root, {
      "path": path
    });
    try {
      const text = view.text();
      return view.loaded ? text : null;
    } catch (e) {
      console.error("[FileManager] Could not read file:", path, e);
      return null;
    } finally {
      view.destroy();
    }
  }

  property Component _reader: Component {
    FileView {
      blockLoading: true
      printErrors: false
    }
  }
}
