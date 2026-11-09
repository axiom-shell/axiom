pragma Singleton
import QtQuick

// The Keybinds editor's key map: a US keyboard as rows of keys (by the
// names binds use, KeyNames), and which of them a set of modifiers leaves
// free, given axiom's binds and the user's own.
QtObject {
  id: root

  // A key: { key, label, width } (width in key units; key "" is a gap or a
  // key that can't be bound with modifiers, drawn blank)
  function _k(key, label, width) {
    return {
      "key": key,
      "label": label ?? key.toUpperCase(),
      "width": width ?? 1
    };
  }

  function _blank(label, width) {
    return root._k("", label, width);
  }

  // The main block, row by row, each row 15 units wide
  readonly property var rows: [[_k("Escape", "Esc"), _blank("", 0.5)].concat(Array.from({
      "length": 12
    }, (_, i) => _k("F" + (i + 1), "F" + (i + 1)))).concat([_blank("", 0.5), _k("Delete", "Del")]), [_k("grave", "`")].concat("1234567890".split("").map(digit => _k(digit))).concat([_k("minus", "-"), _k("equal", "="), _k("BackSpace", "⌫", 2)]), [_k("Tab", "Tab", 1.5)].concat("qwertyuiop".split("").map(letter => _k(letter))).concat([_k("bracketleft", "["), _k("bracketright", "]"), _k("backslash", "\\", 1.5)]), [_blank("Caps", 1.75)].concat("asdfghjkl".split("").map(letter => _k(letter))).concat([_k("semicolon", ";"), _k("apostrophe", "'"), _k("Return", "Enter", 2.25)]), [_blank("Shift", 2.25)].concat("zxcvbnm".split("").map(letter => _k(letter))).concat([_k("comma", ","), _k("period", "."), _k("slash", "/"), _blank("Shift", 2.75)]), [_blank("Ctrl", 1.25), _blank("Super", 1.25), _blank("Alt", 1.25), _k("space", "Space", 6), _blank("Alt", 1.25), _k("Left", "←"), _k("Down", "↓"), _k("Up", "↑"), _k("Right", "→")]]

  // Keys off the main block: navigation, the mouse and media keys
  readonly property var extras: [_k("Print", "Print"), _k("Insert", "Ins"), _k("Home", "Home"), _k("End", "End"), _k("Page_Up", "PgUp"), _k("Page_Down", "PgDn"), _k("mouse:272", "LMB"), _k("mouse:273", "RMB"), _k("mouse:274", "MMB"), _k("mouse_up", "Scroll ↑"), _k("mouse_down", "Scroll ↓"), _k("XF86AudioRaiseVolume", "Vol +"), _k("XF86AudioLowerVolume", "Vol −"), _k("XF86AudioMute", "Mute"), _k("XF86AudioMicMute", "Mic"), _k("XF86MonBrightnessUp", "Bright +"), _k("XF86MonBrightnessDown", "Bright −"), _k("XF86AudioPlay", "Play"), _k("XF86AudioNext", "Next"), _k("XF86AudioPrev", "Prev")]

  /**
   * Who holds each key with `mods` held: { [key]: { source, index } },
   * keys as `rows`/`extras` name them. `source` is "axiom" (one of
   * `binds`, not paused; `index` is its index), "both" (that and the
   * user's config too), "paused" (only paused axiom binds), "user" (only
   * the user's config, `userCounts` being BindKeys.userKeyCounts) or
   * "free" (index -1).
   */
  function occupancy(binds, userCounts, mods, keys) {
    const active = {};
    const paused = {};
    (binds ?? []).forEach((bind, index) => {
      const id = BindKeys.keyId(bind.key);
      if (id === "")
        return;
      const into = bind.paused ? paused : active;
      if (into[id] === undefined)
        into[id] = index;
    });
    const result = {};
    for (const key of keys ?? root.allKeys) {
      const id = BindKeys.keyId(KeyNames.join(mods ?? [], key));
      const user = (userCounts ?? {})[id] > 0;
      if (active[id] !== undefined)
        result[key] = {
          "source": user ? "both" : "axiom",
          "index": active[id]
        };
      else if (user)
        result[key] = {
          "source": "user",
          "index": -1
        };
      else if (paused[id] !== undefined)
        result[key] = {
          "source": "paused",
          "index": paused[id]
        };
      else
        result[key] = {
          "source": "free",
          "index": -1
        };
    }
    return result;
  }

  /**
   * What each key does with `mods` held, from the reference's rows
   * (KeybindManager.keybindings): { [key]: { label, action, source, ids } },
   * keys as `rows`/`extras` name them, only those bound. `source` is
   * "axiom", "user" or "both" (the row holds binds of each).
   */
  function labels(sections, mods, keys) {
    const rowById = {};
    for (const section of sections ?? [])
      for (const row of section.binds)
        for (const id of row.ids ?? [])
          if (rowById[id] === undefined)
            rowById[id] = row;
    const result = {};
    for (const key of keys ?? root.allKeys) {
      const id = BindKeys.keyId(KeyNames.join(mods ?? [], key));
      const row = rowById[id];
      if (row)
        result[key] = {
          "label": row.label,
          "action": row.action ?? "",
          "source": row.axiom && row.user ? "both" : row.axiom ? "axiom" : "user",
          "ids": [id]
        };
    }
    return result;
  }

  // A key's label on the map ("bracketleft" -> "[", "XF86AudioMute" ->
  // "Mute"), matched case-insensitively, or "" for a key it doesn't show
  function labelOf(key) {
    return root._labels[String(key ?? "").toLowerCase()] ?? "";
  }
  readonly property var _labels: [].concat(...root.rows).concat(root.extras).filter(k => k.key !== "").reduce((labels, k) => {
    labels[k.key.toLowerCase()] = k.label;
    return labels;
  }, {})

  // Every bindable key the map shows
  readonly property var allKeys: [].concat(...root.rows.map(row => row.filter(k => k.key !== "").map(k => k.key))).concat(root.extras.map(k => k.key))
}
