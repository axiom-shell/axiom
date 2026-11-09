import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WorkspaceCells"

  function test_layout_of_equal_cells() {
    compare(WorkspaceCells.layout([20, 20, 20], 4, -1, 0), {
      "starts": [0, 24, 48],
      "lengths": [20, 20, 20],
      "total": 68
    });
  }

  function test_layout_widens_the_active_cell_by_extra() {
    const row = WorkspaceCells.layout([20, 20, 20], 4, 1, 20);
    compare(row.lengths, [20, 40, 20], "grows by one normal cell, not twice its own length");
    compare(row.starts, [0, 24, 68], "only cells after it move");
    compare(row.total, 88);
  }

  function test_layout_of_cells_of_different_lengths() {
    const row = WorkspaceCells.layout([20, 50, 20], 0, 1, 20);
    compare(row.lengths, [20, 70, 20], "a long cell grows by the normal cell's length too");
    compare(row.starts, [0, 20, 90]);
    compare(row.total, 110);
  }

  function test_layout_of_no_cells() {
    compare(WorkspaceCells.layout([], 4, -1, 0).total, 0);
  }

  function test_startOf() {
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 0), 0);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 2), 78);
    compare(WorkspaceCells.startOf([20, 50, 20], 4, -1), 0, "none: the start");
    compare(WorkspaceCells.startOf([20, 50, 20], 4, 3), 102, "past the end: where a next cell would start");
  }
}
