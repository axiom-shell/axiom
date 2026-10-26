pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system

/*
 * The emoji the launcher searches (";" or /emoji), while Launcher.emoji is on.
 * `entries()` is config/json/emoji.json (built by scripts/generate_emoji.py
 * from Unicode's emoji-test.txt and CLDR's keywords), read the first time
 * it's asked for: [{ e: emoji, n: name, g: group, k: [keywords] }], in
 * Unicode's order. `copy` puts one on the clipboard and counts it in
 * `usage` ({ emoji: { count, last } }), for LauncherManager's frecency;
 * `type` also types it into the focused window (the daemon's virtual
 * keyboard, where the compositor has one: `canType`).
 * `search(query, limit, group)` ranks them for the launcher and the EmojiPicker
 * module (most used first with no query), `groups()` lists Unicode's groups
 * in order.
 */
QtObject {
  id: root

  // { emoji: { count, last } }
  property var usage: ({})
  readonly property bool canType: WaylandManager.typing

  // Every emoji, loaded on first use; [] when the file can't be read
  function entries() {
    if (root._entries === null) {
      const text = FileManager.read(Paths.resourcePath + "json/emoji.json");
      try {
        root._entries = text ? JSON.parse(text) : [];
      } catch (e) {
        console.warn("[EmojiManager] Could not parse emoji.json:", e);
        root._entries = [];
      }
      if (root._entries.length === 0)
        console.warn("[EmojiManager] No emoji: run scripts/generate_emoji.py");
    }
    return root._entries;
  }

  // Most used first with no query (then the rest in Unicode's order), else
  // by name, then keyword, then group (keywords and groups only on a real
  // match: a fuzzy one would match most of them), with use as a tiebreak.
  // `group` keeps to one group (a name from groups(), "" for all)
  function search(query, limit, group) {
    const all = entries();
    const entriesIn = group ? all.filter(e => e.g === group) : all;
    const q = String(query ?? "").trim().toLowerCase();
    const now = Date.now();
    if (q === "") {
      const byEmoji = entriesIn.reduce((found, e) => {
        found[e.e] = e;
        return found;
      }, {});
      const used = Object.keys(root.usage).filter(e => byEmoji[e]).sort((a, b) => Search.frecency(root.usage[b], now) - Search.frecency(root.usage[a], now));
      return used.map(e => byEmoji[e]).concat(entriesIn.filter(e => !root.usage[e.e])).slice(0, limit);
    }
    const scored = [];
    for (let i = 0; i < entriesIn.length; i++) {
      const e = entriesIn[i];
      const keyword = Math.max(0, ...e.k.map(k => Search.score(k, q)).filter(s => s >= 50));
      const groupScore = Search.score(e.g, q);
      const s = Math.max(Search.score(e.n, q), 0.85 * keyword, groupScore >= 50 ? 0.5 * groupScore : 0);
      if (s > 0)
        scored.push({
          e: e,
          i: i,
          s: s + Math.min(25, 8 * Math.log2(1 + Search.frecency(root.usage[e.e], now)))
        });
    }
    scored.sort((a, b) => b.s - a.s || a.i - b.i);
    return scored.slice(0, limit).map(m => m.e);
  }

  // The most used, most first
  function recent(limit) {
    const now = Date.now();
    return Object.keys(root.usage).sort((a, b) => Search.frecency(root.usage[b], now) - Search.frecency(root.usage[a], now)).slice(0, limit);
  }

  // Unicode's groups, in its order
  function groups() {
    if (root._groups === null)
      root._groups = entries().map(e => e.g).filter((g, i, all) => all.indexOf(g) === i);
    return root._groups;
  }

  function copy(emoji) {
    _record(emoji);
    ClipboardManager.copyText(emoji);
  }

  // Types it once the launcher has closed and the window has the keyboard
  function type(emoji) {
    root._typing = emoji;
    _typeLater.restart();
  }

  // --- Private ---

  property var _entries: null
  property var _groups: null
  property string _typing: ""

  property Timer _typeLater: Timer {
    interval: 150
    onTriggered: BackendManager.call("input.type", {
      "text": root._typing
    }, error => {
      if (error)
        console.warn("[EmojiManager] Could not type:", error.message);
    })
  }

  property var _stateHandler: StateManager.createStateHandler("emoji")

  function _record(emoji) {
    usage = Utils.recordUse(usage, emoji, Date.now());
    _stateHandler.save(usage);
  }

  Component.onCompleted: usage = _stateHandler.load({})
}
