import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FlowColumns"

  function field(extra) {
    return Object.assign({
      "kind": "field",
      "path": ["A", "k"],
      "schema": {}
    }, extra ?? {});
  }

  function field_in(name, extra) {
    return field(Object.assign({
      "path": ["A", name]
    }, extra ?? {}));
  }

  function spans(blocks) {
    return blocks.map(block => [block.from, block.to]);
  }

  function test_count() {
    // A card's rows: target 560, min 400, at most 2, gap 20
    compare(FlowColumns.count(0, 560, 400, 2, 20), 1);
    compare(FlowColumns.count(839, 560, 400, 2, 20), 1);
    compare(FlowColumns.count(840, 560, 400, 2, 20), 2);
    compare(FlowColumns.count(3000, 560, 400, 2, 20), 2);
    compare(FlowColumns.count(900, 560, 500, 2, 20), 1, "the minimum binds");
    // The page's cards: at most 4, gap 8, never under 2
    compare(FlowColumns.count(0, 560, 400, 4, 8, 2), 2);
    compare(FlowColumns.count(680, 560, 400, 4, 8, 2), 2);
    compare(FlowColumns.count(860, 560, 400, 4, 8, 2), 2);
    compare(FlowColumns.count(1220, 560, 400, 4, 8, 2), 2);
    compare(FlowColumns.count(1399, 560, 400, 4, 8, 2), 2);
    compare(FlowColumns.count(1400, 560, 400, 4, 8, 2), 3);
    compare(FlowColumns.count(1940, 560, 400, 4, 8, 2), 3);
    compare(FlowColumns.count(1959, 560, 400, 4, 8, 2), 3);
    compare(FlowColumns.count(1960, 560, 400, 4, 8, 2), 4);
    compare(FlowColumns.count(3900, 560, 400, 4, 8, 2), 4);
  }

  // A tool page's inspector groups (GroupColumns): the pane's body width at
  // 100 % on the overlay's three screens, 1920x1080, 2560x1440, 3840x2160.
  // unit = (short side - 2 x 80 - 20) / 2 (450, 630, 990: the Settings
  // table's W = 2 x unit - 40 agrees); BaseView.editorWidth = 2.8 x unit
  // (the room beside the side panel is wider on every one of them); the
  // pane's body is that less its padding either side (Widget.padding 10).
  // Columns are gap 8 (Style.cardGap) apart, 400..700 px (1.25 x target).
  function test_group_columns_at_the_editor_widths() {
    for (const row of [
      {
        "short": 1080,
        "n": 2
      },
      {
        "short": 1440,
        "n": 3
      },
      {
        "short": 2160,
        "n": 4
      }
    ]) {
      const unit = (row.short - 2 * 80 - 20) / 2;
      const body = Math.round(unit * 2.8) - 2 * 10;
      const n = FlowColumns.count(body, 560, 400, 4, 8);
      compare(n, row.n, `${row.short}: ${body} px`);
      const column = (body - (n - 1) * 8) / n;
      verify(n >= 2);
      verify(column >= 400 && column <= Math.round(1.25 * 560), `${row.short}: ${column} px columns`);
    }
  }

  function test_count_raised_scale() {
    // The real widths at a raised Content size (min = px(400) there)
    compare(FlowColumns.count(848, 560, 500, 4, 10, 2), 2);
    compare(FlowColumns.count(840, 560, 600, 4, 12, 2), 2);
    compare(FlowColumns.count(1208, 560, 500, 4, 10, 2), 2);
    compare(FlowColumns.count(1200, 560, 600, 4, 12, 2), 2);
    compare(FlowColumns.count(1920, 560, 600, 4, 12, 2), 3);
    compare(FlowColumns.count(1896, 560, 600, 4, 12, 2), 3);
  }

  function test_count_larger_fonts() {
    // columnMin grows with the text (StyleTokens.textPx(400, 1, font))
    const at14 = StyleTokens.textPx(400, 1, 14);
    const at18 = StyleTokens.textPx(400, 1, 18);
    const at24 = StyleTokens.textPx(400, 1, 24);
    compare(at14, 400);
    compare(FlowColumns.count(840, 560, at14, 2, 20), 2);
    compare(FlowColumns.count(840, 560, at18, 2, 20), 1, "a row column holds 18 px text, not 14");
    compare(FlowColumns.count(1100, 560, at24, 2, 20), 1);
    compare(FlowColumns.count(1940, 560, at18, 4, 8, 2), 3);
    compare(FlowColumns.count(1940, 560, at24, 4, 8, 2), 2, "never under today's two");
  }

  function test_blocks_plain() {
    const blocks = FlowColumns.blocks([field_in("a"), field_in("b"), field_in("c"), field_in("d")]);
    compare(spans(blocks), [[0, 1], [1, 2], [2, 3], [3, 4]]);
    compare(blocks.map(block => block.wide || block.start), [false, false, false, false]);
    compare(FlowColumns.blocks([]), []);
  }

  function test_blocks_beside() {
    const rows = [field_in("a"), field_in("b", {
        "schema": {
          "x-beside": true
        }
      }), field_in("c")];
    compare(spans(FlowColumns.blocks(rows)), [[0, 2], [2, 3]]);
  }

  function test_blocks_dependent() {
    const dep = {
      "x-showIf": {
        "a": true
      }
    };
    const rows = [field_in("a"), field_in("b", {
        "schema": dep
      }), field_in("c", {
        "schema": dep
      }), field_in("d")];
    compare(spans(FlowColumns.blocks(rows)), [[0, 3], [3, 4]]);
    const global = [field_in("a"), field_in("b", {
        "schema": {
          "x-showIf": {
            "/Compositor.mode": "managed"
          }
        }
      })];
    compare(spans(FlowColumns.blocks(global)), [[0, 1], [1, 2]], "a condition on another section starts its own unit");
  }

  // A condition on a key among no card row starts its own unit; a row two
  // deep (under a row that is under row 0) still joins the unit
  function test_blocks_dependent_tree() {
    const stray = [field_in("a"), field_in("b", {
        "schema": {
          "x-showIf": {
            "other": true
          }
        }
      })];
    compare(spans(FlowColumns.blocks(stray)), [[0, 1], [1, 2]]);
    const deep = [field_in("a"), field_in("b", {
        "schema": {
          "x-showIf": {
            "a": true
          }
        }
      }), field_in("c", {
        "schema": {
          "x-showIf": {
            "b": true
          }
        }
      }), field_in("d")];
    compare(spans(FlowColumns.blocks(deep)), [[0, 3], [3, 4]]);
  }

  // The intro-fold shape of SchemaLayout.withIntro
  function introFold() {
    const fold = "A:settings";
    return [field_in("setup"),
      {
        "kind": "group",
        "title": "Settings",
        "path": [fold],
        "fold": true
      },
      field_in("r1", {
        "foldedBy": fold
      }), field_in("r2", {
        "foldedBy": fold
      }), field_in("r3", {
        "foldedBy": fold
      })];
  }

  function test_blocks_fold() {
    const blocks = FlowColumns.blocks(introFold());
    compare(spans(blocks), [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]]);
    compare(blocks.map(block => block.wide), [false, true, false, false, false]);
    compare(blocks.map(block => block.start), [false, false, false, false, false], "the heading cut the run");
    const after = FlowColumns.blocks(introFold().concat([field_in("plain")]));
    compare(after[5].start, true, "a plain row after the fold's rows starts a run");
  }

  function test_blocks_nested_fold() {
    const outer = "A:settings";
    const inner = "A.deep";
    const rows = [field_in("setup"),
      {
        "kind": "group",
        "title": "Settings",
        "path": [outer],
        "fold": true
      },
      field_in("r1", {
        "foldedBy": outer
      }),
      {
        "kind": "group",
        "title": "Deep",
        "path": ["A", "deep"],
        "fold": true
      },
      field_in("d1", {
        "foldedBy": inner,
        "foldedIn": outer
      }), field_in("d2", {
        "foldedBy": inner,
        "foldedIn": outer
      }), field_in("r2", {
        "foldedBy": outer
      })];
    const blocks = FlowColumns.blocks(rows);
    compare(blocks.map(block => block.wide), [false, true, false, true, false, false, false]);
    compare(blocks.map(block => block.start), [false, false, false, false, false, false, true], "back out of the inner fold starts a run");
  }

  function test_blocks_group() {
    const rows = [field_in("a"),
      {
        "kind": "group",
        "title": "Nested",
        "path": ["A", "nested"]
      },
      {
        "kind": "field",
        "path": ["A", "nested", "x"],
        "schema": {}
      },
      {
        "kind": "field",
        "path": ["A", "nested", "y"],
        "schema": {}
      },
      field_in("z")];
    const blocks = FlowColumns.blocks(rows);
    compare(blocks.map(block => block.wide), [false, true, false, false, false]);
    compare(blocks.map(block => block.start), [false, false, false, false, true]);
  }

  function test_blocks_drawn() {
    const rows = [
      {
        "kind": "object",
        "path": ["A", "o"],
        "schema": {
          "x-row": "Thing"
        }
      },
      {
        "kind": "field",
        "path": ["A", "o", "x"],
        "schema": {},
        "drawnBy": "A.o"
      },
      {
        "kind": "field",
        "path": ["A", "o", "y"],
        "schema": {},
        "drawnBy": "A.o"
      }
    ];
    compare(spans(FlowColumns.blocks(rows)), [[0, 3]]);
  }

  function test_lines() {
    const rows = [field_in("a"), field_in("b", {
        "schema": {
          "x-beside": true
        }
      }), field_in("c")];
    const lines = FlowColumns.lines(rows);
    compare(lines.map(entry => entry.side), [0, 1, -1]);
    compare(lines.map(entry => entry.line), [0, 0, 1]);
  }

  function test_block_heights() {
    const rows = [field_in("a"), field_in("b", {
        "schema": {
          "x-beside": true
        }
      }), field_in("c")];
    const blocks = FlowColumns.blocks(rows);
    compare(FlowColumns.blockHeights(blocks, FlowColumns.lines(rows), [42, 60, 42]), [60, 42]);
  }

  // Four plain rows placed by ColumnSplit in two columns of 490, 20 apart
  function placeRows(rows, heights, n, width) {
    const blocks = FlowColumns.blocks(rows);
    const lines = FlowColumns.lines(rows);
    const unitHeights = FlowColumns.blockHeights(blocks, lines, heights);
    const wide = blocks.map(block => block.wide);
    const starts = blocks.map(block => block.start);
    const splits = ColumnSplit.splitsN(unitHeights, wide, n, 0, starts);
    const placed = ColumnSplit.placeN(unitHeights, wide, splits, n, 0, starts, false);
    return FlowColumns.place(blocks, lines, heights, placed, width, 20, 12);
  }

  function test_place_two_columns() {
    const rows = [field_in("a"), field_in("b"), field_in("c"), field_in("d")];
    const placed = placeRows(rows, [42, 42, 42, 42], 2, 1000);
    compare(placed.rows.map(row => row.x), [0, 0, 510, 510]);
    compare(placed.rows.map(row => row.y), [0, 42, 0, 42]);
    compare(placed.rows.map(row => row.width), [490, 490, 490, 490]);
    compare(placed.height, 84);
  }

  function test_place_heading() {
    const rows = [
      {
        "kind": "group",
        "title": "H",
        "path": ["A:f"],
        "fold": true
      },
      field_in("a", {
        "foldedBy": "A:f"
      }), field_in("b", {
        "foldedBy": "A:f"
      })];
    const placed = placeRows(rows, [42, 42, 42], 2, 1000);
    compare(placed.rows[0].x, 0);
    compare(placed.rows[0].width, 1000);
    compare(placed.rows[0].column, -1);
    compare(placed.rows.slice(1).map(row => [row.x, row.y, row.column]), [[0, 42, 0], [510, 42, 1]]);
  }

  function test_place_lone_unit_keeps_width() {
    const placed = placeRows([field_in("a")], [42], 2, 1000);
    compare(placed.rows[0].x, 0);
    compare(placed.rows[0].width, 490);
  }

  function test_place_beside() {
    const beside = {
      "schema": {
        "x-beside": true
      }
    };
    const rows = [field_in("a"), field_in("b"), field_in("c", beside)];
    const placed = placeRows(rows, [42, 42, 42], 2, 1000);
    compare(placed.rows[1].column, 1);
    compare(placed.rows[1].width, 239);
    compare(placed.rows[2].x, 510 + 239 + 12);
    compare(placed.rows[1].x, 510);
    compare(placed.rows[2].width, 239);
    compare(placed.rows[2].y, placed.rows[1].y, "one line");
  }

  function test_blocks_wide_field() {
    const rows = [field_in("a"), field_in("b", {
        "schema": {
          "x-wide": true
        }
      }), field_in("c")];
    const blocks = FlowColumns.blocks(rows);
    compare(spans(blocks), [[0, 1], [1, 2], [2, 3]]);
    compare(blocks.map(block => block.wide), [false, true, false]);
    compare(blocks.map(block => block.start), [false, false, false]);
  }

  function test_blocks_wide_wins() {
    const rows = [field_in("a"), field_in("b", {
        "schema": {
          "x-showIf": {
            "a": true
          },
          "x-wide": true
        }
      }), field_in("c", {
        "schema": {
          "x-beside": true
        }
      })];
    const blocks = FlowColumns.blocks(rows);
    compare(spans(blocks), [[0, 1], [1, 2], [2, 3]]);
    compare(blocks.map(block => block.wide), [false, true, false]);
    compare(FlowColumns.lines(rows).map(line => line.side), [-1, -1, -1]);
  }

  function test_place_wide_field() {
    const placed = placeRows([field_in("a", {
        "schema": {
          "x-wide": true
        }
      })], [300], 2, 1000);
    compare(placed.rows[0].x, 0);
    compare(placed.rows[0].width, 1000);
    compare(placed.rows[0].column, -1);
    compare(placed.height, 300);
  }

  function test_place_wide_between() {
    const rows = [field_in("a"), field_in("b"), field_in("w", {
        "schema": {
          "x-wide": true
        }
      }), field_in("d")];
    const placed = placeRows(rows, [42, 42, 200, 42], 2, 1000);
    compare(placed.rows.map(row => [row.x, row.y, row.width, row.column]), [[0, 0, 490, 0], [510, 0, 490, 1], [0, 42, 1000, -1], [0, 242, 490, 0]]);
    compare(placed.height, 284);
  }
}
