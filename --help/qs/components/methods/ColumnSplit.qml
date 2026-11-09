pragma Singleton
import QtQuick

// Splits an ordered list of cards into two newspaper columns (the first k on
// the left, the rest on the right) so both end as close together as they
// can, from the cards' heights. Wide cards span both columns and cut the
// list into runs, each split on its own. Used by the settings page. No file
// access, processes or services.
QtObject {
  id: root

  // The height of heights[from..to) stacked with `gap` between them
  function _stack(heights, from, to, gap) {
    let sum = 0;
    for (let i = from; i < to; i++)
      sum += heights[i];
    return to > from ? sum + gap * (to - from - 1) : 0;
  }

  // How many cards go in the left column (0..n): the split whose taller
  // column is shortest, the larger one on a tie (the left column fuller)
  function split(heights, gap) {
    const n = heights.length;
    const total = heights.reduce((sum, height) => sum + height, 0);
    // Running sums, so each split costs O(1)
    let left = total;
    let best = n;
    let bestHeight = Infinity;
    for (let k = n; k >= 0; k--) {
      if (k < n)
        left -= heights[k];
      const right = total - left;
      const tallest = Math.max(k > 0 ? left + gap * (k - 1) : 0, k < n ? right + gap * (n - k - 1) : 0);
      if (tallest < bestHeight) {
        best = k;
        bestHeight = tallest;
      }
    }
    return best;
  }

  // Each card's y within its column, with the first `k` on the left
  function tops(heights, k, gap) {
    const result = [];
    let y = 0;
    for (let i = 0; i < heights.length; i++) {
      if (i === k)
        y = 0;
      result.push(y);
      y += heights[i] + gap;
    }
    return result;
  }

  // The taller column's height, with the first `k` on the left
  function height(heights, k, gap) {
    return Math.max(root._stack(heights, 0, k, gap), root._stack(heights, k, heights.length, gap));
  }

  // The runs of narrow cards between wide ones, as [from, to) pairs. A
  // wide card is a run of its own, as is a narrow card alone between wide
  // ones (or the ends): it takes the whole width rather than leave half
  // empty
  function runs(wide) {
    const result = [];
    const n = wide.length;
    let i = 0;
    while (i < n) {
      let end = i + 1;
      if (!wide[i])
        while (end < n && !wide[end])
          end++;
      result.push({
        "from": i,
        "to": end,
        "wide": !!wide[i] || end - i === 1
      });
      i = end;
    }
    return result;
  }

  // Each run's split (as `split` picks it, within the run; 1 for a run
  // taking the whole width)
  function splits(heights, wide, gap) {
    return root.runs(wide).map(run => run.wide ? 1 : root.split(heights.slice(run.from, run.to), gap));
  }

  // Where each card goes, with each run split by `splits` (one per run):
  // { cards: [{ column: 0 | 1 | -1 (both), y }], height }. A run starts
  // below the taller column of the one before
  function place(heights, wide, splits, gap) {
    const cards = [];
    let y = 0;
    root.runs(wide).forEach((run, r) => {
      const sub = heights.slice(run.from, run.to);
      if (run.wide) {
        cards.push({
          "column": -1,
          "y": y
        });
        y += sub[0] + gap;
        return;
      }
      const k = splits[r] ?? root.split(sub, gap);
      root.tops(sub, k, gap).forEach((top, j) => cards.push({
          "column": j < k ? 0 : 1,
          "y": y + top
        }));
      y += root.height(sub, k, gap) + gap;
    });
    return {
      "cards": cards,
      "height": cards.length > 0 ? y - gap : 0
    };
  }
}
