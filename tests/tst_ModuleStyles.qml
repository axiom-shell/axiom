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
}
