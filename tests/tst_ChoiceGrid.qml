import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ChoiceGrid"

  function test_columns_data() {
    // [count, width, comfortable, least, gap, expected, why]
    return [[7, 1000, 120, 80, 8, 7, "one line"], [7, 888, 120, 80, 8, 7, "exactly fits"], [7, 887, 120, 80, 8, 4, "fit 6, 4 + 3"], [7, 600, 120, 80, 8, 4, "fit 4, 4 + 3"], [7, 400, 120, 80, 8, 3, "fit 3, 3 + 3 + 1"], [7, 376, 120, 80, 8, 3, "fit 3"], [7, 375, 120, 80, 8, 2, "fit 2"], [7, 250, 120, 80, 8, 2, "2 + 2 + 2 + 1"], [7, 200, 120, 80, 8, 2, "the floor gives 2, not 1"], [7, 168, 120, 80, 8, 2, "floor boundary"], [7, 167, 120, 80, 8, 1, "two labels do not fit"], [7, 150, 120, 80, 8, 1, "two labels do not fit"], [7, 200, 120, 80, -4, 2, "a negative gap counts as 0"], [3, 380, 120, 80, 8, 3, "one line"], [3, 250, 120, 80, 8, 2, "2 + 1"], [3, 300, 100, 140, 8, 2, "comfortable never below least"], [4, 400, 120, 80, 8, 2, "fit 3, 2 + 2 not 3 + 1"], [5, 400, 120, 80, 8, 3, "3 + 2"], [2, 100, 120, 80, 8, 1, ""], [2, 168, 120, 80, 8, 2, ""], [1, 500, 120, 80, 8, 1, ""], [0, 500, 120, 80, 8, 1, ""], [7, 0, 120, 80, 8, 1, "no width"]];
  }

  function test_columns(data) {
    compare(ChoiceGrid.columns(data[0], data[1], data[2], data[3], data[4]), data[5], data[6]);
  }
}
