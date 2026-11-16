import QtQuick
import QtTest
import qs.components.methods

// The settings page indents a row only under the row its value depends on
// (RowTree over each card's rows), from the real schema
TestCase {
  id: root

  name: "SettingsIndent"

  RepoFiles {
    id: files
  }

  property var schema: null
  // Dotted path of a row -> its level, over every card of every category
  property var levels: ({})

  function initTestCase() {
    root.schema = files.json("qml/config/json/config.schema.json");
    const found = {};
    for (const category of SchemaLayout.categories(root.schema)) {
      for (const group of SchemaLayout.categoryGroups(root.schema, category)) {
        const rows = group.rows ?? [];
        const plan = RowTree.plan(rows);
        rows.forEach((row, i) => found[row.path.join(".")] = plan.levels[i]);
      }
    }
    root.levels = found;
  }

  function test_settingsRows_data() {
    return [
      {
        "path": "WindowSwitcher.edge",
        "level": 0,
        "why": "gated by a field in another card: no rail"
      },
      {
        "path": "WorkspaceOverlay.size",
        "level": 0,
        "why": "gated by a field in another card: no rail"
      },
      {
        "path": "Idle.dim",
        "level": 1,
        "why": "the Dim heading under Handle idle"
      },
      {
        "path": "Idle.dim.level",
        "level": 2,
        "why": "under Mode, under Handle idle"
      },
      {
        "path": "Appearance.wallpaper.rotation.interval",
        "level": 1,
        "why": "under Mode"
      },
      {
        "path": "WindowLook.blur.xray",
        "level": 2,
        "why": "under Blur transparent windows, under Match axiom's shape"
      },
      {
        "path": "Input.keyboard.method.autostart",
        "level": 2,
        "why": "under Framework"
      },
      {
        "path": "NightLight.startAt",
        "level": 1,
        "why": "under On a schedule"
      }
    ];
  }

  function test_settingsRows(data) {
    compare(root.levels[data.path], data.level, data.path + ": " + data.why);
  }

  // BarStyleBlock draws one SchemaPropertiesForm per section: levels per form
  function formLevels(title) {
    const group = SchemaLayout.objectGroups(root.schema.definitions.BarStyle, []).find(g => g.title === title);
    verify(group, "section " + title);
    const rows = group.keys.reduce((all, key) => all.concat(SchemaLayout.rows({
        "properties": {
          [key]: root.schema.definitions.BarStyle.properties[key]
        }
      }, []).filter(row => row.kind !== "group" && row.kind !== "object")), []);
    const plan = RowTree.plan(rows);
    const out = {};
    rows.forEach((row, i) => out[row.path.join(".")] = plan.levels[i]);
    return out;
  }

  function test_barStyleSections() {
    const look = root.formLevels("Look");
    compare(look.splitLabelColor, 3);
    compare(look.tintOpacity, 0);
    const colors = root.formLevels("Colors");
    compare(colors.groupColor, 0);
    compare(colors.gradientFrom, 1);
  }
}
