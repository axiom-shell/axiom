pragma Singleton
import QtQuick

// Lays a settings card's rows, and the settings page's cards, out in newspaper
// columns: how many columns a width holds, which rows must stay together
// (blocks), and where each row goes. No file access, processes or services.
QtObject {
  id: root

  // How many columns `width` holds: round(width / target) clamped to
  // [1, max], lowered while a column would fall under `min` (columns `gap`
  // apart), then never under `least`. No width: `least`
  function count(width, target, min, max, gap, least = 1) {
    if (width <= 0)
      return least;
    let n = Math.max(1, Math.min(max, Math.round(width / target)));
    while (n > 1 && (width - (n - 1) * gap) / n < min)
      n--;
    return Math.max(n, least);
  }

  // A heading row: an `x-fold` header, the intro's `Settings` fold, a
  // nested object's title
  function _heading(row) {
    return row.kind === "group";
  }

  // The context a row sits in: its folds and the path of the innermost
  // nested object (a heading that isn't a fold) it is under. `headings` are
  // the nested objects' paths seen so far
  function _context(row, headings) {
    let nested = "";
    const path = row.path ?? [];
    for (let i = headings.length - 1; i >= 0; i--) {
      const head = headings[i];
      if (head.length < path.length && head.every((part, j) => part === path[j])) {
        nested = head.join(".");
        break;
      }
    }
    return (row.foldedBy ?? "") + "|" + (row.foldedIn ?? "") + "|" + nested;
  }

  // Each row's context, in order
  function _contexts(rows) {
    const headings = [];
    return rows.map(row => {
      if (root._heading(row) && row.fold !== true)
        headings.push(row.path ?? []);
      return root._context(row, headings);
    });
  }

  // A row that spans the row area: a heading, or an `x-wide` field (or `x-row` object)
  function _wide(row) {
    return root._heading(row) || row.schema?.["x-wide"] === true;
  }

  // Whether row `i` continues the unit of the row before it: an `x-beside`
  // row, a dependent row (under an earlier row of the card, RowTree; `levels`)
  // or a row another field draws, in the same context
  function _continues(rows, contexts, levels, i) {
    if (i === 0 || root._wide(rows[i]) || root._wide(rows[i - 1]) || contexts[i] !== contexts[i - 1])
      return false;
    const row = rows[i];
    return row.schema?.["x-beside"] === true || !!row.drawnBy || levels[i] > 0;
  }

  // The units rows must stay together in: [{ from, to, wide, start }],
  // every row once, in order. A heading or an `x-wide` row is a unit alone, `wide` (it spans
  // the row area); any other row starts a unit unless it continues the one
  // before. `start`: the unit's context differs from the previous unit's,
  // which is no heading, so a run of columns starts there
  function blocks(rows) {
    const result = [];
    const contexts = root._contexts(rows);
    const levels = RowTree.plan(rows).levels;
    for (let i = 0; i < rows.length; i++) {
      if (root._continues(rows, contexts, levels, i)) {
        result[result.length - 1].to = i + 1;
        continue;
      }
      const previous = result[result.length - 1];
      result.push({
        "from": i,
        "to": i + 1,
        "wide": root._wide(rows[i]),
        "start": !!previous && !previous.wide && !root._wide(rows[i]) && contexts[i] !== contexts[previous.to - 1]
      });
    }
    return result;
  }

  // Each row's line: [{ line, side }]. An `x-beside` row shares the line of
  // the row before it (side 1, that row 0); every other row is alone on
  // its line (side -1)
  function lines(rows) {
    const contexts = root._contexts(rows);
    const result = [];
    let line = -1;
    for (let i = 0; i < rows.length; i++) {
      const beside = i > 0 && rows[i].schema?.["x-beside"] === true && !root._wide(rows[i]) && !root._wide(rows[i - 1]) && contexts[i] === contexts[i - 1] && result[i - 1].side !== 1;
      if (beside) {
        result[i - 1].side = 0;
        result.push({
          "line": line,
          "side": 1
        });
      } else {
        line++;
        result.push({
          "line": line,
          "side": -1
        });
      }
    }
    return result;
  }

  // Each row's line's height: the tallest row on it
  function _lineHeights(lines, heights) {
    const tallest = {};
    lines.forEach((entry, i) => tallest[entry.line] = Math.max(tallest[entry.line] ?? 0, heights[i] ?? 0));
    return tallest;
  }

  // Each unit's height: its lines stacked, a line as tall as its tallest row
  function blockHeights(blocks, lines, heights) {
    const tallest = root._lineHeights(lines, heights);
    return blocks.map(block => {
      let sum = 0;
      let last = -1;
      for (let i = block.from; i < block.to; i++) {
        if (lines[i].line !== last) {
          sum += tallest[lines[i].line];
          last = lines[i].line;
        }
      }
      return sum;
    });
  }

  // Where each row goes, given where ColumnSplit.placeN put the units
  // (`placed`): { rows: [{ x, y, width, run, column }], height }. A heading
  // spans `width` (column -1); a unit sits in its column, `gap` apart, its
  // lines stacked; an `x-beside` pair takes half a column each, `besideGap`
  // apart
  function place(blocks, lines, heights, placed, width, gap, besideGap) {
    const tallest = root._lineHeights(lines, heights);
    const rows = [];
    blocks.forEach((block, u) => {
      const spot = placed.cards[u] ?? {
        "column": 0,
        "columns": 1,
        "y": 0,
        "run": 0
      };
      const columns = Math.max(1, spot.columns);
      const columnWidth = (width - (columns - 1) * gap) / columns;
      const spans = block.wide || spot.column === -1;
      const x = spans ? 0 : spot.column * (columnWidth + gap);
      const unitWidth = spans ? width : columnWidth;
      let y = spot.y;
      let last = -1;
      for (let i = block.from; i < block.to; i++) {
        const line = lines[i];
        if (line.line !== last && last !== -1)
          y += tallest[last];
        last = line.line;
        const half = (unitWidth - besideGap) / 2;
        rows.push({
          "x": line.side === 1 ? x + half + besideGap : x,
          "y": y,
          "width": line.side === -1 ? unitWidth : half,
          "run": spot.run,
          "column": block.wide ? -1 : spot.column
        });
      }
    });
    return {
      "rows": rows,
      "height": placed.height
    };
  }
}
