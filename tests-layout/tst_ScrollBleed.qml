import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.forms
import qs.components.views.BarEditor
import qs.components.content.base

// A scroll view holding FormRows with `bleed: Style.rowBleed` and matching
// negative margins: the rows keep the full width and their tint stays in the view.
TestCase {
  id: root

  name: "ScrollBleed"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: pageComp

    ColumnLayout {
      id: page

      property bool bar: false
      property alias scroll: scroll
      property alias row: row

      width: 400
      height: 300
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
      }

      StyledScrollView {
        id: scroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: -Style.rowBleed
        Layout.rightMargin: -Style.rowBleed
        bleed: Style.rowBleed
        contentPadding: 0
        showScrollBar: page.bar

        ColumnLayout {
          width: scroll.availableWidth

          FormRow {
            id: row

            Layout.fillWidth: true
            bodyHeight: 30
            hoverable: true
          }
        }
      }
    }
  }

  function findAll(item, pred) {
    const out = [];
    const walk = it => {
      if (pred(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  // The nearest ancestor that clips what is drawn outside it (a ScrollView's
  // own Flickable clips at its padding, so the padding is no room)
  function clipOf(item) {
    for (let p = item.parent; p; p = p.parent) {
      if (p.clip)
        return p;
    }
    return null;
  }

  // The tint overhangs its row by the bleed and lies inside the clip around it
  function tintInside(row, tint) {
    const clip = clipOf(tint);
    verify(clip, "something clips the tint");
    const left = tint.mapToItem(clip, 0, 0).x;
    verify(left >= -0.5 && left + tint.width <= clip.width + 0.5, `the tint lies in its clip: ${left} + ${tint.width} of ${clip.width}`);
    const over = tint.mapToItem(row, 0, 0).x;
    verify(over <= -Style.rowBleed + 0.5, `the tint overhangs the row: ${over}`);
  }

  function check(bar) {
    harness.configure({});
    const page = createTemporaryObject(pageComp, root, {
      "bar": bar
    });
    waitForRendering(page);
    tryVerify(() => page.row.width > 0);
    const at = page.row.mapToItem(page, 0, 0);
    compare(Math.round(at.x), 0);
    if (bar)
      verify(page.row.width < 400, `the scroll bar takes room (${page.row.width})`);
    else
      compare(Math.round(page.row.width), 400);
    tryVerify(() => findAll(page.row, it => it.objectName === "rowTint").length > 0);
    const tint = findAll(page.row, it => it.objectName === "rowTint")[0];
    tintInside(page.row, tint);
  }

  function test_bleed_without_scroll_bar() {
    check(false);
  }

  function test_bleed_with_scroll_bar() {
    check(true);
  }

  // The bar widget inspector's sizing override row, in the inspector's scroll
  // view (bleed, matching margins, a scroll bar): its hover tint stays inside
  // the view, which is the clipping the settings panel had
  Component {
    id: overrideComp

    ColumnLayout {
      id: page

      property alias scroll: scroll
      property alias row: row

      width: 400
      height: 300
      spacing: 0

      StyledScrollView {
        id: scroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: -Style.rowBleed
        Layout.rightMargin: -Style.rowBleed
        bleed: Style.rowBleed
        contentPadding: 0
        showScrollBar: true

        ColumnLayout {
          width: scroll.availableWidth

          LayoutOverrideField {
            id: row

            Layout.fillWidth: true
            key: "maxSize"
            first: true
            fieldSchema: ({
                "title": "Largest size",
                "description": "How large it grows"
              })
          }
        }
      }
    }
  }

  // The pinned list of a tool pane: padded and outset by the ring's width
  Component {
    id: pinnedComp

    Item {
      id: page

      property alias scroll: scroll
      property alias entry: entry

      width: 300
      height: 200

      StyledScrollView {
        id: scroll

        anchors.fill: parent
        anchors.margins: -Style.focusWidth
        contentPadding: 0
        bleed: Style.focusWidth
        topPadding: Style.focusWidth
        bottomPadding: Style.focusWidth

        ColumnLayout {
          width: scroll.availableWidth

          ListEntryRow {
            id: entry

            Layout.fillWidth: true
            label: "First"
            icon: "star"
          }
        }
      }
    }
  }

  function test_override_row_tint_inside_inspector_scroll() {
    harness.configure({});
    for (const value of [undefined, 40]) {
      const page = createTemporaryObject(overrideComp, root);
      waitForRendering(page);
      page.row.value = value;
      tryVerify(() => page.row.width > 0);
      verify(page.row.implicitHeight >= Style.rowHeight, `a row's height (${page.row.implicitHeight})`);
      const at = page.row.mapToItem(page, 0, 0);
      compare(Math.round(at.x), 0);
      tryVerify(() => findAll(page.row, it => it.objectName === "rowTint").length > 0);
      const tint = findAll(page.row, it => it.objectName === "rowTint")[0];
      tintInside(page.row, tint);
    }
  }

  function test_pinned_list_ring_inside_scroll() {
    harness.configure({});
    const page = createTemporaryObject(pinnedComp, root);
    waitForRendering(page);
    const ring = findAll(page.entry, it => it.shown !== undefined && it._host !== undefined)[0];
    verify(ring !== undefined, "the row's FocusRing");
    ring.shown = true;
    const clip = clipOf(ring);
    verify(clip, "something clips the ring");
    const tl = ring.mapToItem(clip, 0, 0);
    verify(tl.x >= -0.5 && tl.y >= -0.5, `the ring starts inside: ${tl.x},${tl.y}`);
    verify(tl.x + ring.width <= clip.width + 0.5, "the ring ends inside across");
  }

  // A titled card's scrolling body (the bars panel, window rules, keybinds):
  // a FormRow in it keeps its place under the card's padding, and its tint
  // lies inside the scroll view's clip
  Component {
    id: cardComp

    TitledCard {
      id: card

      property alias row: row

      width: 400
      height: 300

      FormRow {
        id: row

        Layout.fillWidth: true
        first: true
        bodyHeight: 30
        hoverable: true
      }
    }
  }

  function test_titled_card_body_keeps_row_tint() {
    harness.configure({});
    const card = createTemporaryObject(cardComp, root);
    waitForRendering(card);
    tryVerify(() => card.row.width > 0);
    const scroll = findAll(card, it => it.bleed !== undefined && it.contentPadding !== undefined)[0];
    verify(scroll !== undefined, "the body's scroll view");
    compare(scroll.bleed, Style.rowBleed);
    const at = card.row.mapToItem(card, 0, 0);
    compare(Math.round(at.x), Widget.padding);
    tryVerify(() => findAll(card.row, it => it.objectName === "rowTint").length > 0);
    const tint = findAll(card.row, it => it.objectName === "rowTint")[0];
    tintInside(card.row, tint);
  }
}
