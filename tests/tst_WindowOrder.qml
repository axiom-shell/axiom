import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WindowOrder"

  function win(id, rank, extra) {
    return Object.assign({
      "id": id,
      "focusRank": rank,
      "output": "A"
    }, extra ?? {});
  }

  readonly property var all: () => true

  function test_byFocusHistory() {
    const order = WindowOrder.mru([win("0x3", 2), win("0x1", 0), win("0x2", 1)], all, "");
    compare(order.map(w => w.id), ["0x1", "0x2", "0x3"]);
  }

  function test_activeFirst() {
    // the window list hasn't caught up with a switch to 0x2 yet
    const order = WindowOrder.mru([win("0x1", 0), win("0x2", 1), win("0x3", 2)], all, "0x2");
    compare(order.map(w => w.id), ["0x2", "0x1", "0x3"]);
  }

  function test_filtered() {
    const windows = [win("0x1", 0), win("0x2", 1, {
        "output": "B"
      }), win("0x3", 2)];
    const order = WindowOrder.mru(windows, w => w.output === "A", "0x2");
    compare(order.map(w => w.id), ["0x1", "0x3"], "an active window filtered out stays out");
  }

  function test_missingHistoryLast() {
    const order = WindowOrder.mru([win("0x1", undefined), win("0x2", 0)], all, "");
    compare(order.map(w => w.id), ["0x2", "0x1"]);
  }

  function test_doesNotTouchInput() {
    const windows = [win("0x2", 1), win("0x1", 0)];
    WindowOrder.mru(windows, all, "");
    compare(windows[0].id, "0x2");
  }

  function test_stepIndex() {
    compare(WindowOrder.stepIndex(0, 1, 3), 1);
    compare(WindowOrder.stepIndex(2, 1, 3), 0, "wraps forwards");
    compare(WindowOrder.stepIndex(0, -1, 3), 2, "wraps backwards");
    compare(WindowOrder.stepIndex(0, 1, 1), 0, "one window");
    compare(WindowOrder.stepIndex(0, 1, 0), 0, "none");
  }

  function cellsOf(grid) {
    return grid.cells.map(cell => [cell.column, cell.row]);
  }

  function test_tileGrid_horizontal() {
    const grid = WindowOrder.tileGrid(5, 3, "leftToRight");
    compare([grid.columns, grid.rows], [3, 2]);
    compare(cellsOf(grid), [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1]], "wraps below once a row is full");
    compare(cellsOf(WindowOrder.tileGrid(5, 3, "rightToLeft")), [[2, 0], [1, 0], [0, 0], [2, 1], [1, 1]], "from the right");
  }

  function test_tileGrid_vertical() {
    const grid = WindowOrder.tileGrid(5, 3, "topToBottom");
    compare([grid.columns, grid.rows], [2, 3]);
    compare(cellsOf(grid), [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1]], "wraps to the right once a column is full");
    compare(cellsOf(WindowOrder.tileGrid(5, 3, "bottomToTop")), [[0, 2], [0, 1], [0, 0], [1, 2], [1, 1]], "from the bottom");
  }

  function test_tileGrid_fits_one_line() {
    const grid = WindowOrder.tileGrid(2, 8, "rightToLeft");
    compare([grid.columns, grid.rows], [2, 1], "only as long as the tiles");
    compare(cellsOf(grid), [[1, 0], [0, 0]]);
  }

  function test_tileGrid_edges() {
    compare(WindowOrder.tileGrid(0, 3, "leftToRight"), {
      "columns": 0,
      "rows": 0,
      "cells": []
    });
    compare(cellsOf(WindowOrder.tileGrid(2, 0, "topToBottom")), [[0, 0], [1, 0]], "at least one to a line");
    compare(cellsOf(WindowOrder.tileGrid(2, 2, "")), [[0, 0], [1, 0]], "anything else is left to right");
  }
}
