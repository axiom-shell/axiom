import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "CompositorLayer"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  RepoFiles {
    id: files
  }

  readonly property var opts: ({
      "activeHex": "aabbcc",
      "inactiveHex": "112233",
      "borderWidth": 2,
      "radius": 8,
      "surfacesBlur": true
    })

  function defaults() {
    const schema = files.json("config/json/config.schema.json");
    return SchemaValidation.applyDefaults({}, schema.properties.WindowLook, schema);
  }

  // WindowLook's defaults with `parts` over them, each group's keys one by one
  function lookWith(parts) {
    const values = defaults();
    for (const part in parts)
      Object.assign(values[part], parts[part]);
    return values;
  }

  function test_hex() {
    compare(shared.calls.CompositorLayer.hex({
      "r": 1,
      "g": 0,
      "b": 0.5
    }), "ff0080");
  }

  function test_look_off_by_default() {
    const look = shared.calls.CompositorLayer.look(defaults(), opts);
    compare(look.parts, []);
    compare(look.borders, null);
    compare(look.shape, null);
    compare(look.gaps, null);
    compare(look.blur, null);
    compare(look.shadow, null);
    compare(look.dim, null);
    compare(look.opacity, null);
  }

  function test_look_shadow_and_dim() {
    const values = lookWith({
      "shadow": {
        "enabled": true,
        "size": 12
      },
      "dim": {
        "enabled": true,
        "strength": 15
      }
    });
    const cast = (color, alpha, offset) => Object.assign({}, opts, {
        "shadow": {
          "size": 12,
          "color": color,
          "alpha": alpha,
          "offset": offset
        }
      });
    const look = shared.calls.CompositorLayer.look(values, cast("101010", 0.6, 3));
    compare(look.parts, ["shadow", "dim"]);
    compare(look.shadow, {
      "size": 12,
      "power": values.shadow.power,
      "color": "10101099",
      "rgb": "101010",
      "alpha": 0.6,
      "baseAlpha": 0.6,
      "strength": 1,
      "offset": 3,
      "soft": false
    });
    compare(look.dim, {
      "strength": 15
    });
    compare(shared.calls.CompositorLayer.look(values, cast("", 1, 0)).shadow.color, "", "no color: the compositor's own");
    compare(shared.calls.CompositorLayer.look(values, cast("c4a7e7", 1, 0)).shadow.color, "c4a7e7ff");
    const strong = cast("101010", 0.4, 0);
    strong.shadow.strength = 2;
    compare(shared.calls.CompositorLayer.look(values, strong).shadow.color, "101010cc", "the strength scales the alpha");
    strong.shadow.strength = 4;
    compare(shared.calls.CompositorLayer.look(values, strong).shadow.color, "101010ff", "up to opaque");
  }

  function test_luminance() {
    compare(shared.calls.CompositorLayer.luminance("000000"), 0);
    compare(shared.calls.CompositorLayer.luminance("ffffff"), 1);
    fuzzyCompare(shared.calls.CompositorLayer.luminance("c4a7e7"), 0.45, 0.01);
  }

  // Matching axiom's shadow while it casts none: no shadow, the part off
  function test_look_shadow_none() {
    const values = Object.assign(defaults(), {
      "shadow": true
    });
    const look = shared.calls.CompositorLayer.look(values, Object.assign({}, opts, {
      "shadow": null
    }));
    compare(look.shadow, null);
    compare(look.parts, []);
  }

  function test_look_parts() {
    const values = lookWith({
      "borders": {
        "enabled": true
      },
      "shape": {
        "enabled": true
      },
      "gaps": {
        "enabled": true,
        "inner": 4,
        "outer": 12
      },
      "blur": {
        "enabled": true,
        "windowBlur": false
      },
      "opacity": {
        "enabled": true,
        "inactive": 90
      }
    });
    const look = shared.calls.CompositorLayer.look(values, opts);
    compare(look.parts, ["borders", "shape", "gaps", "blur", "opacity"]);
    compare(look.borders, {
      "active": "aabbcc",
      "inactive": "112233"
    });
    compare(look.shape, {
      "width": 2,
      "radius": 8
    });
    compare(look.gaps, {
      "inner": 4,
      "outer": 12
    });
    compare(look.blur, {
      "windows": false,
      "surfaces": true,
      "size": values.blur.size,
      "passes": values.blur.passes,
      "xray": values.blur.xray,
      "noise": values.blur.noise,
      "contrast": values.blur.contrast
    });
    compare(look.opacity.inactive, 90);
    compare(look.opacity.active, 100);
    compare(look.values, values, "the values, for annotation-driven fields");
  }
}
