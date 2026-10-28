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

  RepoFiles {
    id: files
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
}
