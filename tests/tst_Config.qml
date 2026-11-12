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

  // A colour field is `color` or ends in `Color`: check_structure's T4 tells
  // a colour name from a state word by that
  function test_widget_color_fields_are_named_color() {
    for (const option of schema.definitions.BarWidget.oneOf) {
      const name = option.$ref.split("/").pop();
      const settings = schema.definitions[name].properties.properties.properties;
      for (const key of Object.keys(settings)) {
        if (settings[key]["x-options"] === "colors")
          verify(/^(color|\w+Color)$/.test(key), name + "." + key + " is a colour field not named color or *Color");
      }
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

  // The state fields P1 and the Network lock rely on: their Auto role and
  // whether they follow the bar's gradient
  function test_state_fields_data() {
    return [
      {
        "tag": "DevMode.failedColor",
        "type": "DevMode",
        "key": "failedColor",
        "role": "critical",
        "grades": false
      },
      {
        "tag": "Updates.failedColor",
        "type": "Updates",
        "key": "failedColor",
        "role": "critical",
        "grades": false
      },
      {
        "tag": "NextEvent.soonColor",
        "type": "NextEvent",
        "key": "soonColor",
        "role": "warning",
        "grades": false
      },
      {
        "tag": "Markets.upColor",
        "type": "Markets",
        "key": "upColor",
        "role": "rise",
        "grades": false
      },
      {
        "tag": "Markets.downColor",
        "type": "Markets",
        "key": "downColor",
        "role": "fall",
        "grades": false
      },
      {
        "tag": "Notifications.badgeColor",
        "type": "Notifications",
        "key": "badgeColor",
        "role": "critical",
        "grades": false
      },
      {
        "tag": "Notifications.dndColor",
        "type": "Notifications",
        "key": "dndColor",
        "role": "off",
        "grades": false
      },
      {
        "tag": "Network.vpnColor",
        "type": "Network",
        "key": "vpnColor",
        "role": "alt",
        "grades": true
      }
    ];
  }

  function test_state_fields(row) {
    const name = row.type + "Widget";
    verify(schema.definitions.BarWidget.oneOf.some(o => o.$ref.split("/").pop() === name), row.type + " is a widget type");
    const field = schema.definitions[name].properties.properties.properties[row.key];
    verify(field !== undefined, row.tag + " exists");
    compare(field["x-autoColor"], row.role);
    compare(field["x-autoGradient"] === true, row.grades);
  }
}
