import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.CustomWidgets

// FormColumn publishes its top row drawn, which a FormRow in it takes for
// `first` (no divider), moving to the next row when the top one hides; a
// SwitchRow flips on a click off its switch.
TestCase {
  id: root

  name: "FormColumn"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: columnComp

    FormColumn {
      property alias row1: row1
      property alias row2: row2
      property alias flip: flip
      property int flips: 0
      width: 300

      FormRow {
        id: row1
        bodyHeight: Widget.height
      }
      FormRow {
        id: row2
        bodyHeight: Widget.height
      }
      SwitchRow {
        id: flip
        label: "Flip"
        checked: false
        onToggled: newValue => parent.flips++
      }
    }
  }

  Component {
    id: afterFormComp

    FormColumn {
      property alias form: form
      property alias after: after
      width: 300

      Item {
        id: form
        property bool allHidden: false
        implicitHeight: 10
      }
      FormRow {
        id: after
        bodyHeight: Widget.height
      }
    }
  }

  Component {
    id: cardComp

    FieldGroup {
      property alias row1: row1
      property alias row2: row2
      width: 300
      title: "Card"

      FormRow {
        id: row1
        bodyHeight: Widget.height
      }
      FormRow {
        id: row2
        bodyHeight: Widget.height
      }
    }
  }

  // A card whose last row is a fold row
  Component {
    id: foldCardComp

    FieldGroup {
      property alias row1: row1
      property alias fold: fold
      width: 300
      title: "Card"

      FormRow {
        id: row1
        bodyHeight: Widget.height
      }
      FoldFormRow {
        id: fold
        title: "More"
        open: false
        onToggled: open = !open
      }
    }
  }

  // An inspector box: a FormColumn whose first child is a FormColumn of rows
  // (ConditionRows, as ElementInspector's Visible and BarTab's triggers are)
  // draws no divider on that top row, and the rows under it do
  Component {
    id: nestedFirstComp

    FormColumn {
      property alias head: top
      property alias lower: lower
      property alias plain: plain
      width: 300

      ConditionRows {
        id: top
        label: "Top"
        value: ({
            "test": "when"
          })
        keys: ["a"]
        tests: [
          {
            "value": "is",
            "label": "is"
          }
        ]
      }
      ConditionRows {
        id: lower
        label: "Second"
      }
      FieldRow {
        id: plain
        label: "Plain"
      }
    }
  }

  Component {
    id: nestedAfterComp

    FormColumn {
      property alias name: name
      property alias cond: cond
      width: 300

      FieldRow {
        id: name
        label: "Name"
      }
      ConditionRows {
        id: cond
        label: "Visible"
      }
    }
  }

  Component {
    id: plainHostComp

    ColumnLayout {
      property alias joined: joined
      property alias topRow: top
      width: 300

      FormColumn {
        id: joined
        joins: true
        Layout.fillWidth: true

        FormRow {
          id: top
          bodyHeight: Widget.height
        }
        FormRow {
          bodyHeight: Widget.height
        }
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function test_first_moves_to_the_next_row() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    wait(50);
    verify(col.row1.first, "the top row is first");
    verify(!col.row2.first);
    verify(!col.flip.first);
    col.row1.shown = false;
    wait(50);
    verify(!col.row1.first);
    verify(col.row2.first, "the next row is first once the top hides");
    col.row2.shown = false;
    wait(50);
    verify(col.flip.first, "a SwitchRow is a row too");
  }

  // A row after a form that draws rows keeps its divider; once the form hides
  // every row it is the top one
  function test_first_stops_at_a_shown_form() {
    const col = createTemporaryObject(afterFormComp, root);
    verify(col);
    wait(50);
    verify(!col.after.first, "the form's rows come first");
    const dividers = () => root.findAll(col.after, it => it.backTone !== undefined && it.visible);
    verify(dividers().length > 0, "its separator shows");
    col.form.allHidden = true;
    wait(50);
    verify(col.after.first, "the form drew nothing: this row is the top");
    compare(dividers().length, 0);
  }

  // The top row of a nested column draws no divider, its other rows do, and
  // a nested column under another row is not the top at all
  function test_nested_column_top_row_has_no_divider() {
    const col = createTemporaryObject(nestedFirstComp, root);
    verify(col);
    wait(50);
    const rows = it => root.findAll(it, r => r.bodyHeight !== undefined && r.first !== undefined && r.hitHeight !== undefined);
    const topRows = rows(col.head);
    verify(topRows.length >= 2, "the When condition builds its rows");
    verify(topRows[0].first, "the top row of the top column has no divider");
    for (let i = 1; i < topRows.length; i++)
      verify(!topRows[i].first, "the rows under it do");
    for (const r of rows(col.lower))
      verify(!r.first, "a lower column's rows all draw one");
    verify(!col.plain.first);

    const under = createTemporaryObject(nestedAfterComp, root);
    verify(under);
    wait(50);
    verify(under.name.first);
    for (const r of rows(under.cond))
      verify(!r.first, "a column under the top row draws its divider, ElementInspector's Visible");
  }

  function findAll(item, test) {
    const out = [];
    const walk = it => {
      if (test(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  // A joined column outside a FormColumn has no top to claim: its top row
  // keeps its divider
  function test_joined_column_in_a_plain_column_keeps_its_divider() {
    const host = createTemporaryObject(plainHostComp, root);
    verify(host);
    wait(50);
    compare(host.joined.firstRow, null);
    verify(!host.topRow.first, "the top row draws its divider");
  }

  function test_card_rows_get_first() {
    const card = createTemporaryObject(cardComp, root);
    verify(card);
    wait(50);
    verify(card.row1.first, "a FieldGroup's top row has no divider");
    verify(!card.row2.first);
  }

  function test_card_ends_shut_on_a_shut_fold_row() {
    const card = createTemporaryObject(foldCardComp, root);
    verify(card);
    wait(50);
    verify(card.row1.first, "the top row has no divider");
    verify(card.endsShut, "the shut fold row closes the card");
    card.fold.open = true;
    verify(!card.endsShut, "an open fold row no longer ends it");
  }

  function test_switchRow_click_off_the_switch_flips() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    wait(50);
    waitForRendering(col);
    const row = col.flip;
    verify(row.hoverable, "a row that activates something is hoverable");
    // The row's left edge, away from the switch at its right end
    const at = row.mapToItem(root, Style.space2, row.height / 2);
    mouseClick(root, at.x, at.y);
    compare(col.flips, 1, "a click off the switch flipped it");
  }

  function test_switchRow_unavailable_is_greyed_and_off_only() {
    const col = createTemporaryObject(columnComp, root);
    verify(col);
    col.flip.unavailableReason = "Not here";
    compare(col.flip.opacity, Style.opacityDisabled);
    verify(!col.flip.enabled, "off and unavailable: can't be switched");
    col.flip.checked = true;
    verify(col.flip.enabled, "on: can still be turned off");
  }
}
