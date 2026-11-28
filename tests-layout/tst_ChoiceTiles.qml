import QtQuick
import QtTest
import qs.config
import qs.components.reusable
import qs.components.methods

// ChoiceTiles at scale, font and width (the layout harness): an even grid of
// equal tiles read from ChoiceGrid, none past the right edge, never one per
// line while two labels fit, labels whole, previews never under their floor.
TestCase {
  id: root

  name: "ChoiceTiles"
  when: windowShown
  visible: true
  width: 1000
  height: 700

  Harness {
    id: harness
  }

  readonly property var labels: ["Filled", "Tinted", "Outline", "Split", "Underline", "Colored icons", "Plain text"]

  Component {
    id: tilesComp

    ChoiceTiles {
      property var previewed: false

      value: "o0"
      preview: previewed ? previewComp : null
    }
  }

  Component {
    id: previewComp

    Rectangle {
      required property var value
    }
  }

  function options(count) {
    return labels.slice(0, count).map((label, i) => ({
          "value": "o" + i,
          "label": label
        }));
  }

  function make(row, count, previews) {
    harness.configure(row);
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": options(count),
      "previewed": previews === true
    });
    waitForRendering(tiles);
    return tiles;
  }

  // The tile delegates of `tiles` grouped by row
  function rowsOf(tiles) {
    const byY = {};
    for (const child of tiles.children) {
      if (child.width !== tiles.tileWidth || child.height < 1)
        continue;
      (byY[child.y] = byY[child.y] ?? []).push(child);
    }
    return Object.keys(byY).map(Number).sort((a, b) => a - b).map(y => byY[y]);
  }

  function matrix() {
    const out = [];
    for (const scale of [100, 150])
      for (const fontSize of [8, 32])
        for (const count of [3, 7])
          for (const at of ["edge", "panel", "wide"])
            out.push({
              "tag": `${scale}% ${fontSize}pt ${count} options ${at}`,
              "scale": scale,
              "fontSize": fontSize,
              "count": count,
              "at": at
            });
    return out;
  }

  function widthAt(tiles, at) {
    return at === "edge" ? tiles._leastTile * 2 + tiles.spacing : at === "panel" ? Widget.textPx(260) : Widget.textPx(900);
  }

  function test_grid_is_even_and_inside_data() {
    return matrix();
  }

  function test_grid_is_even_and_inside(data) {
    const tiles = make(data, data.count);
    tiles.width = widthAt(tiles, data.at);
    wait(50);
    compare(tiles.columns, ChoiceGrid.columns(data.count, tiles.width, tiles.minTileWidth, tiles._leastTile, tiles.spacing));
    const grid = rowsOf(tiles);
    compare(grid.length, Math.ceil(data.count / tiles.columns), "rows");
    for (let i = 0; i < grid.length - 1; i++)
      compare(grid[i].length, tiles.columns, "a full row");
    let count = 0;
    for (const row of grid)
      for (const tile of row) {
        count++;
        compare(tile.width, tiles.tileWidth, "equal tiles");
        verify(tile.x + tile.width <= tiles.width + 0.5, "inside the right edge");
      }
    compare(count, data.count);
    const tileHeight = grid[0][0].height;
    fuzzyCompare(tiles.implicitHeight, grid.length * tileHeight + (grid.length - 1) * tiles.spacing, 1);
  }

  function test_never_one_per_line_while_two_fit_data() {
    const out = [];
    for (const scale of [75, 100, 150])
      for (const fontSize of [8, 14, 32])
        out.push({
          "tag": `${scale}% ${fontSize}pt`,
          "scale": scale,
          "fontSize": fontSize
        });
    return out;
  }

  function test_never_one_per_line_while_two_fit(data) {
    const tiles = make(data, 7);
    tiles.width = tiles._leastTile * 2 + tiles.spacing;
    wait(50);
    compare(tiles.columns, 2, "two columns at the floor, not one");
    compare(rowsOf(tiles).length, 4);
    tiles.width -= 1;
    compare(tiles.columns, 1, "one only below two labels");
  }

  function test_labels_are_not_cut_data() {
    return matrix().filter(row => row.at === "edge");
  }

  function test_labels_are_not_cut(data) {
    const tiles = make(data, data.count);
    tiles.width = widthAt(tiles, data.at);
    wait(50);
    verify(tiles.columns >= 2);
    for (const t of harness.texts(tiles))
      verify(!t.truncated, `"${t.text}" is elided`);
    compare(harness.containedProblems(tiles), []);
  }

  function test_previews_keep_their_floor_data() {
    return matrix().filter(row => row.at === "edge" && row.count === 3);
  }

  function test_previews_keep_their_floor(data) {
    const tiles = make(data, 3, true);
    verify(tiles._leastTile >= tiles.previewMinWidth + Widget.smallPadding * 2, "the floor holds the preview");
    tiles.width = tiles._leastTile * 2 + tiles.spacing;
    wait(50);
    compare(tiles.columns, 2);
    for (const row of rowsOf(tiles))
      for (const tile of row)
        verify(tile.width - Widget.smallPadding >= tiles.previewMinWidth, "preview room");
    tiles.width = Widget.textPx(900);
    wait(50);
    const tile = rowsOf(tiles)[0][0];
    compare(tile.height, tiles.previewHeight + Widget.smallPadding + Widget.height);
  }

  function cards() {
    return [
      {
        "value": "a",
        "label": "Short",
        "icon": "bolt",
        "description": "One line."
      },
      {
        "value": "b",
        "label": "Long",
        "icon": "tune",
        "tag": "Recommended",
        "description": "A much longer description that wraps over several lines in a half-width card, so this card is taller."
      }
    ];
  }

  function test_icon_variant_is_a_card() {
    harness.configure({});
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": cards()
    });
    waitForRendering(tiles);
    const tile = tiles.children.find(child => child.width === tiles.tileWidth);
    verify(tile.card, "icon, description or tag make a card");
    verify(tile.height >= Widget.padding * 2, "has its content's height");
    compare(harness.containedProblems(tiles, true), []);
  }

  function test_rows_layout_is_two_up_and_equal_height_data() {
    return [
      {
        "tag": "100%",
        "scale": 100
      },
      {
        "tag": "150%",
        "scale": 150,
        "fontSize": 20
      }
    ];
  }

  function test_rows_layout_is_two_up_and_equal_height(data) {
    harness.configure(data);
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(480),
      "options": cards(),
      "layout": "rows"
    });
    waitForRendering(tiles);
    wait(50);
    compare(tiles.columns, 2);
    const row = rowsOf(tiles);
    compare(row.length, 1, "one line");
    compare(row[0].length, 2);
    compare(row[0][0].width, row[0][1].width, "equal halves");
    compare(row[0][0].height, row[0][1].height, "equal heights");
    verify(row[0][0].height >= row[0][1].implicitHeight, "as tall as the taller");
    compare(harness.containedProblems(tiles, true), []);
  }

  function test_disabled_tile_is_not_picked() {
    harness.configure({});
    const options = cards();
    options[1].disabledReason = "Not here";
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": options
    });
    waitForRendering(tiles);
    const picks = [];
    tiles.picked.connect(value => picks.push(value));
    const tile = rowsOf(tiles)[0][1];
    compare(tile.disabledReason, "Not here");
    verify(tile.disabled);
    mouseClick(tile);
    compare(picks, [], "a click on a disabled tile picks nothing");
    mouseClick(rowsOf(tiles)[0][0]);
    compare(picks, ["a"]);
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

  function tilesOf(tiles) {
    return rowsOf(tiles).reduce((all, row) => all.concat(row), []);
  }

  function pressableOf(tile) {
    return findAll(tile, it => it.tinted !== undefined && it.tabStop !== undefined && it.acceptedButtons !== undefined)[0];
  }

  // A card says why it can't be picked under its description, not greyed
  function test_card_shows_disabled_reason() {
    harness.configure({});
    const options = cards();
    options[0].disabledReason = "Not here";
    const preview = [
      {
        "value": "p",
        "label": "Prev",
        "disabledReason": "Nope"
      },
      {
        "value": "q",
        "label": "Quiet"
      }
    ];
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": options
    });
    waitForRendering(tiles);
    const [off, on] = tilesOf(tiles);
    const row = findAll(off, it => it.objectName === "disabledReason")[0];
    verify(row, "the reason row");
    verify(row.visible);
    compare(findAll(row, it => it.text === "Not here").length, 1);
    compare(row.opacity, 1);
    compare(findAll(on, it => it.objectName === "disabledReason")[0].visible, false);
    const previews = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": preview
    });
    waitForRendering(previews);
    for (const tile of tilesOf(previews))
      for (const r of findAll(tile, it => it.objectName === "disabledReason"))
        verify(!r.visible, "a preview tile has no reason row");
  }

  // Only an unselected tile tints under the pointer
  function test_selected_tile_does_not_tint() {
    harness.configure({});
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": cards(),
      "value": "a"
    });
    waitForRendering(tiles);
    const [first, second] = tilesOf(tiles);
    compare(pressableOf(first).tinted, false);
    compare(pressableOf(second).tinted, true);
  }

  Component {
    id: menuHostComp

    Item {
      id: host
      property alias area: area
      property alias tiles: tiles
      property var rights: []
      width: 900
      height: 400

      MouseArea {
        id: area
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: host.rights.push("right")
      }

      ChoiceTiles {
        id: tiles
        width: parent.width
        value: "a"
        options: root.cards()
      }
    }
  }

  // A right click is left to what is under the tiles, until a tile asks
  function test_right_click_reaches_parent() {
    harness.configure({});
    const host = createTemporaryObject(menuHostComp, root);
    waitForRendering(host);
    const tile = tilesOf(host.tiles)[1];
    mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton);
    compare(host.rights, ["right"]);
  }

  Component {
    id: bareTileComp

    PreviewTile {
      property var menus_: []
      width: 200
      height: 80
      title: "T"
      icon: "bolt"
      onMenuRequested: (x, y) => menus_.push([x, y])
    }
  }

  function test_menus_emits_menu_requested() {
    harness.configure({});
    const tile = createTemporaryObject(bareTileComp, root, {
      "menus": true
    });
    waitForRendering(tile);
    mouseClick(tile, 10, 10, Qt.RightButton);
    compare(tile.menus_.length, 1);
    const off = createTemporaryObject(bareTileComp, root);
    mouseClick(off, 10, 10, Qt.RightButton);
    compare(off.menus_.length, 0, "off by default");
  }

  function test_list_layout() {
    harness.configure({});
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": cards().concat([
        {
          "value": "c",
          "label": "Third",
          "icon": "star"
        }
      ]),
      "layout": "list"
    });
    waitForRendering(tiles);
    wait(50);
    compare(tiles.columns, 1);
    const all = tilesOf(tiles);
    compare(all.length, 3);
    let y = -1;
    for (const tile of all) {
      compare(tile.x, 0);
      compare(tile.width, tiles.width);
      verify(tile.y > y, "y increases");
      y = tile.y;
      compare(tile.height, tile.implicitHeight, "its own height");
    }
    verify(all[0].height !== all[1].height, "heights differ");
  }

  function test_keys() {
    harness.configure({});
    const before = createTemporaryObject(entryComp, root, {
      "y": 600
    });
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": cards().concat([
        {
          "value": "c",
          "label": "Third",
          "icon": "star"
        }
      ]),
      "layout": "list"
    });
    const picks = [];
    tiles.picked.connect(value => picks.push(value));
    waitForRendering(tiles);
    before.forceActiveFocus();
    verify(before.activeFocus);
    keyClick(Qt.Key_Tab);
    verify(tiles.activeFocus, "Tab enters the tiles");
    const ringed = () => tilesOf(tiles).findIndex(t => t.ringed);
    compare(ringed(), 0);
    keyClick(Qt.Key_Down);
    compare(ringed(), 1);
    keyClick(Qt.Key_Right);
    compare(ringed(), 2);
    keyClick(Qt.Key_Up);
    compare(ringed(), 1);
    keyClick(Qt.Key_Return);
    compare(picks, ["b"]);
    keyClick(Qt.Key_Left);
    keyClick(Qt.Key_Space);
    compare(picks, ["b", "a"]);
    keyClick(Qt.Key_Tab);
    verify(!tiles.activeFocus, "Tab again leaves: one stop");
  }

  Component {
    id: entryComp

    FocusScope {
      width: 10
      height: 10
      activeFocusOnTab: true
    }
  }

  function test_keys_skip_disabled() {
    harness.configure({});
    const options = cards();
    options[1].disabledReason = "Not here";
    const tiles = createTemporaryObject(tilesComp, root, {
      "width": Widget.textPx(900),
      "options": options,
      "value": "a"
    });
    const picks = [];
    tiles.picked.connect(value => picks.push(value));
    waitForRendering(tiles);
    tiles.forceActiveFocus();
    keyClick(Qt.Key_Right);
    keyClick(Qt.Key_Return);
    compare(picks, [], "a disabled option is not picked");
  }
}
