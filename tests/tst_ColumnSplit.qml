import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ColumnSplit"

  // The old two-column `split`: the first column's size
  function first(heights, gap) {
    return ColumnSplit.splitN(heights, 2, gap)[0] ?? 0;
  }

  function test_empty() {
    compare(ColumnSplit.splitN([], 2, 10), []);
    compare(ColumnSplit.placeN([], [], [], 2, 10, [], true).height, 0);
  }

  function test_one() {
    compare(ColumnSplit.splitN([100], 2, 10), [1], "a lone unit goes in the first column");
    compare(ColumnSplit.placeN([100], [false], [[1]], 2, 10, [], false).height, 100);
  }

  function test_equal() {
    compare(first([50, 50], 10), 1);
    compare(first([50, 50, 50, 50], 10), 2);
    compare(first([50, 50, 50], 10), 2, "a tie leaves the first column fuller");
  }

  function test_huge() {
    compare(first([500, 50, 50, 50], 10), 1, "a huge first unit has the first column to itself");
    compare(first([50, 50, 50, 500], 10), 3, "a huge last unit has the last column to itself");
  }

  function test_gap() {
    // Without gaps 60 | 30 + 30 would tie; with them the second column is
    // 70, so both in the first (130) loses to 60 | 70
    compare(first([60, 30, 30], 10), 1);
    compare(ColumnSplit.placeN([60, 30, 30], [false, false, false], [[1, 2]], 2, 10, [], false).height, 70);
  }

  function test_splitN_matches_two_columns() {
    compare(first([], 10), 0);
    compare(first([100], 10), 1);
    compare(first([50, 50, 50], 10), 2);
    compare(first([500, 50, 50, 50], 10), 1);
    compare(first([50, 50, 50, 500], 10), 3);
    compare(first([60, 30, 30], 10), 1);
  }

  function test_splitN_three() {
    compare(ColumnSplit.splitN([50, 50, 50, 50, 50, 50], 3, 10), [2, 2, 2]);
    compare(ColumnSplit.splitN([300, 50, 50, 50, 50], 3, 10), [1, 2, 2], "the rest balances on its own optimum");
    compare(ColumnSplit.splitN([50, 50, 300], 3, 10), [1, 1, 1]);
    compare(ColumnSplit.splitN([50, 50, 50, 50], 3, 10), [2, 1, 1], "ties fill earlier columns");
  }

  function test_splitN_four() {
    compare(ColumnSplit.splitN([50, 50, 50, 50, 50, 50, 50, 50], 4, 10), [2, 2, 2, 2]);
    compare(ColumnSplit.splitN([50, 50, 50], 4, 10), [1, 1, 1], "never an empty column");
  }

  function test_splitN_non_empty() {
    compare(ColumnSplit.splitN([1000, 10, 10, 10], 3, 10), [1, 2, 1]);
  }

  function test_tops_and_height() {
    // 40 60 | 20 30, in two columns
    const placed = ColumnSplit.placeN([40, 60, 20, 30], [false, false, false, false], [[2, 2]], 2, 10, [], false);
    compare(placed.cards.map(card => [card.column, card.y]), [[0, 0], [0, 50], [1, 0], [1, 30]]);
    compare(placed.height, 110);
    const one = ColumnSplit.placeN([40, 60], [false, false], [[2]], 1, 10, [], false);
    compare(one.cards.map(card => card.y), [0, 50]);
  }

  function test_runsN() {
    compare(ColumnSplit.runsN([], []), []);
    compare(ColumnSplit.runsN([false, false, true, false, false], []).map(run => [run.from, run.to, run.wide]), [[0, 2, false], [2, 3, true], [3, 5, false]]);
    compare(ColumnSplit.runsN([false], []).map(run => run.wide), [false], "a lone unit is a narrow run; placeN spans it only with fill");
  }

  function test_runsN_starts() {
    compare(ColumnSplit.runsN([false, false, false, false], [false, false, true, false]).map(run => [run.from, run.to]), [[0, 2], [2, 4]]);
  }

  function test_place_all_narrow() {
    const wide = [false, false, false, false];
    const splits = ColumnSplit.splitsN([40, 60, 20, 30], wide, 2, 10, []);
    compare(splits, [ColumnSplit.splitN([40, 60, 20, 30], 2, 10)]);
    const placed = ColumnSplit.placeN([40, 60, 20, 30], wide, [[2, 2]], 2, 10, [], true);
    compare(placed.cards.map(card => [card.column, card.columns, card.y]), [[0, 2, 0], [0, 2, 50], [1, 2, 0], [1, 2, 30]]);
  }

  function test_placeN_fill() {
    const heights = [50, 50];
    const wide = [false, false];
    const filled = ColumnSplit.placeN(heights, wide, [[1, 1]], 4, 10, [], true);
    compare(filled.cards.map(card => card.columns), [2, 2]);
    const kept = ColumnSplit.placeN(heights, wide, [[1, 1]], 4, 10, [], false);
    compare(kept.cards.map(card => [card.column, card.columns]), [[0, 4], [1, 4]]);
  }

  function test_placeN_wide_and_lone() {
    // wide, then two narrow side by side, then wide
    const wide = [true, false, false, true];
    compare(ColumnSplit.splitsN([100, 50, 70, 30], wide, 2, 10, []), [[1], [1, 1], [1]]);
    let placed = ColumnSplit.placeN([100, 50, 70, 30], wide, [[1], [1, 1], [1]], 2, 10, [], true);
    compare(placed.cards.map(card => [card.column, card.y]), [[-1, 0], [0, 110], [1, 110], [-1, 190]], "a wide unit starts below the taller column");
    compare(placed.height, 220);
    placed = ColumnSplit.placeN([100, 50, 70, 30], wide, [[1], [1, 1], [1]], 3, 10, [], true);
    compare(placed.cards.map(card => [card.column, card.columns]), [[-1, 1], [0, 2], [1, 2], [-1, 1]], "fewer units than columns widen");
    placed = ColumnSplit.placeN([100, 40, 60], [true, false, true], [[1], [1], [1]], 2, 10, [], true);
    compare(placed.cards.map(card => [card.column, card.y]), [[-1, 0], [-1, 110], [-1, 160]], "a lone unit takes the whole width");
    compare(ColumnSplit.placeN([80], [false], [[1]], 2, 10, [], true).cards[0].column, -1);
    compare(ColumnSplit.placeN([80], [false], [[1]], 2, 10, [], false).cards[0].column, 0, "not when it doesn't fill");
  }

  function test_placeN_bad_splits() {
    const heights = [50, 50, 50, 50];
    const wide = [false, false, false, false];
    const good = ColumnSplit.placeN(heights, wide, [[2, 2]], 2, 10, [], true).cards;
    compare(ColumnSplit.placeN(heights, wide, [[1, 1]], 2, 10, [], true).cards, good, "a sum that isn't the run");
    compare(ColumnSplit.placeN(heights, wide, [[1, 1, 2]], 2, 10, [], true).cards, good, "more columns than n");
    compare(ColumnSplit.placeN(heights, wide, [], 2, 10, [], true).cards, good, "none");
  }
}
