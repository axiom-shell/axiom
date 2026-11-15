pragma Singleton
import QtQuick

import qs.components.methods

// The bar's colour plumbing, beside Style: the theme's raw colours the bar draws in (D-24), its widget colours memoised and its pulse ladders. The bar and the chrome joined to it read colours here; Style never reads this (it builds on the lock screen and in the greeter, D-44).
QtObject {
  id: root

  // What BarEnrich reads of the theme: one object per theme (it depends on
  // Style's roles alone, so a theme switch re-enriches every bar once)
  readonly property var env: ({
      "foreground": Style.resolve("foreground"),
      "background": Style.resolve("background"),
      "resolve": name => Style.resolve(name)
    })

  // A colour the bar's look names, as the theme has it
  function resolve(name) {
    return Style.resolve(name);
  }

  // BarWidgetStyle.widgetColors, memoised: one object per input set. It
  // reads no QML property (every input is an argument), so a binding calling
  // it keeps its dependencies on a hit. The key is the enriched `barConfig`
  // object (replaced on any theme, look or geometry change, kept while
  // equal) and the exact text of the other inputs.
  function widgetColors(barConfig, accentColor, foregroundColor, flags) {
    const memo = root._memo;
    memo.calls++;
    // A colour argument can be a reference to the property it was read from
    // (a QML colour handed to JS), which a result would keep and follow when
    // that property changes: a stored result must hold plain copies
    const accent = root._copy(accentColor);
    const foreground = root._copy(foregroundColor);
    let inner = null;
    for (let i = memo.bars.length - 1; i >= 0; i--) {
      if (memo.bars[i].bar === barConfig) {
        inner = memo.bars[i];
        break;
      }
    }
    if (inner === null) {
      inner = {
        "bar": barConfig,
        "count": 0,
        "byKey": ({})
      };
      memo.bars.push(inner);
      // the oldest bars' entries go (a bar's enriched object is replaced on
      // any theme, look or geometry change)
      if (memo.bars.length > 32)
        memo.bars.shift();
    }
    const key = [Qt.color(accent).toString(), Qt.color(foreground).toString(), flags.splits, flags.hovered, flags.spot, flags.auto, flags.level, flags.muted, flags.pressed].join("|");
    let result = inner.byKey[key];
    if (result !== undefined) {
      memo.hits++;
      if (memo.checkLeft > 0) {
        memo.checkLeft--;
        const direct = BarWidgetStyle.widgetColors(barConfig, accent, foreground, flags);
        const bad = root._differs(result, direct);
        if (bad !== "")
          console.warn("BarColors: memo MISMATCH", bad);
      }
    } else {
      result = BarWidgetStyle.widgetColors(barConfig, accent, foreground, flags);
      // past 1024 entries the bar's inner map starts over
      if (inner.count >= 1024) {
        inner.byKey = ({});
        inner.count = 0;
      }
      inner.byKey[key] = result;
      inner.count++;
    }
    if (memo.calls >= 4096) {
      console.log(`BarColors: widget colours memo ${memo.hits}/${memo.calls} hits`);
      memo.calls = 0;
      memo.hits = 0;
    }
    return result;
  }

  // The steps of a pulse from `colors` to `muted` (BarWidgetStyle.pulseLadder),
  // memoised: a memoised pair is one ladder for every widget sharing it
  function pulseLadder(colors, muted) {
    const memo = root._memo;
    let ladder;
    for (let i = memo.ladders.length - 1; i >= 0; i--) {
      if (memo.ladders[i].colors === colors && memo.ladders[i].muted === muted) {
        ladder = memo.ladders[i].ladder;
        break;
      }
    }
    if (ladder === undefined) {
      ladder = BarWidgetStyle.pulseLadder(colors, muted, BarWidgetStyle.pulseSteps, null);
      memo.ladders.push({
        "colors": colors,
        "muted": muted,
        "ladder": ladder
      });
      if (memo.ladders.length > 64)
        memo.ladders.shift();
    } else if (memo.ladderCheckLeft > 0) {
      memo.ladderCheckLeft--;
      const direct = BarWidgetStyle.pulseLadder(colors, muted, BarWidgetStyle.pulseSteps, null);
      for (let k = 0; k < direct.length; k++) {
        const bad = root._differs(ladder[k], direct[k]);
        if (bad !== "")
          console.warn("BarColors: memo MISMATCH", "ladder", k, bad);
      }
    }
    return ladder;
  }

  // `color` as a plain value, not a reference to a property
  function _copy(color) {
    const c = Qt.color(color);
    return Qt.rgba(c.r, c.g, c.b, c.a);
  }

  // The first key `a` and `b` differ in ("" for none): colours by
  // Qt.colorEqual, everything else by ===
  function _differs(a, b) {
    if (a === b)
      return "";
    const isColor = v => typeof v === "object" && v !== null && v.r !== undefined;
    const keys = Object.keys(a);
    if (keys.length !== Object.keys(b).length)
      return "keys";
    for (const key of keys) {
      const x = a[key];
      const y = b[key];
      if (x === y)
        continue;
      if (isColor(x) && isColor(y)) {
        if (!Qt.colorEqual(x, y))
          return key;
      } else if (typeof x === "string" && isColor(y) || isColor(x) && typeof y === "string") {
        if (!Qt.colorEqual(x, y))
          return key;
      } else if (Array.isArray(x) && Array.isArray(y) && x.length === y.length) {
        if (!x.every((v, i) => v === y[i] || (isColor(v) && isColor(y[i]) && Qt.colorEqual(v, y[i])) || root._differs(v, y[i]) === ""))
          return key;
      } else if (typeof x === "object" && x !== null && typeof y === "object" && y !== null) {
        const inner = root._differs(x, y);
        if (inner !== "")
          return key + "." + inner;
      } else {
        return key;
      }
    }
    return "";
  }

  // mutated in place, never reassigned (a reassignment would notify every
  // binding that called a function reading it: a binding loop inside one)
  readonly property var _memo: ({
      "bars": [],
      "ladders": [],
      "calls": 0,
      "hits": 0,
      "checkLeft": 256,
      "ladderCheckLeft": 64
    })

  // The self-check starts over after a theme switch (a handler, not a read
  // inside the memo functions: no bar binding depends on the revision)
  readonly property Connections _themeWatch: Connections {
    target: Style

    function onRevisionChanged() {
      root._memo.checkLeft = 256;
      root._memo.ladderCheckLeft = 64;
    }
  }
}
