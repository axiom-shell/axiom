pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core

// NotificationManager's files (its `_files`): the history, saved to
// `historyPath` half a second after a change, and the image cache: an
// entry's picture copied to `dir` as a small PNG (the UI only shows
// thumbnails), since a notification's raw image data is gone once it is.
// Images are rendered in `host`, an item in a window the toast host
// lends, as grabbing an image needs one. `saved(uid, url)` points the
// entry at its copy; if caching fails the entry keeps the original, which
// lasts as long as the notification.
QtObject {
  id: root

  property Item host: null
  // The history, as the manager holds it (written as it is then)
  property var entries: []
  readonly property string historyPath: Paths.userStatePath + "notifications.json"
  readonly property string dir: Paths.userStatePath + "notifications/"

  // The saved entries ([] for none or an unreadable file), as written
  function read() {
    const content = FileManager.read("file://" + root.historyPath);
    if (!content)
      return [];
    try {
      const saved = JSON.parse(content);
      return Array.isArray(saved) ? saved : [];
    } catch (e) {
      console.warn("[NotificationManager] Could not parse", root.historyPath, e);
      return [];
    }
  }

  // Saves the entries (without `live`) shortly
  function save() {
    _writeTimer.restart();
  }

  // Writes a pending save now (the shell closing)
  function flush() {
    if (_writeTimer.running)
      root._write();
  }

  property Timer _writeTimer: Timer {
    interval: 500
    onTriggered: root._write()
  }

  function _write() {
    _writeTimer.stop();
    FileManager.write(root.historyPath, JSON.stringify(root.entries.map(e => Object.assign({}, e, {
        live: undefined
      })), null, 2));
  }

  signal saved(string uid, string url)

  // Whether `source` isn't what uid's copy came from
  function differs(uid, source) {
    return source !== root._sources[uid];
  }

  // Remembers what uid's image (kept as it was) came from
  function adopt(uid, source) {
    root._sources[uid] = source;
  }

  function cache(uid, source) {
    root._sources[uid] = source;
    if (!source)
      return;
    if (!root.host) {
      console.warn("[NotificationManager] No image host yet, not caching", source);
      return;
    }
    const img = grabber.createObject(root.host, {
      source: source
    });
    const done = ok => {
      if (!ok)
        console.warn("[NotificationManager] Could not cache image", source);
      img.destroy();
    };
    const grab = () => {
      if (img.status === Image.Error)
        return done(false);
      if (img.status !== Image.Ready)
        return;
      const scale = Math.min(1, 160 / Math.max(img.implicitWidth, img.implicitHeight, 1));
      img.width = Math.max(1, Math.round(img.implicitWidth * scale));
      img.height = Math.max(1, Math.round(img.implicitHeight * scale));
      const path = root.dir + uid + ".png";
      const ok = img.grabToImage(result => {
        if (!result.saveToFile(path))
          return done(false);
        root.saved(uid, "file://" + path + "?" + Date.now());
        done(true);
      });
      if (!ok)
        done(false);
    };
    img.statusChanged.connect(grab);
    grab();
  }

  // An entry gone: its copy too, unless keepFile (clear() takes them all)
  function forget(entry, keepFile) {
    delete root._sources[entry.uid];
    if (!keepFile && entry.image.startsWith("file://" + root.dir))
      CommandManager.runDetached(["rm", "-f", root._pathOf(entry.image)]);
  }

  // Every copy gone (the history cleared)
  function clear() {
    CommandManager.runDetached(["sh", "-c", "rm -f \"$1\"*.png", "sh", root.dir]);
  }

  // Calls back with the images (file:// urls) no longer on disk (removed by
  // hand), which would warn on every row built from them
  function missing(images, callback) {
    const paths = images.map(image => root._pathOf(image)).filter(p => p !== "");
    if (paths.length === 0)
      return;
    CommandManager.run(["sh", "-c", "for f; do [ -e \"$f\" ] || echo \"$f\"; done", "sh"].concat(paths), (code, out) => {
      const gone = out.split("\n").filter(p => p !== "");
      if (gone.length > 0)
        callback(images.filter(image => gone.includes(root._pathOf(image))));
    }, null, true);
  }

  Component.onCompleted: CommandManager.runDetached(["mkdir", "-p", root.dir])

  // uid -> the image source an entry's copy came from
  property var _sources: ({})

  function _pathOf(image) {
    return image.startsWith("file://") ? image.slice(7).split("?")[0] : "";
  }

  property Component _grabber: Component {
    id: grabber
    Image {
      asynchronous: false
      cache: false
      sourceSize: Qt.size(160, 160)
      fillMode: Image.PreserveAspectFit
    }
  }
}
