import QtQuick
import QtTest
import qs.components.methods

// A module's style by its room (ModuleStyles)
TestCase {
  name: "ModuleStyles"

  readonly property var candidates: [
    {
      "style": "focus",
      "minWidth": 300,
      "minHeight": 300
    },
    {
      "style": "tiles",
      "minWidth": 200,
      "minHeight": 100
    },
    {
      "style": "list",
      "minWidth": 0,
      "minHeight": 0
    }
  ]

  function test_explicit_style_kept() {
    compare(ModuleStyles.resolvedStyle("tiles", candidates, 10, 10), "tiles", "whatever the room");
    compare(ModuleStyles.resolvedStyle("pills", candidates, 400, 400), "pills", "not a candidate");
  }

  function test_auto_by_room() {
    compare(ModuleStyles.resolvedStyle("auto", candidates, 400, 400), "focus");
    compare(ModuleStyles.resolvedStyle("auto", candidates, 250, 150), "tiles");
    compare(ModuleStyles.resolvedStyle("auto", candidates, 200, 100), "tiles", "edges fit");
    compare(ModuleStyles.resolvedStyle("auto", candidates, 350, 150), "tiles", "width fits focus, height does not");
    compare(ModuleStyles.resolvedStyle("auto", candidates, 100, 50), "list", "the 0/0 fallback");
  }

  function test_auto_nothing_fits() {
    compare(ModuleStyles.resolvedStyle("auto", candidates.slice(0, 2), 10, 10), "tiles", "no 0/0 entry: the last candidate");
    compare(ModuleStyles.resolvedStyle("auto", [], 400, 400), "", "no candidates");
  }

  // WorldClocks' candidates (em = 16: rowMin 2.4 em, tileMinWidth 7 em,
  // tileHeight 4.4 em) must equal its old rule: count > 1, height < count *
  // rowMin, width >= 2 * tileMinWidth, height >= tileHeight
  function worldClocks(count) {
    return [
      {
        "style": "list",
        "minWidth": 0,
        "minHeight": count * 38.4
      },
      {
        "style": "tiles",
        "minWidth": 224,
        "minHeight": 70.4
      },
      {
        "style": "list",
        "minWidth": 0,
        "minHeight": 0
      }
    ];
  }

  function test_world_clocks_parity() {
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(3), 400, 120), "list", "tall enough for 3 rows");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(3), 400, 100), "tiles", "short, wide, tile-high");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(3), 160, 100), "list", "short but under two tiles wide");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(3), 400, 60), "list", "shorter than a tile");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(1), 400, 20), "list", "one place, short");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(1), 400, 80), "list", "one place, tile-high");
    compare(ModuleStyles.resolvedStyle("auto", worldClocks(0), 400, 100), "list", "no places");
    compare(ModuleStyles.resolvedStyle("tiles", worldClocks(3), 400, 400), "tiles", "explicit tiles");
    compare(ModuleStyles.resolvedStyle("list", worldClocks(3), 400, 100), "list", "explicit list");
  }
}
