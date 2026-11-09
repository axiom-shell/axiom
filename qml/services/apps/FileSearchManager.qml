pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.system

/*
 * The launcher's file search ("~", and a few files in the main search):
 * the axiom daemon keeps the index of Launcher.providers.files' folders
 * (backend/internal/fileindex, crawled at idle priority, kept current by
 * inotify) and reads those settings itself. This asks it and nothing
 * else: no polling, one call per search, thumbnails only for rows shown.
 *
 * An item is { path, name, dir, mime, icons, size, mtime (ms) }; `dir`
 * is a folder or a link to one. `state` is the index's
 * { phase: off | waiting | loading | crawling | ready, entries, watched,
 * unwatched, unreadable, truncated, error }, pushed as it changes.
 *
 * Searches, listings and the recent files share one sequence: an answer
 * to anything older than the newest asked is dropped, and the daemon
 * stops an older search early (the ids rise per connection).
 */
QtObject {
  id: root

  property var state: ({
      "phase": "off",
      "entries": 0,
      "watched": 0,
      "unwatched": 0,
      "unreadable": 0,
      "truncated": false,
      "error": ""
    })

  // --- Searching ---

  // The three calls only read: one cut off by a lost connection (a
  // re-exec) is sent again, as the text it answers is still shown

  // done({ items, indexed }) with the files best matching `query` (below
  // `dir`, absolute, when given): unless something newer was asked
  // meanwhile. `indexed` is false while there's no index yet, or when it
  // doesn't hold `dir`
  function search(query, dir, limit, done) {
    const id = root._next();
    BackendManager.call("filesearch.query", {
      "id": id,
      "query": query,
      "dir": dir ?? "",
      "limit": limit
    }, (error, result) => {
      if (id !== root._seq || error?.kind === "unavailable")
        return;
      if (error)
        console.warn("[FileSearchManager] search failed:", error.message);
      if (!error && result.stale)
        return;
      done(error ? {
        "items": [],
        "indexed": true
      } : {
        "items": result.items,
        "indexed": result.indexed
      });
    }, {
      "repeatable": true
    });
  }

  // done({ items, total, error }) with the folder's entries from the disk
  // (folders first, or best matching `query`), unless something newer
  // was asked meanwhile; error is why it can't be listed (the error's
  // kind: not_found, failed, …), else ""
  function browse(path, query, limit, done) {
    const id = root._next();
    BackendManager.call("filesearch.browse", {
      "path": path,
      "query": query,
      "limit": limit,
      "hidden": LauncherConfig.fileShowHidden
    }, (error, result) => {
      if (id !== root._seq || error?.kind === "unavailable")
        return;
      done(error ? {
        "items": [],
        "total": 0,
        "error": error.kind
      } : {
        "items": result.items,
        "total": result.total,
        "error": ""
      });
    }, {
      "repeatable": true
    });
  }

  // done(items): the recently used files, newest first
  function recent(limit, done) {
    const id = root._next();
    BackendManager.call("filesearch.recent", {
      "limit": limit
    }, (error, result) => {
      if (id === root._seq && error?.kind !== "unavailable")
        done(error ? [] : result.items);
    }, {
      "repeatable": true
    });
  }

  // --- Acting on a file ---

  // Opens it with its default app, and remembers it (its rank, the recent
  // files)
  function open(path) {
    DefaultAppsManager.open(path);
    BackendManager.call("filesearch.used", {
      "path": path
    }, error => {
      if (error)
        console.warn("[FileSearchManager] remembering an opened file failed:", error.message);
    });
  }

  // Shows it selected in the file manager (FileManager1), else opens its
  // folder
  function reveal(path) {
    BackendManager.call("filesearch.reveal", {
      "path": path
    }, error => {
      if (error)
        console.warn("[FileSearchManager] showing a file in its folder failed:", error.message);
    });
  }

  function copyPath(path) {
    ClipboardManager.copyText(path);
  }

  // --- Icons ---

  // An item's icon as a source the icon theme holds: its type's icons,
  // most specific first, then a folder's or a document's; "" with none
  // (the row shows its glyph)
  function iconFor(item) {
    const key = item.dir ? "inode/directory" : item.mime;
    let icon = root._icons[key];
    if (icon === undefined) {
      const names = (item.icons ?? []).concat(item.dir ? ["folder"] : ["text-x-generic"]);
      icon = "";
      for (const name of names) {
        icon = Quickshell.iconPath(name, true);
        if (icon)
          break;
      }
      root._icons[key] = icon;
    }
    return icon;
  }

  // mime -> icon source; the theme doesn't change while the shell runs
  property var _icons: ({})

  // --- Thumbnails ---

  // key -> the thumbnail's url, "" when there's none. Replaced on each
  // answer, so bindings reading it follow
  property var thumbnails: ({})

  // A file's thumbnail's key (a changed file is another key)
  function thumbnailKey(path, mtime) {
    return path + "\n" + mtime;
  }

  // A shown row wants the thumbnail of `path`; at most 4 are asked at
  // once, and one no row wants by its turn isn't asked
  function want(key, path) {
    root._wanted[key] = (root._wanted[key] ?? 0) + 1;
    if (key in root.thumbnails || root._queued.some(q => q.key === key) || key in root._asking)
      return;
    root._queued.push({
      "key": key,
      "path": path
    });
    root._pump();
  }

  // The row no longer shows it
  function unwant(key) {
    const n = (root._wanted[key] ?? 0) - 1;
    if (n > 0)
      root._wanted[key] = n;
    else
      delete root._wanted[key];
  }

  // key -> count of rows showing it
  property var _wanted: ({})
  // [{ key, path }] waiting for a turn
  property var _queued: []
  // key -> true while asked
  property var _asking: ({})
  property int _inFlight: 0
  readonly property int _maxInFlight: 4
  // Kept past this many, only those still wanted are
  readonly property int _maxThumbnails: 400

  function _pump() {
    while (root._inFlight < root._maxInFlight && root._queued.length > 0) {
      const next = root._queued.shift();
      if (!(next.key in root._wanted))
        continue;
      root._ask(next.key, next.path);
    }
  }

  function _ask(key, path) {
    root._inFlight++;
    root._asking[key] = true;
    // The size the row draws it at (two pixels a point): 128 px or 256 px.
    // A fetch: one cut off by a lost connection is sent again after the
    // next hello
    BackendManager.call("filesearch.thumbnail", {
      "path": path,
      "size": LauncherConfig.iconSize * 2 > 128 ? "large" : "normal"
    }, (error, result) => {
      root._inFlight--;
      delete root._asking[key];
      // No daemon (unavailable): not kept, so a row showing it later asks
      // again; a failure is kept as none, not asked again
      if (error?.kind !== "unavailable")
        root._keep(key, !error && result.path ? "file://" + result.path : "");
      root._pump();
    }, {
      "repeatable": true
    });
  }

  function _keep(key, url) {
    let kept = root.thumbnails;
    if (Object.keys(kept).length >= root._maxThumbnails)
      kept = Object.keys(kept).filter(k => k in root._wanted).reduce((out, k) => {
        out[k] = root.thumbnails[k];
        return out;
      }, {});
    const next = Object.assign({}, kept);
    next[key] = url;
    root.thumbnails = next;
  }

  // --- Private ---

  // The newest call's id: answers to older ones are dropped
  property int _seq: 0

  function _next() {
    return ++root._seq;
  }

  function _fetchState() {
    BackendManager.call("filesearch.get", {}, (error, state) => {
      if (!error)
        root.state = state;
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._fetchState();
    }
  }

  Component.onCompleted: {
    BackendManager.listen("filesearch.state", state => root.state = state);
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetchState();
  }
}
