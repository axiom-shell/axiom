pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.ui

/*
 * The emoji the launcher searches (";" or /emoji), while Launcher.emoji is on.
 * `entries()` is config/json/emoji.json (built by scripts/gen_emoji.py
 * from Unicode's emoji-test.txt and CLDR's keywords), read the first time
 * it's asked for: [{ e: emoji, n: name, g: group, k: [keywords] }], in
 * Unicode's order. `copy` puts one on the clipboard and counts it in
 * `usage` ({ emoji: { count, last } }), for LauncherManager's frecency;
 * `type` also types it into the focused window (the daemon's virtual
 * keyboard, where the compositor has one: `canType`), or where the focused
 * app can't take it as keys (Chromium and Electron drop characters above
 * U+FFFF from key events) pastes it with Ctrl+V (the clipboard already holds
 * it from copy()), 150 ms after it's called, so call it once that window has
 * the keyboard back.
 * `search(query, limit, group)` ranks them for the launcher and the EmojiPicker
 * module (most used first with no query).
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
        console.warn("[EmojiManager] No emoji: run scripts/gen_emoji.py");
    }
    return root._entries;
  }

  // Most used first with no query (then the rest in Unicode's order), else
  // by name, then keyword, then group (keywords and groups only on a real
  // match: a fuzzy one would match most of them), with use as a tiebreak.
  // `group` keeps to one group (a Unicode group name, "" for all)
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
          s: s + Search.useBonus(Search.frecency(root.usage[e.e], now))
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

  function copy(emoji) {
    _record(emoji);
    ClipboardManager.copyText(emoji);
  }

  // Types it (or pastes it, see the header) a moment after it's called. Call
  // it once the window to type into has the keyboard back; the launcher calls
  // it after its windows have gone (LauncherManager.afterClose). A type is
  // dropped if the launcher reopens before it fires (the emoji stays on the
  // clipboard)
  function type(emoji) {
    root._typing = emoji;
    _typeLater.restart();
  }

  // -- Private --

  property var _entries: null
  property string _typing: ""

  property Timer _typeLater: Timer {
    interval: 150
    onTriggered: {
      if (LauncherManager.shown)
        return;
      const done = error => {
        if (error)
          console.warn("[EmojiManager] Could not type:", error.message);
      };
      if (root._pastes(root._typing))
        BackendManager.call("input.paste", {}, done);
      else
        BackendManager.call("input.type", {
          "text": root._typing
        }, done);
    }
  }

  // Whether text goes by Ctrl+V: the clipboard holds it, it has a codepoint
  // above U+FFFF (QV4 strings are UTF-16, so one shows as a surrogate pair)
  // and the focused window isn't a terminal (desktop entry category
  // TerminalEmulator; no matching entry: not a terminal), which takes keys
  function _pastes(text) {
    if (!ClipboardManager.available || !/[\uD800-\uDBFF][\uDC00-\uDFFF]/.test(text))
      return false;
    const window = CompositorManager.lastFocused(CompositorManager.windows);
    const entry = window ? DesktopEntries.heuristicLookup(window.appId) : null;
    return !(entry?.categories ?? []).includes("TerminalEmulator");
  }

  property var _stateHandler: StateManager.createStateHandler("emoji")

  function _record(emoji) {
    usage = Utils.recordUse(usage, emoji, Date.now());
    _stateHandler.save(usage);
  }

  Component.onCompleted: usage = _stateHandler.load({})
}
