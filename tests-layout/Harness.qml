import QtQuick
import qs.components.methods
import qs.services.core

// What the layout tests share: the real Widget, Appearance and Style load over
// the stubbed ConfigManager and ThemeManager (tests-layout/stubs), fed the
// schema's defaults and a bundled theme read from the repo like tests/Shared
// does. `configure` sets one row's scale, density and font and re-assigns the
// whole config, so every reader binding re-runs.
QtObject {
  id: root

  property var _schema: null

  function text(path) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", Qt.resolvedUrl("../" + path), false);
    xhr.send();
    if (xhr.responseText === "")
      throw new Error("empty or unreadable: " + path);
    return xhr.responseText;
  }

  function json(path) {
    return JSON.parse(root.text(path));
  }

  // `row`: { scale (%), density, fontSize, theme (a themes/ file name) }
  function configure(row) {
    if (!root._schema)
      root._schema = root.json("qml/config/json/config.schema.json");
    const live = SchemaValidation.applyDefaults({}, root._schema);
    live.Interface.scale = row.scale ?? 100;
    live.Interface.density = row.density ?? "normal";
    live.Appearance.font.size = row.fontSize ?? 14;
    live.Appearance.font.family = "DejaVu Sans Mono";
    ConfigManager.live = live;
    ThemeManager.defaults = root.json("qml/config/json/theme-defaults.json");
    ThemeManager.currentTheme = root.json("qml/config/themes/" + (row.theme ?? "catppuccin-mocha") + ".json");
  }

  // Every visible text-like item under `item` (a Text: advanceWidth-bearing, with painted sizes)
  function texts(item) {
    const out = [];
    const walk = it => {
      if (it.visible && it.paintedWidth !== undefined && it.lineCount !== undefined)
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  // A piece holds its texts: every visible one's painted rect inside the
  // piece within half a pixel; a one-line text has one line, a wrapping one at
  // most `maxLines`
  function containedProblems(piece) {
    const problems = [];
    for (const t of root.texts(piece)) {
      if (t.text === "")
        continue;
      const at = t.mapToItem(piece, 0, 0);
      if (at.x < -0.5 || at.y < -0.5 || at.x + t.paintedWidth > piece.width + 0.5 || at.y + t.paintedHeight > piece.height + 0.5)
        problems.push(`"${t.text}" painted ${at.x},${at.y} ${t.paintedWidth}x${t.paintedHeight} outside ${piece.width}x${piece.height}`);
      if (t.maximumLineCount < 100 && t.lineCount > t.maximumLineCount)
        problems.push(`"${t.text}" has ${t.lineCount} lines, the cap is ${t.maximumLineCount}`);
    }
    return problems;
  }
}
