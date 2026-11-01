import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ChipRows"

  function test_split() {
    compare(ChipRows.split(5, 3), [3, 2]);
    compare(ChipRows.split(7, 3), [3, 2, 2]);
    compare(ChipRows.split(4, 4), [4]);
    compare(ChipRows.split(4, 3), [2, 2], "evened out, not 3 + 1");
    compare(ChipRows.split(3, 0), [1, 1, 1], "always one a row at least");
    compare(ChipRows.split(0, 3), []);
  }

  function test_starts() {
    compare(ChipRows.starts([3, 2, 2]), [0, 3, 5]);
    compare(ChipRows.starts([]), []);
  }
}
