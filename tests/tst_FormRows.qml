import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FormRows"

  function row(shown, bodyHeight, shutFold) {
    return {
      "shown": shown,
      "bodyHeight": bodyHeight,
      "shutFold": shutFold === true
    };
  }

  function test_first() {
    const rows = [null, row(false, 20), row(true, 0),
      {
        "label": "not a row"
      },
      row(undefined, 20), row(true, 20)];
    compare(FormRows.first(rows), 4, "skips missing, hidden, empty and non-rows; unknown counts as shown");
    compare(FormRows.first(rows.slice(0, 4)), -1);
    compare(FormRows.first([]), -1);
    compare(FormRows.first(undefined), -1);
  }

  function test_first_moves_when_the_top_hides() {
    const rows = [row(true, 20), row(true, 20)];
    compare(FormRows.first(rows), 0);
    rows[0].shown = false;
    compare(FormRows.first(rows), 1, "the next row is the top once the first hides");
  }

  function test_first_stops_at_a_shown_form() {
    compare(FormRows.first([
      {
        "allHidden": false
      },
      row(true, 20)]), -1, "a form drawing rows comes first: the row after it keeps its divider");
    compare(FormRows.first([
      {
        "allHidden": true
      },
      row(true, 20)]), 1, "a form with every row hidden is skipped");
  }

  function test_endsShut() {
    verify(FormRows.endsShut([row(true, 20), row(true, 20, true)], false));
    verify(!FormRows.endsShut([row(true, 20, true), row(true, 20)], false), "the last decides");
    verify(FormRows.endsShut([row(true, 20, true), row(false, 20)], false), "a hidden last row is skipped");
    verify(FormRows.endsShut([row(true, 20, true),
      {
        "allHidden": true
      }
    ], false), "a hidden form is skipped");
    verify(!FormRows.endsShut([row(true, 20, true)], true), "never while folded");
    verify(!FormRows.endsShut([], false));
    verify(!FormRows.endsShut(undefined, false));
  }

  function test_empty() {
    verify(FormRows.empty([row(false, 20),
      {
        "allHidden": true
      }
    ]), "every counted row hidden");
    verify(!FormRows.empty([row(false, 20), row(true, 20)]));
    verify(!FormRows.empty([row(false, 20),
      {
        "allHidden": false
      }
    ]), "a form with a shown row");
    verify(!FormRows.empty([row(undefined, 20)]), "unknown counts as shown");
    verify(!FormRows.empty([
      {
        "label": "x"
      }
    ]), "nothing counted is not empty");
    verify(!FormRows.empty([]));
  }
}
