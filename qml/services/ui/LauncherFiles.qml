pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.apps

/*
 * The launcher's file rows (LauncherManager's part, `_files`): "~" mode
 * (FilePaths.parse: the recent files, a folder's entries, a search
 * everywhere or below a folder) and the few files under the apps in the
 * main search. Answers come later: rowsFor / mainRows return the newest
 * answer's rows (an older text's until the new one lands, so the list
 * doesn't flicker) and ask once per new text; `updated` says new rows are
 * in, and the launcher reads them again, which asks nothing.
 * A row is the launcher's shape plus `thumb` (the file whose thumbnail
 * LauncherRow shows once FileSearchManager has it), `mtime`, and copy()
 * (Ctrl+C: the path).
 */
QtObject {
  id: root

  // New rows are in (an answer, the index's state)
  signal updated

  readonly property string _home: FilePaths.join(Quickshell.env("HOME"), "")
  readonly property int _limit: 50

  // "~" mode's rows for `text` (starting with ~)
  function rowsFor(text) {
    if (text !== root._mode.text) {
      root._mode.text = text;
      root._ask(text);
    }
    return root._modeRows();
  }

  // The main search's file rows for `q` (trimmed): none under two
  // characters, or with Files in the main search at 0
  function mainRows(q) {
    if (!LauncherConfig.files || LauncherConfig.filesInSearch === 0 || q.length < 2) {
      root._mainQ = "";
      root._mainItems = [];
      return [];
    }
    if (q !== root._mainQ) {
      root._mainQ = q;
      // One id sequence: this drops "~" mode's answer in flight
      root._mode.text = null;
      FileSearchManager.search(q, "", LauncherConfig.filesInSearch, answer => {
        if (q !== root._mainQ)
          return;
        root._mainItems = answer.items;
        root.updated();
      });
    }
    return root._mainItems.map(item => root._row(item, true));
  }

  // Asks again on the next read: the launcher closed (it opens to fresh
  // results)
  function forget() {
    root._mode.text = null;
    root._mainQ = "";
  }

  // --- "~" mode ---

  // What the rows show: the text asked for, and its answer { request,
  // phase (the index's when asked), browsed (the folder's own entries),
  // items, total, indexed, error }, null until the first lands
  property var _mode: ({
      "text": null,
      "answer": null
    })

  function _ask(text) {
    // One id sequence: this drops the main search's answer in flight
    root._mainQ = "";
    const request = FilePaths.parse(text, root._home);
    const phase = FileSearchManager.state.phase;
    const land = answer => {
      if (text !== root._mode.text)
        return;
      root._mode = {
        "text": text,
        "answer": Object.assign({
          "request": request,
          "phase": phase,
          "browsed": false,
          "total": 0,
          "indexed": true,
          "error": ""
        }, answer)
      };
      root.updated();
    };
    const browse = () => FileSearchManager.browse(request.dir, request.query, root._limit, answer => land(Object.assign(answer, {
          "browsed": true
        })));
    if (request.kind === "recent")
      FileSearchManager.recent(root._limit, items => land({
          "items": items
        }));
    else if (request.kind === "browse")
      browse();
    else
    // Below a folder the index holds once it's built; else (outside the
    // folders searched: the index answers not indexed; while it builds)
    // the folder's own entries
    if (request.dir === "" || phase === "ready")
      FileSearchManager.search(request.query, request.dir, root._limit, answer => {
        if (answer.indexed || request.dir === "")
          land(answer);
        else
          browse();
      });
    else
      browse();
  }

  function _modeRows() {
    const answer = root._mode.answer;
    if (!answer)
      return [];
    const request = answer.request;
    const rows = answer.items.map(item => root._row(item, false));
    // The daemon's error kind (its message stays English)
    if (answer.error)
      return [root._info(answer.error === "not_found" ? I18n.tr("No such folder") : I18n.tr("This folder can't be read"), Paths.shortenHome(request.dir), "folder_off")];
    if (answer.browsed) {
      if (answer.total > rows.length)
        rows.push(root._info(I18n.tr("{0} more", answer.total - rows.length), I18n.tr("Type to narrow them down"), "more_horiz"));
      return rows.length > 0 ? rows : [root._info(request.query ? I18n.tr("No matches") : I18n.tr("Empty folder"), Paths.shortenHome(request.dir), "folder_open")];
    }
    if (request.kind === "recent")
      return rows.length > 0 ? rows : [root._info(I18n.tr("No recent files"), I18n.tr("Type a name to search your files, or ~/ to browse"), "history")];
    // A search: while the index builds, say so after what it has
    const state = FileSearchManager.state;
    if (state.phase === "off")
      return [root._info(I18n.tr("File search is off"), I18n.tr("Launcher settings › Files"), "search_off")];
    if (!answer.indexed || state.phase === "loading" || state.phase === "crawling" || state.phase === "waiting")
      rows.push(root._info(I18n.tr("Indexing… {0} files", state.entries), I18n.tr("Results grow as it goes"), "manage_search"));
    else if (rows.length === 0)
      rows.push(root._info(I18n.tr("No matches"), state.error ? I18n.tr("The file index couldn't be built") : state.truncated ? I18n.tr("Only the first {0} files are indexed", state.entries) : I18n.tr("{0} files indexed", state.entries), "search_off"));
    return rows;
  }

  // --- The main search ---

  // The query asked for, and the newest answer's items
  property string _mainQ: ""
  property var _mainItems: []

  // --- Rows ---

  // A file or folder: Enter opens it, Shift+Enter shows it in its folder,
  // Tab types its path (a folder's lists it), Ctrl+C copies the path
  function _row(item, inMain) {
    const where = Paths.shortenHome(FilePaths.parentOf(item.path));
    const when = I18n.formatDate(new Date(item.mtime), I18n.dateFormat("mediumDate"));
    return {
      kind: item.dir ? "folder" : "file",
      image: FileSearchManager.iconFor(item),
      glyph: item.dir ? "folder" : "draft",
      thumb: LauncherConfig.fileThumbnails && !item.dir && FilePaths.thumbnailable(item.mime) ? item.path : "",
      mtime: item.mtime,
      title: item.name,
      subtitle: item.dir ? I18n.tr("{0} · {1}", where, when) : I18n.tr("{0} · {1} · {2}", where, Utils.formatBytes(item.size), when),
      hint: inMain ? (item.dir ? I18n.tr("Folder") : I18n.tr("File")) : I18n.tr("Shift+Enter shows it"),
      complete: FilePaths.completion(item.path, root._home, item.dir),
      run: shift => {
        if (shift)
          FileSearchManager.reveal(item.path);
        else
          FileSearchManager.open(item.path);
        return true;
      },
      copy: () => FileSearchManager.copyPath(item.path)
    };
  }

  function _info(title, subtitle, glyph) {
    return {
      kind: "info",
      glyph: glyph,
      title: title,
      subtitle: subtitle,
      run: () => false
    };
  }

  // The index's phase or size changed: a search answered before it was
  // built asks again while shown (at most twice a second, as the state is
  // pushed), until an answer from the built index lands; one the folder's
  // own entries answered (from the disk) only once the phase changes;
  // anything else redraws its info row
  property Connections _index: Connections {
    target: FileSearchManager
    function onStateChanged() {
      const answer = root._mode.answer;
      if (!root.active || root._mode.text === null || !answer)
        return;
      // (also one asked as ready that found no index: a daemon re-exec)
      if (answer.request.kind === "search" && (answer.phase !== "ready" || !answer.indexed) && (!answer.browsed || answer.phase !== FileSearchManager.state.phase))
        root._ask(root._mode.text);
      else
        root.updated();
    }
  }

  // Whether the launcher shows "~" mode (LauncherManager): only then does
  // a change of the index ask again
  property bool active: false
}
