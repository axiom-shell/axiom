pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import qs.config
import qs.services.core

/*
 * The clipboard history the launcher searches (":" or /clipboard), while
 * Launcher.clipboard is on. Launcher.clipboardSource picks where it comes from:
 *   axiom     `wl-paste --watch` records text clips, in memory only (kept
 *             across QML reloads, gone on restart). Clips a password manager
 *             marks sensitive (CLIPBOARD_STATE=sensitive) are never recorded.
 *   cliphist  cliphist's history, listed when the launcher asks. While it's
 *             on, axiom records into it too (text and images: a text-only
 *             watcher misses screenshots, and keeps only the HTML of an image
 *             copied in a browser); cliphist drops duplicates, so a watcher
 *             the user runs as well is harmless, and skips sensitive clips.
 *             Images come with a thumbnail: the newest are decoded into
 *             $XDG_RUNTIME_DIR/axiom/clipboard/ (tmpfs, pruned to the listed
 *             ones, removed when turned off).
 * `entries` is [{ id, text, time, image }], newest first (time is 0 for
 * cliphist); an image also has `format` (png, jpeg, …), `dimensions`
 * ("1920x1080"), `size` ("1.2 MiB") and `image`, its thumbnail's url once
 * decoded. HTML that is just an image (a browser's copy, stored beside the
 * image itself) has `html` set and `image` from its src once decoded. Copying back pipes the text to wl-copy's stdin, never through argv.
 *
 * `pins` are text clips the user pinned ([{ id, text, preview, time,
 * pinned: true }], newest first): the one part written to disk
 * ($XDG_STATE_HOME/axiom/ui/clipboardPins.json), kept through clear() and restarts,
 * whichever source is on. A cliphist clip is decoded first, as its listing
 * is only a preview (its lines run together, cut short); the pin keeps that
 * preview as `preview`, which is how its row in the listing is matched.
 * Images can't be pinned.
 */
Singleton {
  id: root

  readonly property bool enabled: LauncherConfig.clipboard
  readonly property bool cliphist: LauncherConfig.clipboardSource === "cliphist"
  // Whether axiom records the clipboard itself
  readonly property bool recording: enabled && !cliphist
  // undefined until checked
  readonly property var cliphistInstalled: DependencyManager.found.cliphist

  property var entries: []
  property var pins: []

  // Longer clips aren't recorded
  readonly property int _maxLength: 100000
  // The newest images given a thumbnail
  readonly property int _maxThumbnails: 50
  readonly property string _thumbDir: Paths.runtimePath + "clipboard"

  // Lists cliphist's history again (axiom's own is always current), at most
  // once a second: the launcher asks on every keystroke
  function refresh() {
    if (!enabled || !cliphist || _list.running || root._deleting > 0 || Date.now() - root._listedAt < 1000)
      return;
    root._listedAt = Date.now();
    DependencyManager.check(["cliphist"]);
    _list.running = true;
  }

  function copy(entry) {
    if (!entry)
      return;
    if (entry.pinned)
      copyText(entry.text);
    else if (cliphist && entry.html)
      _run(["sh", "-c", 'cliphist decode "$1" | wl-copy --type text/html', "sh", entry.id], null);
    else if (cliphist && entry.format)
      _run(["sh", "-c", 'cliphist decode "$1" | wl-copy --type "$2"', "sh", entry.id, "image/" + entry.format], null);
    else if (cliphist)
      _run(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", entry.id], null);
    else
      _run(["wl-copy"], entry.text);
  }

  // Puts text on the clipboard (through wl-copy's stdin, never argv)
  function copyText(text) {
    _run(["wl-copy"], String(text ?? ""));
  }

  function remove(entry) {
    if (!entry)
      return;
    root.entries = root.entries.filter(e => e.id !== entry.id);
    root._listed = "";
    // cliphist delete reads the listed line on stdin. Until it's done a
    // listing would bring the entry back
    if (cliphist) {
      root._deleting++;
      _run(["cliphist", "delete"], entry.id + "\t" + entry.text + "\n", () => {
        root._deleting--;
        root._listedAt = 0;
        root.refresh();
      });
    }
  }

  // Whether a clip can be pinned (text, not an image), and whether it is
  function canPin(entry) {
    return !!entry && !entry.format && !entry.html && !/^\[\[ binary data/.test(entry.text);
  }

  function isPinned(entry) {
    return !!entry && (entry.pinned === true || root.pins.some(p => root._pinMatches(p, entry)));
  }

  function pin(entry) {
    if (!canPin(entry) || isPinned(entry))
      return;
    if (!cliphist || entry.pinned)
      return root._addPin(entry.text, "");
    CommandManager.run(["cliphist", "decode"], (exitCode, stdout) => {
      if (exitCode === 0 && stdout !== "")
        root._addPin(stdout, entry.text);
    }, entry.id + "\t" + entry.text + "\n");
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
    if (cliphist) {
      _run(["cliphist", "wipe"], null);
      _clearThumbnails();
    }
  }

  // --- axiom's own history ---

  // As JSON: a JS array can't cross into the reloaded engine
  PersistentProperties {
    id: _history
    reloadableId: "axiomClipboard"
    property string entries: "[]"
    property int nextId: 1

    // Before this, the saved history hasn't been restored yet: keep what was
    // recorded meanwhile on top of it
    onLoaded: {
      root._restored = true;
      if (root.cliphist)
        return;
      const texts = root.entries.map(e => e.text);
      root.entries = root.entries.concat(JSON.parse(_history.entries).filter(e => !texts.includes(e.text)));
    }
  }

  property bool _restored: false

  onEntriesChanged: {
    if (_restored && !cliphist)
      _history.entries = JSON.stringify(entries);
  }

  function _add(text) {
    if (text.trim() === "" || text.length > root._maxLength)
      return;
    const kept = root.entries.filter(e => e.text !== text).slice(0, Math.max(0, LauncherConfig.clipboardMaxEntries - 1));
    root.entries = [
      {
        "id": String(_history.nextId++),
        "text": text,
        "time": Date.now()
      }
    ].concat(kept);
  }

  // One text clip per ASCII RS; the first is whatever is on the clipboard now
  Process {
    id: _watch
    running: root.recording
    command: ["wl-paste", "--type", "text", "--watch", "sh", "-c", '[ "$CLIPBOARD_STATE" = data ] || exit 0; cat; printf "\\036"']
    stdout: SplitParser {
      splitMarker: "\u001e"
      onRead: data => root._add(data)
    }
  }

  onEnabledChanged: {
    if (!enabled) {
      root.entries = [];
      _clearThumbnails();
    }
  }

  onCliphistChanged: {
    root.entries = [];
    root._listed = "";
    if (!cliphist)
      _clearThumbnails();
  }

  // --- cliphist ---

  readonly property bool _storing: enabled && cliphist && cliphistInstalled === true

  Process {
    running: root._storing
    command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
  }

  Process {
    running: root._storing
    command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
  }

  Process {
    id: _list
    command: ["cliphist", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.cliphist || text === root._listed)
          return;
        if (root._deleting > 0) {
          root._listed = "";
          return;
        }
        root._listed = text;
        const thumbs = root._thumbUrls;
        const entries = text.split("\n").filter(line => line.includes("\t")).map(line => {
          const tab = line.indexOf("\t");
          const entry = {
            "id": line.slice(0, tab),
            "text": line.slice(tab + 1),
            "time": 0,
            "image": ""
          };
          // [[ binary data 1.2 MiB png 1920x1080 ]]
          const binary = entry.text.match(/^\[\[ binary data (.+) (\w+) (\d+x\d+) \]\]$/);
          if (binary) {
            entry.size = binary[1];
            entry.format = binary[2] === "jpg" ? "jpeg" : binary[2];
            entry.dimensions = binary[3];
            entry.image = thumbs[entry.id] ?? "";
          }
          // <meta …><img src="https://…" …>, its src past the listed preview
          if (!binary && /^(?:<meta[^>]*>)?\s*<img\b/i.test(entry.text)) {
            entry.html = true;
            entry.image = thumbs[entry.id] ?? "";
          }
          return entry;
        });
        root.entries = entries;
        root._decodeThumbnails();
      }
    }
  }

  // --- cliphist thumbnails ---

  property real _listedAt: 0
  // cliphist deletes still running
  property int _deleting: 0
  // The last `cliphist list` output, so an unchanged one changes nothing
  property string _listed: ""

  // { id: url } of the thumbnails decoded so far
  property var _thumbUrls: ({})

  function _thumbName(entry) {
    return entry.id + "." + (entry.html ? "html" : entry.format);
  }

  // Decodes the newest images (and image HTML) that have no file yet,
  // removes the files of entries no longer listed and prints the ones there
  // are: an image's name, or an HTML file's name, a tab and its img src
  function _decodeThumbnails() {
    if (_thumbs.running) {
      _thumbs.pending = true;
      return;
    }
    const images = root.entries.filter(e => e.format || e.html).slice(0, root._maxThumbnails);
    const names = images.map(e => _thumbName(e));
    if (names.length === 0 && Object.keys(root._thumbUrls).length === 0)
      return;
    _thumbs.names = names;
    _thumbs.command = ["sh", "-c", ['umask 077; dir="$1"; shift; mkdir -p "$dir" || exit 1', 'for name in "$@"; do', '  [ -s "$dir/$name" ] || { cliphist decode "${name%%.*}" > "$dir/$name.part" && mv "$dir/$name.part" "$dir/$name"; } || rm -f "$dir/$name.part"', 'done', 'for file in "$dir"/*; do', '  [ -e "$file" ] || continue', '  case " $* " in *" ${file##*/} "*) ;; *) rm -f "$file" ;; esac', 'done', 'for name in "$@"; do', '  [ -s "$dir/$name" ] || continue', '  case "$name" in', '    *.html) printf "%s\\t%s\\n" "$name" "$(sed -n \'s/.*<img[^>]*src="\\([^"]*\\)".*/\\1/p\' "$dir/$name" | head -n 1)" ;;', '    *) echo "$name" ;;', '  esac', 'done', 'true'].join("\n"), "sh", root._thumbDir].concat(names);
    _thumbs.running = true;
  }

  function _clearThumbnails() {
    root._listed = "";
    root._thumbUrls = {};
    _run(["rm", "-rf", "--", root._thumbDir], null);
  }

  Process {
    id: _thumbs
    property var names: []
    property bool pending: false
    stdout: StdioCollector {
      id: _thumbsOut
    }
    onExited: exitCode => {
      if (exitCode === 0 && root.cliphist && root.enabled) {
        const urls = {};
        for (const line of _thumbsOut.text.split("\n").filter(l => l !== "")) {
          const [name, src] = line.split("\t");
          if (src === undefined)
            urls[name.split(".")[0]] = "file://" + root._thumbDir + "/" + name;
          else if (/^https?:\/\//.test(src))
            urls[name.split(".")[0]] = src;
        }
        root._thumbUrls = urls;
        if (root.entries.some(e => (e.format || e.html) && (urls[e.id] ?? "") !== e.image))
          root.entries = root.entries.map(e => e.format || e.html ? Object.assign({}, e, {
              "image": urls[e.id] ?? ""
            }) : e);
      }
      if (pending) {
        pending = false;
        root._decodeThumbnails();
      }
    }
  }

  // --- Pins ---

  property var _pinState: StateManager.createStateHandler("clipboardPins")

  // Whether `pin` is the history row `entry`: by its text, or for a
  // cliphist row (a preview) by the preview it was pinned from
  function _pinMatches(pin, entry) {
    return pin.text === entry.text || (!!pin.preview && pin.preview === entry.text);
  }

  // `preview`: the cliphist listing's line it was decoded from, else ""
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

  // --- Processes ---

  function _run(command, input, done) {
    CommandManager.run(command, () => done?.(), input);
  }

  Component.onCompleted: {
    root.pins = _pinState.load([]);
    if (cliphist)
      DependencyManager.check(["cliphist"]);
  }
}
