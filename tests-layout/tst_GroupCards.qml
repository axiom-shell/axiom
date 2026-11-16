import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.views.base
import qs.components.views.CustomWidgets
import qs.components.views.Keybinds

// An editor's group is the settings page's card: an outlined surface box, its
// header at the top, rows inside padded Style.space3, indented only by their
// dependency level (RowTree), a fold row (FoldFormRow) for extra options.
TestCase {
  id: root

  name: "GroupCards"
  when: windowShown
  visible: true
  width: 700
  height: 800

  Harness {
    id: harness
  }

  // Two rows in a titled card on a surface pane
  Component {
    id: paneComp

    Surface {
      id: pane
      property alias group: group
      property alias row0: row0
      property alias row1: row1
      property bool foldable: true
      property string title: "Size"
      property bool hostVisible: true
      property alias stub: stub
      width: 400
      height: 600
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: pane.title
          foldable: pane.foldable && pane.title !== ""
          visible: pane.hostVisible

          // A form's stand-in for the card's hide rule (`allHidden`)
          Item {
            id: stub
            property bool allHidden: true
            visible: false
          }
          FormRow {
            id: row0
            first: true
            bodyHeight: Widget.height
          }
          FormRow {
            id: row1
            bodyHeight: Widget.height
          }
        }
      }
    }
  }

  function rows() {
    const out = [];
    for (const scale of [100, 150])
      for (const density of ["compact", "normal", "roomy"])
        for (const w of [340, 540])
          out.push({
            "tag": `${scale}% ${density} ${w}`,
            "scale": scale,
            "density": density,
            "w": w
          });
    return out;
  }

  function step() {
    return Widget.spacing * 2;
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

  function headerOf(card) {
    return findAll(card, it => it !== card && it.foldable !== undefined && it.collapsed !== undefined && it.status !== undefined)[0];
  }

  function chevronOf(card) {
    return findAll(card, it => it.rotation !== undefined && it.open !== undefined && it.hot !== undefined)[0];
  }

  function dividers(row) {
    return findAll(row, it => it.backTone !== undefined && it.visible);
  }

  function make(data, props) {
    harness.configure(data);
    const pane = createTemporaryObject(paneComp, root, Object.assign({
      "width": Widget.textPx(data.w)
    }, props ?? {}));
    verify(pane);
    waitForRendering(pane);
    wait(30);
    return pane;
  }

  function test_cardGeometry_data() {
    return rows();
  }

  function test_cardGeometry(data) {
    const pane = make(data);
    const group = pane.group;
    compare(group.tone, "surface");
    compare(group.border.width, Style.hairline);
    const header = root.headerOf(group);
    verify(header, "a header");
    const pad = Style.space3;
    compare(Math.round(pane.row0.mapToItem(group, 0, 0).x), pad);
    compare(Math.round(pane.row0.width), Math.round(group.width - 2 * pad));
    compare(Math.round(pane.row0.mapToItem(group, 0, 0).y), Math.round(header.mapToItem(group, 0, header.height).y + Style.space2));
    compare(Math.round(group.implicitHeight), Math.round(pad + header.height + Style.space2 + pane.row0.height + pane.row1.height + pad));
    compare(root.dividers(pane.row0), [], "the top row has no divider");
    compare(root.dividers(pane.row1).length, 1, "the next has one");
  }

  function test_fold_data() {
    return rows();
  }

  function test_fold(data) {
    const pane = make(data);
    const group = pane.group;
    const header = root.headerOf(group);
    verify(root.chevronOf(group).visible, "a chevron");
    group.toggled();
    verify(group.collapsed);
    tryVerify(() => Math.abs(group.height - (2 * Style.space3 + header.height)) < 1, 3000);
    group.toggled();
    verify(!group.collapsed);
    tryVerify(() => group.height > 2 * Style.space3 + header.height + 1, 3000);
  }

  function test_notFoldable_data() {
    return rows();
  }

  function test_notFoldable(data) {
    const pane = make(data, {
      "foldable": false
    });
    verify(!root.chevronOf(pane.group).visible, "no chevron");
    const header = root.headerOf(pane.group);
    mouseClick(header, 5, 5);
    wait(30);
    compare(pane.group.collapsed, false, "a click changes nothing");
  }

  function test_titleless_data() {
    return rows();
  }

  function test_titleless(data) {
    const pane = make(data, {
      "title": ""
    });
    const group = pane.group;
    compare(group.foldable, false);
    compare(group.headed, false);
    compare(Math.round(pane.row0.mapToItem(group, 0, 0).y), Style.space3, "the rows start at the padding");
    const header = root.headerOf(group);
    verify(header === undefined || !header.visible, "no header");
  }

  function test_hideRule_data() {
    return rows();
  }

  function test_hideRule(data) {
    const pane = make(data);
    // The form stub (all hidden) and the two rows are what counts
    compare(pane.group.visible, true, "a row shows");
    pane.row0.shown = false;
    pane.row1.shown = false;
    tryCompare(pane.group, "visible", false);
    pane.row1.shown = true;
    tryCompare(pane.group, "visible", true);
    pane.row1.shown = false;
    tryCompare(pane.group, "visible", false);
    pane.stub.allHidden = false;
    tryCompare(pane.group, "visible", true, 1000, "a form with a row shown");
    pane.stub.allHidden = true;
    tryCompare(pane.group, "visible", false);
    pane.hostVisible = false;
    pane.row0.shown = true;
    tryCompare(pane.group, "visible", false, 1000, "a host's own visible still wins");
  }

  // A hand-built row at depth `level`: a probe in its body
  Component {
    id: levelComp

    Item {
      property alias row: row
      property alias probe: probe
      width: 400
      height: 100

      FormRow {
        id: row
        width: parent.width
        bodyHeight: Widget.height

        Item {
          id: probe
          width: 10
          height: 10
        }
      }
    }
  }

  function make_level(level, beside) {
    const host = createTemporaryObject(levelComp, root);
    verify(host);
    host.row.level = level;
    host.row.beside = beside === true;
    wait(20);
    return host;
  }

  function rails(row) {
    return Array.from(row.children).filter(it => it.width === 2 && it.color !== undefined && Qt.colorEqual(it.color, Style.rail)).map(it => it.x).sort((a, b) => a - b);
  }

  function tint(row) {
    return root.findAll(row, it => it.objectName === "rowTint")[0];
  }

  function test_levelIndentsTheBody_data() {
    return rows();
  }

  function test_levelIndentsTheBody(data) {
    harness.configure(data);
    for (const level of [0, 1, 2, 3]) {
      const host = root.make_level(level);
      compare(host.probe.mapToItem(host.row, 0, 0).x, level * root.step(), "level " + level);
      compare(root.rails(host.row).length, level, "one rail per depth");
    }
    const half = root.make_level(1, true);
    compare(half.probe.mapToItem(half.row, 0, 0).x, 0, "the right half of a pair has no indent");
    compare(root.rails(half.row), []);
  }

  function test_tintStartsAtTheRowsRule_data() {
    return rows();
  }

  function test_tintStartsAtTheRowsRule(data) {
    harness.configure(data);
    const at = host => root.tint(host.row).mapToItem(host.row, 0, 0).x;
    compare(at(root.make_level(0)), -Style.rowBleed, "depth 0 bleeds past the edge");
    compare(at(root.make_level(1)), 0, "depth 1 starts at the row's edge");
    compare(at(root.make_level(2)), root.step(), "depth 2 at its own rule");
    const wide = root.make_level(2);
    compare(root.tint(wide.row).mapToItem(wide.row, 0, 0).x + root.tint(wide.row).width, wide.row.width + Style.rowBleed, "the right side bleeds still");
  }

  // The Menu Placement shape: Screen edge under Placement, Across under that
  Component {
    id: formComp

    Surface {
      property alias group: group
      width: Widget.textPx(540)
      height: 500
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Placement"

          SchemaPropertiesForm {
            Layout.fillWidth: true
            order: ["placement", "edge", "across"]
            propertiesSchema: ({
                "placement": {
                  "type": "string",
                  "title": "Placement",
                  "enum": ["edge", "free"],
                  "default": "edge"
                },
                "edge": {
                  "type": "string",
                  "title": "Screen edge",
                  "enum": ["left", "right"],
                  "default": "left",
                  "x-showIf": {
                    "placement": "edge"
                  }
                },
                "across": {
                  "type": "string",
                  "title": "Across",
                  "enum": ["start", "end"],
                  "default": "start",
                  "x-showIf": {
                    "edge": ["left", "right"]
                  }
                }
              })
          }
        }
      }
    }
  }

  function formRows(item) {
    return root.findAll(item, it => it.bodyHeight !== undefined && it.depth !== undefined);
  }

  function test_formLevels_data() {
    return rows();
  }

  function test_formLevels(data) {
    harness.configure(data);
    const pane = createTemporaryObject(formComp, root);
    verify(pane);
    wait(50);
    const found = root.formRows(pane);
    compare(found.length, 3);
    compare(found.map(r => r.depth), [0, 1, 2]);
    compare(found.map(r => r.indent), [0, root.step(), 2 * root.step()], "Screen edge one step in, Across two");
    compare(root.rails(found[2]), [0, root.step()], "two rails on Across");
  }

  // A card straight in a scroll view: every tint lies inside what clips it
  Component {
    id: scrollComp

    Surface {
      id: scrollPane
      readonly property alias scroll: scroll
      width: 320
      height: 300
      tone: "surface"

      StyledScrollView {
        id: scroll
        anchors.fill: parent

        ColumnLayout {
          width: scroll.availableWidth

          FieldGroup {
            Layout.fillWidth: true
            title: "Group"

            FormRow {
              first: true
              hoverable: true
              bodyHeight: Widget.height

              StyledTextEntry {
                width: parent.width
                text: "x"
              }
            }
            InspectorRow {
              label: "Key"
              besideLabel: true

              StyledTextEntry {
                Layout.fillWidth: true
                text: "y"
              }
            }
          }
        }
      }
    }
  }

  function layers(item) {
    return root.findAll(item, it => it.bleed !== undefined && it.bleed > 0 && it.hovered !== undefined);
  }

  function clipOf(item) {
    for (let p = item.parent; p; p = p.parent) {
      if (p.clip)
        return p;
    }
    return null;
  }

  function test_tintInsideTheClip_data() {
    return [
      {
        "tag": "100%",
        "scale": 100
      },
      {
        "tag": "150%",
        "scale": 150
      }
    ];
  }

  function test_tintInsideTheClip(data) {
    harness.configure({
      "scale": data.scale
    });
    const pane = createTemporaryObject(scrollComp, root);
    verify(pane);
    wait(50);
    waitForRendering(pane);
    const found = root.layers(pane.scroll);
    verify(found.length >= 2, "the rows' tints are built: " + found.length);
    for (const layer of found) {
      const clip = root.clipOf(layer);
      verify(clip, "something clips the tint");
      const left = layer.mapToItem(clip, 0, 0).x;
      verify(left >= 0, "room on the left: " + left);
      verify(left + layer.width <= clip.width, "room on the right: " + (left + layer.width) + " of " + clip.width);
    }
  }

  // A fold row's rows: shut hides the form behind it and the row after it
  Component {
    id: foldComp

    Surface {
      id: foldPane
      property bool open: false
      property alias group: group
      property alias fold: fold
      property alias after: after
      property alias form: form
      width: 400
      height: 500
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Script"
          bottomInset: foldPane.open ? Style.space3 : 0

          FoldFormRow {
            id: fold
            title: "Advanced"
            open: foldPane.open
            onToggled: foldPane.open = !foldPane.open
          }
          SchemaPropertiesForm {
            id: form
            Layout.fillWidth: true
            folded: !foldPane.open
            follows: true
            propertiesSchema: ({
                "a": {
                  "type": "boolean",
                  "title": "A",
                  "default": false
                }
              })
          }
          FormRow {
            id: after
            shown: foldPane.open
            tinted: false
            bodyHeight: Widget.height
          }
        }
      }
    }
  }

  function test_foldFormRow() {
    harness.configure({});
    const pane = createTemporaryObject(foldComp, root);
    verify(pane);
    wait(50);
    compare(pane.after.shown, false);
    compare(root.formRows(pane.form).map(r => r.shown), [false], "the form's rows hidden behind the shut fold");
    tryCompare(pane.after, "height", 0);
    tryVerify(() => Math.abs(pane.group.mapToItem(pane.group, 0, pane.group.height).y - pane.fold.mapToItem(pane.group, 0, pane.fold.height).y) < 1, 1000, "shut: the card ends at the fold row");
    pane.fold.toggled();
    compare(pane.open, true);
    compare(pane.after.shown, true);
    verify(root.formRows(pane.form).every(r => r.shown !== false), "the form's rows shown again");
    tryVerify(() => pane.after.height > 0, 1000);
  }

  // A schema control in a card at a narrow width keeps its line
  Component {
    id: comboCard

    Surface {
      property alias combo: combo
      property alias group: group
      width: Widget.textPx(340)
      height: 300
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Look"

          FormRow {
            first: true
            hoverable: true
            bodyHeight: combo.implicitHeight

            SchemaComboBox {
              id: combo
              width: parent.width
              label: "Color"
              options: ["", "primary"]
              currentValue: ""
            }
          }
        }
      }
    }
  }

  function test_narrowControlInACard_data() {
    return rows().filter(r => r.w === 340);
  }

  function test_narrowControlInACard(data) {
    harness.configure(data);
    const pane = createTemporaryObject(comboCard, root);
    verify(pane);
    waitForRendering(pane);
    wait(30);
    verify(pane.combo.fit.inline, "on the label's line");
    compare(harness.containedProblems(pane.group), []);
  }

  // A settings hand-built card: children spaced by Style.space2, no fold
  Component {
    id: handComp

    Surface {
      property alias group: group
      property alias a: first
      property alias b: second
      width: 400
      height: 400
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: "Account"
          bodySpacing: Style.space2
          foldable: false

          StyledText {
            id: first
            text: "One"
          }
          StyledText {
            id: second
            text: "Two"
          }
        }
      }
    }
  }

  function test_handBuiltCard_data() {
    return rows().filter(r => r.w === 340);
  }

  function test_handBuiltCard(data) {
    harness.configure(data);
    const pane = createTemporaryObject(handComp, root);
    verify(pane);
    waitForRendering(pane);
    wait(30);
    const header = root.headerOf(pane.group);
    compare(Math.round(pane.group.height), Math.round(2 * Style.space3 + header.height + Style.space2 + pane.a.height + Style.space2 + pane.b.height));
  }

  // The bind inspector's one title-less card of BindRows
  Component {
    id: bindsComp

    Surface {
      property alias group: group
      property alias key: keyRow
      property alias action: actionRow
      width: 400
      height: 400
      tone: "surface"

      ColumnLayout {
        width: parent.width

        FieldGroup {
          id: group
          title: ""

          BindRow {
            id: keyRow
            first: true
            label: "Key"
          }
          BindRow {
            id: actionRow
            label: "Action"
          }
        }
      }
    }
  }

  function test_titlelessBindRows_data() {
    return rows().filter(r => r.w === 340);
  }

  function test_titlelessBindRows(data) {
    harness.configure(data);
    const pane = createTemporaryObject(bindsComp, root);
    verify(pane);
    waitForRendering(pane);
    wait(30);
    compare(pane.group.headed, false);
    compare(pane.group.foldable, false);
    compare(Math.round(pane.key.mapToItem(pane.group, 0, 0).y), Style.space3, "row 0 starts at the padding");
    verify(pane.action.y >= pane.key.height, "row 1 under row 0");
  }
}
