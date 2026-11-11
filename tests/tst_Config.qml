import QtQuick
import QtTest
import qs.components.methods

// The real schema's defaults, filled in as the shell fills them: the calls
// go through Shared, so the axiom binary is checked against the same bytes
// (that they're valid is the binary's TestSchemaDefaultsAreValid).
TestCase {
  id: test
  name: "Config"

  // Records the helper calls as shared fixtures (Shared.qml)
  Shared {
    id: shared
    testCase: test
  }

  property var schema

  function initTestCase() {
    schema = shared.schema;
  }

  function test_defaults_fill() {
    const defaults = shared.applyDefaults({}, schema);
    compare(defaults.format, 2);
    compare(defaults.version, schema.properties.version.default);
  }

  function test_every_variant_default_fills_data() {
    const rows = [];
    for (const union of ["BarWidget", "OverlayModule", "OverlayView"]) {
      for (const option of schema.definitions[union].oneOf) {
        const name = option.$ref.split("/").pop();
        const type = schema.definitions[name].properties.type.const;
        rows.push({
          tag: union + ":" + type,
          union: union,
          type: type
        });
      }
    }
    return rows;
  }

  function test_every_variant_default_fills(data) {
    const unionSchema = {
      "$ref": "#/definitions/" + data.union
    };
    // Format 2's items carry a stable id
    const filled = shared.applyDefaults({
      "type": data.type,
      "id": "test"
    }, unionSchema, schema);
    compare(filled.type, data.type);
  }

  // A new edge menu (MenuEditor) fills the same way
  function test_edge_menu_default_fills() {
    const filled = shared.applyDefaults({
      "id": "test"
    }, {
      "$ref": "#/definitions/Menu"
    }, schema);
    compare(filled.id, "test");
  }

  // A widget drawing a value style draws its icon and label in its
  // foregroundColor on a filled bar: without the field they're transparent
  function test_value_widgets_have_foreground_color() {
    for (const option of schema.definitions.BarWidget.oneOf) {
      const name = option.$ref.split("/").pop();
      const settings = schema.definitions[name].properties.properties.properties;
      if (settings.appearance)
        verify(settings.foregroundColor !== undefined, name + " has no foregroundColor");
    }
  }

  // One Auto accent role per widget type: the bar picks a widget's accent
  // from the first, so a second would fall to a neutral (Network's VPN lock).
  // LockKeys grades its warning-role active state by `x-autoGradient`, not
  // by a second accent.
  function test_widgets_have_one_accent_role() {
    for (const option of schema.definitions.BarWidget.oneOf) {
      const name = option.$ref.split("/").pop();
      const settings = schema.definitions[name].properties.properties.properties;
      const accents = Object.keys(settings).filter(key => settings[key]["x-autoColor"] === "accent");
      verify(accents.length <= 1, name + " has several accent roles: " + accents.join(", "));
    }
  }

  // Which Auto fields give way to the bar's gradient: an accent always, any
  // other role only by `x-autoGradient`; idle and off states never
  function test_auto_gradient_fields() {
    for (const option of schema.definitions.BarWidget.oneOf) {
      const name = option.$ref.split("/").pop();
      const settings = schema.definitions[name].properties.properties.properties;
      for (const key of Object.keys(settings)) {
        const field = settings[key];
        const where = name + "." + key;
        verify(field["x-autoColor"] !== "rest", where + " has the removed role rest");
        if ("x-autoGradient" in field) {
          verify("x-autoColor" in field, where + ": x-autoGradient without x-autoColor");
          verify(field["x-autoColor"] !== "off" && field["x-autoColor"] !== "neutral", where + ": an " + field["x-autoColor"] + " field never grades");
        }
        if (field["x-autoColor"] === "accent")
          verify(field["x-autoGradient"] !== false, where + ": an accent field always grades");
      }
    }
  }
}
