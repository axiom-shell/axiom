pragma Singleton
import QtQuick

// Splits an ordered list of units (the settings page's cards, a card's
// rows) into newspaper columns, N of them: contiguous groups from the
// units' heights, so the tallest column is as short as it can be. Wide
// units span every column and cut the list into runs, as do units marked
// as starting a run; each run is split on its own. No file access,
// processes or services.
QtObject {
  id: root

  // The height of heights[from..to) stacked with `gap` between them
  function _stack(heights, from, to, gap) {
    let sum = 0;
    for (let i = from; i < to; i++)
      sum += heights[i];
    return to > from ? sum + gap * (to - from - 1) : 0;
  }

  // The tallest column of the best split of heights[from..) into at most
  // `m` columns: a table of optima by [m][from] (Infinity where impossible)
  function _optima(heights, m, gap) {
    const n = heights.length;
    const table = [];
    for (let c = 0; c <= m; c++) {
      const row = [];
      for (let from = 0; from <= n; from++) {
        if (from === n) {
          row.push(0);
          continue;
        }
        if (c === 0) {
          row.push(Infinity);
          continue;
        }
        if (c === 1) {
          row.push(root._stack(heights, from, n, gap));
          continue;
        }
        let best = Infinity;
        for (let end = from + 1; end <= n; end++) {
          const tallest = Math.max(root._stack(heights, from, end, gap), table[c - 1][end]);
          if (tallest < best)
            best = tallest;
        }
        row.push(best);
      }
      table.push(row);
    }
    return table;
  }

  // The column sizes ([k0, k1, ...], newspaper order) of `heights` in at
  // most `n` columns: the partition whose tallest column is shortest, with
  // min(n, units) non-empty columns. On a tie the first column takes the
  // most units that still let the rest reach the optimum, and the rest is
  // split the same way against its own optimum. [] for none
  function splitN(heights, n, gap) {
    const count = heights.length;
    if (count === 0)
      return [];
    const columns = Math.max(1, Math.min(n, count));
    const table = root._optima(heights, columns, gap);
    const optimum = table[columns][0];
    const sizes = [];
    let from = 0;
    let left = columns;
    // The tallest column the rest may have, the optimum of the whole at first
    let limit = optimum;
    while (from < count) {
      if (left === 1) {
        sizes.push(count - from);
        break;
      }
      // Every column must stay non-empty: leave one unit per column left
      let take = 1;
      for (let end = count - (left - 1); end > from; end--) {
        const here = root._stack(heights, from, end, gap);
        const rest = table[left - 1][end];
        if (here <= limit + 1e-6 && rest <= limit + 1e-6) {
          take = end - from;
          break;
        }
      }
      sizes.push(take);
      from += take;
      left--;
      // The rest balances against its own optimum
      limit = table[left][from];
    }
    return sizes;
  }

  // The runs of units, as { from, to, wide } ([from, to) pairs): a wide
  // unit is a run of its own; narrow units run on until a wide unit or one
  // with `starts[i]`
  function runsN(wide, starts) {
    const result = [];
    const n = wide.length;
    let i = 0;
    while (i < n) {
      let end = i + 1;
      if (!wide[i])
        while (end < n && !wide[end] && !starts?.[end])
          end++;
      result.push({
        "from": i,
        "to": end,
        "wide": !!wide[i]
      });
      i = end;
    }
    return result;
  }

  // Each run's split: [1] for a wide run, else splitN of the run
  function splitsN(heights, wide, n, gap, starts) {
    return root.runsN(wide, starts).map(run => run.wide ? [1] : root.splitN(heights.slice(run.from, run.to), n, gap));
  }

  // Whether `sizes` is a split of `k` units into 1..n columns
  function _valid(sizes, k, n) {
    if (!Array.isArray(sizes) || sizes.length < 1 || sizes.length > n)
      return false;
    let sum = 0;
    for (const size of sizes) {
      if (!Number.isInteger(size) || size < 0)
        return false;
      sum += size;
    }
    return sum === k;
  }

  // Where each unit goes, with each run split by `splits` (one per run; a
  // stale one is split again): { cards: [{ column, columns, y, run }],
  // height }. A wide run: column -1, columns 1. A narrow run takes the
  // column count of its split when `fill` (a lone unit spans: column -1),
  // else n (units keep the n-column width). Units stack with `gap`; a run
  // is as tall as its tallest column and the next starts below it
  function placeN(heights, wide, splits, n, gap, starts, fill) {
    const cards = [];
    let y = 0;
    root.runsN(wide, starts).forEach((run, r) => {
      const sub = heights.slice(run.from, run.to);
      if (run.wide) {
        cards.push({
          "column": -1,
          "columns": 1,
          "y": y,
          "run": r
        });
        y += sub[0] + gap;
        return;
      }
      const given = splits?.[r];
      const sizes = root._valid(given, sub.length, n) ? given : root.splitN(sub, n, gap);
      const columns = fill ? sizes.length : n;
      let tallest = 0;
      let at = 0;
      sizes.forEach((size, c) => {
        let top = 0;
        for (let j = at; j < at + size; j++) {
          cards.push({
            "column": fill && sub.length === 1 ? -1 : c,
            "columns": fill && sub.length === 1 ? 1 : columns,
            "y": y + top,
            "run": r
          });
          top += sub[j] + gap;
        }
        tallest = Math.max(tallest, top > 0 ? top - gap : 0);
        at += size;
      });
      y += tallest + gap;
    });
    return {
      "cards": cards,
      "height": cards.length > 0 ? y - gap : 0
    };
  }
}
