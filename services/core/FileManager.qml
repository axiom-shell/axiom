pragma Singleton
import QtQuick
import Quickshell.Io

// Synchronous whole-file reads, for the few places that need a file's
// contents during a binding or initializer (config, schema, theme, state).
// Watching and writing stay with FileView.
QtObject {
  id: root

  // Contents of a file (a file:// URL or an absolute path), or null if it
  // can't be read. A blocking FileView per read, so it needs no
  // QML_XHR_ALLOW_FILE_READ.
  function read(url) {
    const path = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
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
