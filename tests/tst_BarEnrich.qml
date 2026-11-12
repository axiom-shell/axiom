import QtQuick
import QtTest
import qs.components.methods
import "barstyle/Bars.js" as Bars

// BarEnrich's pure rules: a type's Auto color fields from the schema, the
// Auto colors picked into a bar's widgets, a bar's kind and what it
// reserves. Bars come from the real schema's defaults (barstyle/Bars.js).
TestCase {
  name: "BarEnrich"

  readonly property var fields: ({
      "Alpha": {
        "stateColor": {
          "role": "accent",
          "gradient": true
        },
        "offColor": {
          "role": "off",
          "gradient": false
        }
      }
    })

  // Alpha: a visible, a hidden, and one of a type with no Auto fields
  function widgets(over) {
    return {
      "left": [
        {
          "type": "Alpha",
          "properties": {}
        },
        {
          "type": "Alpha",
          "visible": false,
          "properties": {}
        }
      ],
      "center": [
        {
          "type": "Plain",
          "properties": {}
        }
      ],
      "right": []
    };
  }

  function test_with_auto_colors_picks_each_empty_field_with_its_role_and_gradient() {
    const bar = Bars.bar({});
    const out = BarEnrich.withAutoColors(widgets(), bar.look, Bars.env({
      "autoColorFields": fields
    }));
    const first = out.left[0];
    compare(Object.keys(first.autoColors).sort(), ["offColor", "stateColor"]);
    compare(first.autoColors.stateColor, {
      "role": "accent",
      "gradient": true
    });
    compare(first.autoColors.offColor, {
      "role": "off",
      "gradient": false
    });
    verify(first.properties.stateColor !== "" && first.properties.offColor !== "", "colors picked");
  }

  // A trend's Auto colors are success and error, swapped under Red for gains
  function test_with_auto_colors_gives_rise_and_fall_their_colors() {
    const raw = {
      "left": [
        {
          "type": "Markets",
          "properties": {}
        }
      ]
    };
    const fields = {
      "Markets": {
        "upColor": {
          "role": "rise",
          "gradient": false
        },
        "downColor": {
          "role": "fall",
          "gradient": false
        }
      }
    };
    const picked = over => BarEnrich.withAutoColors(raw, Bars.bar({}).look, Bars.env(Object.assign({
        "autoColorFields": fields
      }, over))).left[0].properties;
    compare([picked({}).upColor, picked({}).downColor], ["success", "error"]);
    compare([picked({
        "redForGains": true
      }).upColor, picked({
        "redForGains": true
      }).downColor], ["error", "success"]);
  }

  function test_with_auto_colors_skips_hidden_widgets_and_unknown_types() {
    const raw = widgets();
    const out = BarEnrich.withAutoColors(raw, Bars.bar({}).look, Bars.env({
      "autoColorFields": fields
    }));
    compare(out.left[1], raw.left[1], "a hidden widget is left as it was");
    compare(out.center, raw.center, "a type with no Auto fields too");
    compare(out.right, raw.right, "and an empty section");
  }

  function test_with_auto_colors_keeps_a_set_color() {
    const raw = widgets();
    raw.left[0].properties.stateColor = "base0B";
    const out = BarEnrich.withAutoColors(raw, Bars.bar({}).look, Bars.env({
      "autoColorFields": fields
    }));
    compare(out.left[0].properties.stateColor, "base0B", "as set");
    compare(Object.keys(out.left[0].autoColors), ["offColor"], "only the empty one is Auto");
  }

  // The schema's own: Battery's charging color gives way to the gradient,
  // its warning color does not
  function test_auto_color_fields_reads_the_schema() {
    const all = BarEnrich.autoColorFields(Bars.schema());
    compare(all.Battery.chargingColor, {
      "role": "alt",
      "gradient": true
    });
    compare(all.Battery.lowColor.gradient, false, "x-autoColor without x-autoGradient");
    compare(all.Battery.lowColor.role, "warning");
    compare(BarEnrich.autoColorFields(null), {}, "no schema");
    compare(BarEnrich.autoColorFields({}), {}, "no definitions");
  }

  // A bar built with the real fields has its widgets' Auto colors picked
  function test_enrich_picks_auto_colors_of_its_widgets() {
    const bar = Bars.bar({
      "widgets": {
        "left": [
          {
            "type": "Battery",
            "properties": {}
          }
        ],
        "center": [],
        "right": []
      }
    });
    const battery = bar.widgets.left[0];
    verify(battery.autoColors !== undefined && battery.autoColors.chargingColor.gradient, "Battery's charging color is Auto and gives way");
    verify(battery.properties.chargingColor !== "", "and picked");
  }

  function test_kind_of() {
    const kind = (surface, floating) => BarEnrich.kindOf({
        "surface": surface,
        "floating": floating
      });
    compare(kind("none", true), "transparent", "no surface never floats");
    compare(kind("none", false), "transparent");
    compare(kind("pills", false), "pills");
    compare(kind("pills", true), "floatingPills");
    compare(kind("bar", false), "solid");
    compare(kind("bar", true), "floating");
  }

  function test_reserve_trim() {
    const bar = (kind, side) => ({
          "kind": kind,
          "look": {
            "accentLine": side ? {
              "side": side
            } : null
          }
        });
    compare(BarEnrich.reserveTrim(bar("transparent", ""), 10), 10, "transparent: its gaps_out");
    compare(BarEnrich.reserveTrim(bar("transparent", "outer"), 10), 10, "an outer line is no inner edge");
    compare(BarEnrich.reserveTrim(bar("transparent", "inner"), 10), 0, "an inner line is the edge");
    compare(BarEnrich.reserveTrim(bar("solid", ""), 10), 0, "a surface reserves its extent");
  }
}
