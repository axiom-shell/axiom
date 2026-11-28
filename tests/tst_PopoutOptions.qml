import QtQuick
import QtTest
import qs.components.methods

// A bar widget's Popout card (the bar editor's card 2), from the real schema:
// its `popout.properties` match its popout module's settings, and the cards
// split the widget's rows without losing any
TestCase {
  id: root

  name: "PopoutOptions"

  RepoFiles {
    id: files
  }

  property var defs: ({})
  // Widget type -> its definition, for every bar widget
  property var widgets: ({})

  function initTestCase() {
    root.defs = files.json("qml/config/json/config.schema.json").definitions;
    const found = {};
    for (const [name, def] of Object.entries(root.defs)) {
      if (name.endsWith("Widget") && def.properties?.type?.const && def.properties?.properties?.properties)
        found[def.properties.type.const] = def;
    }
    root.widgets = found;
  }

  function propsOf(type) {
    return root.widgets[type].properties.properties;
  }

  // The expected result (Go's fillPopoutModules rule, written out again): the
  // settings a widget's popout module takes from the card, all but `grow` and
  // what the widget supplies (`fromWidget`)
  function moduleSettings(widget) {
    const module = widget["x-popoutModule"];
    const settings = root.defs[module.type + "OverlayModule"].properties.properties?.properties ?? ({});
    return Utils.pick(settings, Object.keys(settings).filter(key => key !== "grow" && !(module.fromWidget ?? []).includes(key)));
  }

  // The card schemas of a widget type (SchemaLayout.widgetCards)
  function cards(type) {
    return SchemaLayout.widgetCards(root.propsOf(type).properties);
  }

  // Rows as the form draws them
  function rowPaths(schemaMap) {
    return root.paths(SchemaLayout.formRows(schemaMap, []));
  }

  function paths(rows) {
    return rows.map(row => row.path.join("."));
  }

  function test_there_are_widgets() {
    verify(Object.keys(root.widgets).length > 30, "found " + Object.keys(root.widgets).length);
    verify(root.widgets.Network !== undefined);
  }

  function test_popout_properties_match_module() {
    let checked = 0;
    const absent = [];
    for (const [type, widget] of Object.entries(root.widgets)) {
      if (!widget["x-popoutModule"])
        continue;
      checked++;
      const expected = root.moduleSettings(widget);
      const field = root.propsOf(type).properties.popout?.properties?.properties;
      if (Object.keys(expected).length === 0) {
        verify(!field, type + ": no popout.properties when the module has nothing to show");
        absent.push(type);
        continue;
      }
      verify(field, type + ": has popout.properties");
      compare(JSON.stringify(field.properties), JSON.stringify(expected), type);
    }
    verify(checked > 10, "checked " + checked);
    for (const type of ["ClaudeUsage", "SystemStats", "CustomWidget", "Bluetooth", "Drives", "Updates", "KeyboardLayout"])
      verify(absent.includes(type), type + " has no popout.properties");
  }

  function test_system_tray_popout_has_no_properties() {
    const popout = root.propsOf("SystemTray").properties.popout;
    verify(popout);
    verify(popout.properties.properties === undefined);
  }

  function test_network_card2() {
    const rows = SchemaLayout.formRows(root.cards("Network").popout, []);
    compare(root.paths(rows).join(" "), ["enabled", "menu", "sizing.contentSize", "properties.showConnection", "properties.showVpn"].map(p => "popout." + p).join(" "));
    for (const row of rows.filter(row => row.path[1] === "properties")) {
      const gate = row.groupEnabledIf ?? [];
      compare(gate.length, 1, row.path.join("."));
      compare(gate[0].note, "Off while Open instead names a menu.");
    }
  }

  function test_cards_split_loses_nothing_data() {
    return Object.keys(root.widgets).map(type => ({
          "tag": type,
          "type": type
        }));
  }

  function test_cards_split_loses_nothing(data) {
    const parts = root.cards(data.type);
    const first = root.rowPaths(parts.options);
    const second = root.rowPaths(parts.popout);
    const whole = root.rowPaths(root.propsOf(data.type).properties);
    compare(first.filter(path => second.includes(path)).length, 0, "none in both");
    compare(first.concat(second).sort().join(" "), whole.slice().sort().join(" "));
  }

  function test_volume_card2() {
    const paths = root.rowPaths(root.cards("Volume").popout);
    verify(paths.includes("popout.properties.ignoreApps"), paths.join(" "));
    verify(!paths.includes("popout.properties.mode"));
    verify(!paths.includes("popout.properties.maxVolume"));
  }

  function test_separator_has_no_card2() {
    compare(Object.keys(root.cards("Separator").popout).length, 0);
  }
}
