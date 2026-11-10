import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "GridPosition"

  function test_line() {
    compare(GridPosition.line(7, 1, 5, 5, false), {
      "line": 1,
      "count": 5
    });
    compare(GridPosition.line(7, 1, 5, 5, true), {
      "line": 1,
      "count": 5
    }, "the column of index 6");
    compare(GridPosition.line(40, 1, 5, 5, false), {
      "line": 0,
      "count": 5
    }, "outside the grid");
    compare(GridPosition.line(12, 11, 5, 2, false), {
      "line": 0,
      "count": 2
    }, "a second monitor's base");
  }

  function test_glyph() {
    const up = ["keyboard_double_arrow_up", "keyboard_arrow_up", "circle", "keyboard_arrow_down", "keyboard_double_arrow_down"];
    for (let i = 0; i < 5; i++)
      compare(GridPosition.glyph(i, 5, false), up[i]);
    compare(GridPosition.glyph(0, 5, true), "keyboard_double_arrow_left");
    compare(GridPosition.glyph(1, 4, false), "keyboard_arrow_up");
    compare(GridPosition.glyph(2, 4, false), "keyboard_arrow_down", "no middle dot with an even count");
  }

  function test_headPips() {
    let h = GridPosition.head(5, 1, false, 30, 14);
    compare(h.kind, "pips");
    compare(h.dot, 3);
    compare(h.gap, 1);
    compare(h.length, 19);
    h = GridPosition.head(5, 1, false, 40, 14);
    compare(h.kind, "pips");
    compare(h.dot, 4);
    compare(h.gap, 2);
    compare(h.length, 28);
    h = GridPosition.head(2, 0, false, 30, 14);
    compare(h.kind, "pips");
    compare(h.dot, 6);
    compare(h.gap, 3);
    compare(h.length, 15);
  }

  function test_headArrow() {
    let h = GridPosition.head(10, 3, false, 30, 14);
    compare(h.kind, "arrow");
    compare(h.glyph, "keyboard_arrow_up", "3 is before the middle, 4.5");
    h = GridPosition.head(5, 0, false, 20, 12);
    compare(h.kind, "arrow");
    compare(h.glyph, "keyboard_double_arrow_up");
  }

  function test_headNone() {
    compare(GridPosition.head(1, 0, false, 30, 14).kind, "none", "a single line has no position");
  }
}
