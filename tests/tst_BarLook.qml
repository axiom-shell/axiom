import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: root

  name: "BarLook"

  RepoFiles {
    id: files
  }

  property var schema: null

  function initTestCase() {
    root.schema = files.json("qml/config/json/config.schema.json");
  }

  // The shared BarStyle: the schema's defaults (shadow as its object)
  function section() {
    const props = root.schema.definitions.BarStyle.properties;
    return Object.keys(props).reduce((values, key) => {
      values[key] = key === "shadow" ? {
        "enabled": false,
        "color": "",
        "size": 12
      } : props[key].default;
      return values;
    }, {});
  }

  readonly property var geometry: ({
      "thickness": 26,
      "innerPadding": 6,
      "innerGap": 4,
      "radius": 8,
      "far": false
    })

  function look(own, bar) {
    return BarLook.resolve(root.section(), own, bar === undefined ? root.geometry : bar);
  }

  function test_the_table_has_every_style_and_solid() {
    compare(Object.keys(BarLook.table).sort(), root.schema.definitions.BarStyle.properties.widgetStyle.enum.concat(["solid"]).sort());
  }

  function test_every_record_has_every_trait() {
    const fields = Object.keys(BarLook.table.filled).sort();
    for (const name in BarLook.table)
      compare(Object.keys(BarLook.table[name]).sort(), fields, name);
  }

  function test_merge_takes_the_shared_style_where_own_is_null() {
    const values = BarLook.merge(root.section(), {
      "widgetStyle": "outline",
      "tintOpacity": null,
      "shadow": {
        "enabled": true,
        "color": null
      }
    });
    compare(values.widgetStyle, "outline");
    compare(values.tintOpacity, 20);
    compare([values.shadow, values.shadowColor, values.shadowSize], [true, "", 12], "the shadow, flat");
  }

  function test_boxed_styles() {
    for (const style of ["filled", "tinted", "outline", "split"])
      verify(root.look({
        "widgetStyle": style
      }).traits.boxed, style);
    for (const style of ["underline", "accentText", "plain"]) {
      const l = root.look({
        "widgetStyle": style,
        "widgetShape": "tab",
        "widgetGrouping": "merged"
      });
      verify(!l.traits.boxed, style);
      compare([l.shape.name, l.grouping], ["rounded", "separate"], style + ": no shape or runs");
    }
  }

  // A separate badge has no box to hang: a saved tab draws rounded
  function test_a_separate_badge_is_no_tab() {
    const shape = (style, icon, shape, grouping) => root.look({
        "widgetStyle": style,
        "splitIcon": icon,
        "widgetShape": shape,
        "widgetGrouping": grouping
      }).shape.name;
    compare(shape("split", "badge", "tab", "separate"), "rounded");
    compare(shape("split", "badge", "tab", "powerline"), "rounded");
    compare(shape("split", "badge", "tab", "merged"), "tab");
    compare(shape("split", "joined", "tab", "separate"), "tab");
    compare(shape("filled", "badge", "tab", "separate"), "tab");
    compare(shape("split", "badge", "capsule", "separate"), "capsule");
  }

  function test_badge_and_tab_have_no_powerline() {
    const grouping = (style, icon, shape, grouping) => root.look({
        "widgetStyle": style,
        "splitIcon": icon,
        "widgetShape": shape,
        "widgetGrouping": grouping
      }).grouping;
    compare(grouping("split", "badge", "rounded", "powerline"), "separate");
    compare(grouping("split", "badge", "rounded", "merged"), "merged");
    compare(grouping("split", "joined", "rounded", "powerline"), "powerline");
    compare(grouping("filled", "badge", "rounded", "powerline"), "powerline");
    compare(grouping("filled", "joined", "tab", "powerline"), "separate");
    compare(grouping("split", "joined", "tab", "merged"), "merged");
  }

  function test_opaque_fills() {
    const opaque = (style, icon, label) => root.look({
        "widgetStyle": style,
        "splitIcon": icon,
        "splitLabelFill": label
      }).traits.opaque;
    verify(opaque("filled", "joined", "tint"), "filled");
    verify(!opaque("tinted", "joined", "color"), "tinted");
    verify(opaque("split", "joined", "color"), "split on a color");
    verify(!opaque("split", "joined", "tint"), "split on a tint");
    verify(!opaque("split", "badge", "color"), "badge");
  }

  function test_cell_traits() {
    const cell = (style, solid) => BarLook.cellTraits(root.look({
        "widgetStyle": style
      }), solid);
    verify(cell("outline", true).cellBoxedInRun, "solid boxes");
    verify(cell("split", false).cellBoxedInRun, "split's fill");
    verify(!cell("filled", false).cellBoxedInRun);
    verify(cell("filled", false).cellOpaque);
    verify(cell("split", false).cellOpaque, "split's cells are filled");
    verify(cell("outline", true).cellOpaque, "solid boxes");
    verify(!cell("tinted", false).cellOpaque);
    verify(!cell("outline", false).cellOpaque);
    verify(cell("tinted", false).tints, "a tint shows through");
    verify(!cell("tinted", true).tints, "a solid box doesn't");
  }

  function test_auto_contrast() {
    const seen = (style, grouping, icon, label) => root.look({
        "widgetStyle": style,
        "widgetGrouping": grouping,
        "splitIcon": icon,
        "splitLabelFill": label
      }).traits.autoContrast;
    compare(seen("filled", "separate", "joined", "tint"), {
      "onRun": false,
      "minContrast": 1.3
    });
    compare(seen("filled", "merged", "joined", "tint"), {
      "onRun": true,
      "minContrast": 3
    });
    compare(seen("tinted", "merged", "joined", "tint"), {
      "onRun": false,
      "minContrast": 3
    });
    // An outline run has no background: its widgets sit on the bar
    compare(seen("outline", "merged", "joined", "tint"), {
      "onRun": false,
      "minContrast": 3
    });
    // Split's color is the label's text too, unless the label has its own
    compare(seen("split", "separate", "joined", "tint").minContrast, 3);
    compare(seen("split", "separate", "badge", "color").minContrast, 3);
    compare(seen("split", "powerline", "joined", "color").minContrast, 1.3);
    compare(seen("split", "merged", "joined", "tint"), {
      "onRun": true,
      "minContrast": 1.3
    });
    // A powerline of badges draws as separate: seen as separate
    compare(seen("filled", "powerline", "joined", "tint").onRun, false);
  }

  function test_gradient_parts() {
    const part = (style, tint) => root.look({
        "widgetStyle": style,
        "tintOpacity": tint ?? 20
      }).traits.gradientPart;
    compare(part("filled"), {
      "part": "fill",
      "alpha": 1
    });
    compare(part("tinted", 40), {
      "part": "fill",
      "alpha": 0.4
    }, "the tint's");
    compare(part("outline").part, "stroke");
    compare(part("underline").part, "indicator");
    compare(part("split").part, "iconFill");
    compare(part("accentText"), null);
    compare(part("plain"), null);
  }

  function test_only_a_style_drawing_one_has_its_parts() {
    const l = style => root.look({
        "widgetStyle": style
      });
    compare(l("outline").outline, {
      "width": 2,
      "stroke": "solid"
    });
    compare(l("filled").outline, null);
    compare(l("underline").line, {
      "width": 2,
      "side": "inner",
      "farSide": true
    });
    compare(l("tinted").line, null);
    compare(l("filled").split, null);
    compare(l("split").split.icon, "joined");
  }

  // The line's side further from the outer edge, in item coordinates:
  // toward the windows, the far side on a top bar, the near on a bottom one
  function test_the_line_side() {
    const far = (side, onFar) => root.look({
        "widgetStyle": "underline",
        "lineSide": side
      }, Object.assign({}, root.geometry, {
        "far": onFar
      })).line.farSide;
    verify(far("inner", false));
    verify(!far("inner", true));
    verify(!far("outer", false));
    verify(far("outer", true));
  }

  function test_fill_on_hover_only_where_it_applies() {
    const hover = style => root.look({
        "widgetStyle": style,
        "hoverFill": true
      }).hoverFill;
    verify(hover("tinted"));
    verify(hover("outline"));
    verify(!hover("filled"), "filled already");
    verify(!hover("split"));
    verify(!root.look({
      "widgetStyle": "tinted",
      "hoverFill": false
    }).hoverFill, "off");
  }

  function test_split_geometry_from_the_bar() {
    const s = root.look({
      "widgetStyle": "split",
      "widgetShape": "slant"
    }).split;
    compare(s.cap, "slant", "match: the shape's");
    compare(s.room, BarShapes.splitRoom("joined", "slant", 26, 6, 6, 4));
    compare(s.badgePad, 4);
    compare(root.look({
      "widgetStyle": "split"
    }, null).split.room, -1, "no bar: no room");
  }

  function test_gradient_and_separators_as_drawn() {
    compare(root.look({
      "gradient": true,
      "gradientVia": "base0B"
    }).gradient, ["accent", "base0B", "accentAlt"]);
    compare(root.look({
      "gradient": true,
      "widgetStyle": "plain"
    }).gradient, null, "plain has nothing to color");
    compare(root.look({
      "separatorStyle": "dot",
      "widgetGrouping": "powerline"
    }).separators.style, "none", "a powerline's widgets touch");
    compare(root.look({
      "separatorStyle": "dot",
      "widgetStyle": "plain",
      "widgetGrouping": "powerline"
    }).separators.style, "dot", "an unboxed powerline is separate");
  }

  function test_accent_line() {
    compare(root.look({}).accentLine, null);
    compare(root.look({
      "accentLine": "outer",
      "accentLineWidth": 3
    }).accentLine, {
      "side": "outer",
      "color": "accent",
      "fade": "",
      "width": 3
    });
  }

  function test_radius_falls_back_to_the_bars() {
    compare(root.look({}).radius, 8);
    compare(root.look({
      "widgetRadius": 3
    }).radius, 3);
  }

  // `$bar.<key>`: every BarStyle key, shape and grouping as drawn (the
  // shape whether boxed or not, as the inspector has it)
  function test_context() {
    const context = BarLook.context(root.look({
      "widgetStyle": "split",
      "splitIcon": "badge",
      "widgetShape": "tab",
      "widgetGrouping": "powerline"
    }, null));
    compare(Object.keys(context).sort(), Object.keys(root.schema.definitions.BarStyle.properties).map(key => "$bar." + key).sort());
    compare(context["$bar.widgetShape"], "rounded");
    compare(context["$bar.widgetGrouping"], "separate");
    compare(context["$bar.shadow"], false, "the shadow, flat");
    const plain = BarLook.context(root.look({
      "widgetStyle": "plain",
      "widgetShape": "tab"
    }, null));
    compare([plain["$bar.widgetShape"], plain["$bar.widgetGrouping"]], ["tab", "separate"]);
  }
}
