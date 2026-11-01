pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Places `count` tiles in the grid that gives them the largest size in
// this item, never stretched past `maxAspect` either way, with a short
// last row centred. Tiles position themselves from it:
//   Repeater { model: …; ActionTile { required property int index
//     x: grid.tileX(index); y: grid.tileY(index)
//     width: grid.tileWidth; height: grid.tileHeight } }
Item {
  id: root

  property int count: 0
  property real spacing: Widget.spacing
  // Widest a tile may be for its height (and tallest for its width)
  property real maxAspect: 1.6
  // Least a tile is wide for its height (0: any; pills are wide)
  property real minAspect: 0

  readonly property var _fit: {
    const n = Math.max(1, root.count);
    let best = {
      "cols": 1,
      "rows": n,
      "w": 0,
      "h": 0,
      "score": -1
    };
    for (let cols = 1; cols <= n; cols++) {
      const rows = Math.ceil(n / cols);
      let w = (root.width - (cols - 1) * root.spacing) / cols;
      let h = (root.height - (rows - 1) * root.spacing) / rows;
      if (w <= 0 || h <= 0)
        continue;
      w = Math.min(w, h * root.maxAspect);
      h = Math.min(h, w * root.maxAspect);
      if (root.minAspect > 0)
        h = Math.min(h, w / root.minAspect);
      // Bigger tiles first, then fewer empty cells
      const score = Math.min(w, h) - (rows * cols - n) * 0.5;
      if (score > best.score)
        best = {
          "cols": cols,
          "rows": rows,
          "w": w,
          "h": h,
          "score": score
        };
    }
    return best;
  }
  readonly property int columns: _fit.cols
  readonly property int rowCount: _fit.rows
  readonly property real tileWidth: _fit.w
  readonly property real tileHeight: _fit.h

  readonly property real _gridHeight: rowCount * tileHeight + (rowCount - 1) * spacing

  function tileX(i) {
    const row = Math.floor(i / columns);
    const inRow = row === rowCount - 1 ? count - row * columns : columns;
    const rowWidth = inRow * tileWidth + (inRow - 1) * spacing;
    return (width - rowWidth) / 2 + (i % columns) * (tileWidth + spacing);
  }

  function tileY(i) {
    return (height - _gridHeight) / 2 + Math.floor(i / columns) * (tileHeight + spacing);
  }
}
