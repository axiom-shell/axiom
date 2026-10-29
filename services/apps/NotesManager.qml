pragma Singleton
import QtQuick
import qs.config
import qs.services.core

// Notes: Markdown files in NotesConfig.directory ($XDG_DATA_HOME/axiom/notes/ by
// default, or a linked folder). Paths are relative to that folder, with
// "/" between folders, and can never leave it.
//
// Open notes are shared documents: acquire(path) returns one per file,
// counted, so two Notes modules on one note stay in sync, and release(path)
// saves what's pending. Edits save 600 ms after the last change. A change
// on disk (another editor, a sync) reloads a document unless it has edits
// of its own waiting, which then win.
QtObject {
  id: root

  readonly property string directory: NotesConfig.directory
  // A linked folder that doesn't exist (it's never created)
  property bool directoryMissing: false
  // Opened by a module with nothing else to show
  readonly property string defaultNote: "notes.md"
  // Every note under the folder (relative paths, sorted), for pickers
  property var allNotes: []
  // `gio trash` works; otherwise deleting is permanent
  readonly property bool canTrash: DependencyManager.found.gio === true
  // The last failed file operation, for the UI ("" when none)
  property string error: ""

  // A note or folder moved (renamed) or went to the trash: modules showing
  // it (or something in it) follow
  signal moved(string from, string to)
  signal removed(string path)

  // --- Paths ---

  // A clean relative path, or "" when it's empty or tries to leave the
  // folder (absolute, "..", ".")
  function clean(path) {
    const parts = String(path ?? "").split("/").filter(part => part !== "");
    if (parts.length === 0 || String(path).startsWith("/") || parts.some(part => part === "." || part === ".."))
      return "";
    return parts.join("/");
  }

  function absolute(path) {
    return root.directory + path;
  }

  function nameOf(path) {
    return path.split("/").pop();
  }

  // A note's name without its extension
  function titleOf(path) {
    const name = root.nameOf(path);
    const dot = name.lastIndexOf(".");
    return dot > 0 ? name.slice(0, dot) : name;
  }

  function parentOf(path) {
    const slash = path.lastIndexOf("/");
    return slash < 0 ? "" : path.slice(0, slash);
  }

  // `path` is `folder` or inside it
  function within(path, folder) {
    return path === folder || path.startsWith(folder + "/");
  }

  // --- Documents ---

  property var _docs: ({})

  // The shared document for a note ({ path, text, revision, … }), or null
  // for a path outside the folder. Release it with release(path).
  function acquire(path) {
    const rel = root.clean(path);
    if (rel === "")
      return null;
    let doc = root._docs[rel];
    if (!doc) {
      doc = _docComponent.createObject(root, {
        "path": rel
      });
      root._docs[rel] = doc;
    }
    doc.refs += 1;
    return doc;
  }

  function release(path) {
    const doc = root._docs[path];
    if (!doc)
      return;
    doc.flush();
    doc.refs -= 1;
    if (doc.refs <= 0) {
      delete root._docs[path];
      // After a pending write has gone out
      Qt.callLater(() => doc.destroy());
    }
  }

  function flushAll() {
    Object.keys(root._docs).forEach(path => root._docs[path].flush());
  }

  // --- Search ---

  // The last search's answer ({ query, results }), for the launcher
  property var lastSearch: ({
      "query": "",
      "results": []
    })
  property int _searchSeq: 0
  readonly property int _searchLimit: 50

  // Notes whose name or text contains `query` (case-insensitive), calling
  // back with [{ path, title, line, snippet }]: name matches first (line -1,
  // the snippet their folder), then matching lines (0-based). An answer to
  // an older search is dropped.
  function search(query, callback) {
    const q = String(query ?? "").trim();
    const seq = ++root._searchSeq;
    const deliver = results => {
      if (seq !== root._searchSeq)
        return;
      root.lastSearch = {
        "query": q,
        "results": results
      };
      if (callback)
        callback(results);
    };
    if (q === "") {
      deliver([]);
      return;
    }
    const lower = q.toLowerCase();
    const names = root.allNotes.filter(path => path.toLowerCase().includes(lower)).map(path => ({
          "path": path,
          "title": root.titleOf(path),
          "line": -1,
          "snippet": root.parentOf(path)
        }));
    const includes = NotesConfig.extensions.map(ext => "--include=*." + ext.replace(/[^A-Za-z0-9_-]/g, ""));
    // The query is an argument, never part of the script
    const command = ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 2; shift; exec grep -rinIF -m 5 \"$@\"", "sh", root.directory].concat(includes, ["--", q, "."]);
    root._run(command, (ok, out) => {
      const lines = [];
      out.split("\n").forEach(entry => {
        const match = /^\.\/(.*?):(\d+):(.*)$/.exec(entry);
        if (!match || (!NotesConfig.showHidden && match[1].split("/").some(part => part.startsWith("."))))
          return;
        lines.push({
          "path": match[1],
          "title": root.titleOf(match[1]),
          "line": parseInt(match[2]) - 1,
          "snippet": root._snippet(match[3], lower)
        });
      });
      lines.sort((a, b) => a.path.localeCompare(b.path) || a.line - b.line);
      deliver(names.concat(lines).slice(0, root._searchLimit));
    });
  }

  // A matching line, cut down to about 100 characters around the match
  function _snippet(line, lower) {
    const text = line.trim();
    const at = text.toLowerCase().indexOf(lower);
    if (text.length <= 100 || at < 40)
      return text.length <= 100 ? text : text.slice(0, 100) + "…";
    const start = at - 30;
    return "…" + text.slice(start, start + 100) + (start + 100 < text.length ? "…" : "");
  }

  // --- Opening a note elsewhere (the launcher) ---

  // A note (and 0-based line, or -1) to show in the Notes module at a
  // place ("overlay", "edgeMenu:<id>" or "desktop:<screen>", a module's
  // placeKey): one loaded there shows it at once (openRequested); one
  // loaded in the next few seconds takes it with takeReveal(place)
  signal openRequested(string path, int line, string place)
  property var _pendingReveal: null

  function requestOpen(path, line, place) {
    const rel = root.clean(path);
    if (rel === "")
      return;
    root._pendingReveal = {
      "path": rel,
      "line": line ?? -1,
      "place": place,
      "at": Date.now()
    };
    root.setLastOpened(place, rel);
    root.openRequested(rel, line ?? -1, place);
  }

  // The { path, line } pending for `place`, once, or null
  function takeReveal(place) {
    const pending = root._pendingReveal;
    if (!pending || pending.place !== place)
      return null;
    root._pendingReveal = null;
    return Date.now() - pending.at < 5000 ? pending : null;
  }

  // --- The last note each module showed ---

  property var _state: StateManager.createStateHandler("notes-modules")
  property var _lastOpened: ({})

  function lastOpened(key) {
    return root._lastOpened[key] ?? "";
  }

  function setLastOpened(key, path) {
    if (root._lastOpened[key] === path)
      return;
    const next = Object.assign({}, root._lastOpened);
    next[key] = path;
    root._lastOpened = next;
    root._state.save({
      "lastOpened": next
    });
  }

  // --- Files and folders ---

  // Calls back with the new note's path. `name` may be empty ("Untitled"),
  // a taken name gets a number
  function createNote(folder, name, callback) {
    const base = root._fileName(name) || I18n.tr("Untitled");
    const hasExtension = NotesConfig.extensions.some(ext => base.toLowerCase().endsWith("." + ext));
    root._create(folder, hasExtension ? base.replace(/\.[^.]*$/, "") : base, hasExtension ? base.replace(/^.*\./, "") : "md", callback);
  }

  function createFolder(folder, name, callback) {
    root._create(folder, root._fileName(name) || I18n.tr("New folder"), "", callback);
  }

  // Renames a note or folder in place (same parent). A note keeps its
  // extension when the new name has none.
  function rename(path, name, isFolder, callback) {
    const from = root.clean(path);
    let base = root._fileName(name);
    if (from === "" || base === "")
      return;
    const oldName = root.nameOf(from);
    const ext = /\.[^.]+$/.exec(oldName);
    if (ext && !isFolder && !/\.[^.]+$/.test(base))
      base += ext[0];
    const parent = root.parentOf(from);
    const to = parent === "" ? base : parent + "/" + base;
    if (to === from)
      return;
    root._flushUnder(from);
    root._run(["sh", "-c", "[ -e \"$2\" ] && exit 3; mv -n -- \"$1\" \"$2\"", "sh", root.absolute(from), root.absolute(to)], (ok, out, code) => {
      if (!ok) {
        root._fail(code === 3 ? I18n.tr("{0} already exists", base) : I18n.tr("Couldn't rename {0}", oldName));
        return;
      }
      root._moveDocs(from, to);
      root.moved(from, to);
      root.refreshList();
      if (callback)
        callback(to);
    });
  }

  // To the trash (gio), or deleted when there is none
  function trash(path) {
    const rel = root.clean(path);
    if (rel === "")
      return;
    root._flushUnder(rel);
    const command = root.canTrash ? ["gio", "trash", "--", root.absolute(rel)] : ["rm", "-rf", "--", root.absolute(rel)];
    root._run(command, ok => {
      if (!ok) {
        root._fail(I18n.tr("Couldn't delete {0}", root.nameOf(rel)));
        return;
      }
      // Documents open on it are dropped without saving again
      Object.keys(root._docs).filter(doc => root.within(doc, rel)).forEach(doc => root._docs[doc].discard());
      root.removed(rel);
      root.refreshList();
    });
  }

  // Lists every note (find), for allNotes
  function refreshList() {
    const dir = root.directory;
    const names = NotesConfig.extensions.map(ext => "-o -iname '*." + ext.replace(/[^A-Za-z0-9_-]/g, "") + "'").join(" ").replace(/^-o /, "");
    const hidden = NotesConfig.showHidden ? "" : "-not -path '*/.*'";
    if (names === "") {
      root.allNotes = [];
      return;
    }
    root._run(["sh", "-c", "cd \"$1\" 2>/dev/null || exit 2; find . -maxdepth 8 -type f " + hidden + " \\( " + names + " \\) -print", "sh", dir], (ok, out, code) => {
      root.directoryMissing = code === 2 && NotesConfig.linked;
      if (dir !== root.directory)
        return;
      root.allNotes = ok ? out.split("\n").filter(line => line !== "").map(line => line.replace(/^\.\//, "")).sort((a, b) => a.localeCompare(b)) : [];
    });
  }

  function _fileName(name) {
    // One path segment: no slashes, no leading dots or spaces
    return String(name ?? "").replace(/[\/\x00]/g, "-").replace(/^[\s.]+/, "").trim();
  }

  // Makes <folder>/<base>[ n][.ext] (a file, or a folder without ext)
  function _create(folder, base, ext, callback) {
    const parent = folder === "" ? "" : root.clean(folder);
    if (folder !== "" && parent === "")
      return;
    const script = "dir=\"$1\"; base=\"$2\"; ext=\"$3\"; mkdir -p -- \"$dir\" || exit 1; " + "p=\"$dir$base$ext\"; i=2; while [ -e \"$p\" ]; do p=\"$dir$base $i$ext\"; i=$((i+1)); done; " + "if [ -z \"$ext\" ]; then mkdir -- \"$p\"; else : > \"$p\"; fi || exit 1; printf '%s' \"${p#\"$dir\"}\"";
    root._run(["sh", "-c", script, "sh", root.absolute(parent === "" ? "" : parent + "/"), base, ext === "" ? "" : "." + ext], (ok, out) => {
      if (!ok || out === "") {
        root._fail(I18n.tr("Couldn't create {0}", base));
        return;
      }
      root.refreshList();
      if (callback)
        callback(parent === "" ? out : parent + "/" + out);
    });
  }

  function _flushUnder(path) {
    Object.keys(root._docs).filter(doc => root.within(doc, path)).forEach(doc => root._docs[doc].flush());
  }

  // Open documents follow a rename, keeping their holders
  function _moveDocs(from, to) {
    Object.keys(root._docs).filter(path => root.within(path, from)).forEach(path => {
      const doc = root._docs[path];
      const next = to + path.slice(from.length);
      delete root._docs[path];
      doc.path = next;
      root._docs[next] = doc;
    });
  }

  function _fail(message) {
    console.warn("[NotesManager]", message);
    root.error = message;
    _errorClear.restart();
  }

  // Runs a command, calling back with (ok, stdout, exit code)
  function _run(command, callback) {
    CommandManager.run(command, (code, out) => callback(code === 0, out, code));
  }

  function _start() {
    if (NotesConfig.linked) {
      root.refreshList();
      return;
    }
    root._run(["mkdir", "-p", "--", root.directory], () => root.refreshList());
  }

  onDirectoryChanged: {
    root.flushAll();
    root._start();
  }

  Component.onCompleted: {
    const saved = root._state.load({})?.lastOpened;
    root._lastOpened = saved && typeof saved === "object" ? saved : {};
    DependencyManager.check(["gio"]);
    root._start();
  }

  Component.onDestruction: root.flushAll()

  property Timer _errorClear: Timer {
    id: _errorClear
    interval: 5000
    onTriggered: root.error = ""
  }

  property Component _docComponent: Component {
    QtObject {
      id: doc

      property string path
      // The note's text as last loaded or edited
      property string text: ""
      // Bumped when the text is replaced from disk (not by edit())
      property int revision: 0
      property bool loaded: false
      // Edits waiting to be written
      property bool dirty: false
      property int refs: 0
      // Where it is on disk, and the file watched (FileManager)
      readonly property string _file: root.absolute(doc.path)
      property var _watch: null

      function edit(text) {
        if (text === doc.text)
          return;
        doc.text = text;
        doc.dirty = true;
        doc._saveSoon.restart();
      }

      function flush() {
        doc._saveSoon.stop();
        if (!doc.dirty)
          return;
        doc.dirty = false;
        const path = doc.path;
        FileManager.write(doc._file, doc.text, error => {
          if (error)
            root._fail(I18n.tr("Couldn't save {0}", path));
        });
      }

      // Drops pending edits (the file went to the trash)
      function discard() {
        doc._saveSoon.stop();
        doc.dirty = false;
      }

      function _fromDisk(text) {
        doc.loaded = true;
        if (doc.dirty || text === doc.text)
          return;
        doc.text = text;
        doc.revision += 1;
      }

      property Timer _saveSoon: Timer {
        interval: 600
        onTriggered: doc.flush()
      }

      // A new note: nothing on disk until the first edit
      function _read() {
        const text = FileManager.read(doc._file);
        if (text === null)
          doc.loaded = true;
        else
          doc._fromDisk(text);
      }

      // maybe: axiom reconnected, and the file may not have changed
      function _changed(maybe) {
        if (!doc.dirty)
          doc._read();
        else if (!maybe)
          console.warn("[NotesManager]", doc.path, "changed on disk while it had unsaved edits: keeping the edits");
      }

      // Watches and reads _file (again after a rename or a new folder)
      function _follow() {
        FileManager.unwatch(doc._watch);
        doc._watch = FileManager.watch(doc._file, maybe => doc._changed(maybe));
        doc._read();
      }

      on_FileChanged: doc._follow()
      Component.onCompleted: doc._follow()
      Component.onDestruction: FileManager.unwatch(doc._watch)
    }
  }
}
