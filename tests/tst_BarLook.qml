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
    verify(cell("outline", true).boxedInRun, "solid boxes");
    verify(cell("split", false).boxedInRun, "split's fill");
    verify(!cell("filled", false).boxedInRun);
    verify(cell("filled", false).cellOpaque);
    verify(cell("split", false).cellOpaque, "split's cells are filled");
    verify(cell("outline", true).cellOpaque, "solid boxes");
    verify(!cell("tinted", false).cellOpaque);
    verify(!cell("outline", false).cellOpaque);
    verify(cell("tinted", false).tints, "a tint shows through");
    verify(!cell("tinted", true).tints, "a solid box doesn't");
  }

  // What a box of each style paints each part in, as data: paint reads
  // only these (BarWidgetStyle._box)
  function test_box_paints() {
    const box = style => BarLook.table[style].box;
    const row = b => [b.fill, b.stroke, b.indicator, b.text, b.icon, b.keepsIcon];
    compare(row(box("filled")), ["color", null, null, "own", "own", false]);
    compare(row(box("tinted")), ["tint", null, null, "color", "color", false]);
    compare(row(box("outline")), ["unfilled", "color", null, "color", "color", false]);
    compare(row(box("underline")), [null, null, "color", "bar", "bar", false]);
    compare(row(box("accentText")), [null, null, null, "bar", "color", true], "colored icons keep the state");
    compare(row(box("plain")), [null, null, null, "bar", "bar", false]);
    compare(row(box("solid")), ["color", "color", "color", "own", "own", false], "its line and stroke its color too");
    compare(box("split"), null, "its parts instead (iconPart)");
    // Every value is one paint resolves
    const roles = ["color", "tint", "unfilled", "own", "bar", null];
    for (const name in BarLook.table)
      if (BarLook.table[name].box)
        for (const part of ["fill", "stroke", "indicator", "text", "icon"])
          verify(roles.indexOf(BarLook.table[name].box[part]) >= 0, `${name}.${part}`);
  }

  function test_icon_parts_and_runs() {
    const traits = style => root.look({
        "widgetStyle": style
      }).traits;
    for (const style of ["filled", "tinted", "outline", "underline", "accentText", "plain"]) {
      verify(!traits(style).iconPart, style);
      verify(!traits(style).runTints, style);
      verify(!traits(style).boxedInRun, style);
    }
    verify(traits("split").iconPart);
    verify(traits("split").runTints, "a gradient run is its labels' tint");
    verify(traits("split").boxedInRun, "a widget that doesn't split keeps its box in a run");
    compare(traits("split").fallback, "filled");
  }

  function test_only_plain_shows_no_color() {
    for (const name in BarLook.table)
      compare(BarLook.table[name].colored, name !== "plain", name);
  }

  // The label's fill as drawn: a badge's is always on the bar
  function test_split_label_as_drawn() {
    const label = (icon, fill) => root.look({
        "widgetStyle": "split",
        "splitIcon": icon,
        "splitLabelFill": fill
      }).split.label;
    compare(label("joined", "tint"), "tint");
    compare(label("joined", "color"), "color");
    compare(label("joined", "none"), "none");
    compare(label("badge", "color"), "none");
    compare(label("badge", "tint"), "none");
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
  // shape whether boxed or not, as the inspector has it), and the traits
  // the user sees (contextTraits)
  function test_context() {
    const context = BarLook.context(root.look({
      "widgetStyle": "split",
      "splitIcon": "badge",
      "widgetShape": "tab",
      "widgetGrouping": "powerline"
    }, null));
    compare(Object.keys(context).sort(), Object.keys(root.schema.definitions.BarStyle.properties).concat(Object.keys(BarLook.contextTraits)).map(key => "$bar." + key).sort());
    compare(context["$bar.widgetShape"], "rounded");
    compare(context["$bar.widgetGrouping"], "separate");
    compare(context["$bar.shadow"], false, "the shadow, flat");
    const plain = BarLook.context(root.look({
      "widgetStyle": "plain",
      "widgetShape": "tab"
    }, null));
    compare([plain["$bar.widgetShape"], plain["$bar.widgetGrouping"]], ["tab", "separate"]);
  }

  // The traits a widget's options ask of its bar (`$bar.<trait>`), per
  // style: [boxed, merged, underlined, ownColorShows, textColorShows,
  // cellsFilled]
  function test_context_traits() {
    const names = ["boxed", "merged", "underlined", "ownColorShows", "textColorShows", "cellsFilled"];
    compare(Object.keys(BarLook.contextTraits).sort(), names.slice().sort());
    const row = (style, own) => {
      const context = BarLook.context(root.look(Object.assign({
        "widgetStyle": style
      }, own ?? {}), null));
      return names.map(name => context["$bar." + name]);
    };
    compare(row("filled"), [true, false, false, true, true, true], "filled");
    compare(row("tinted"), [true, false, false, true, false, false], "tinted");
    compare(row("outline"), [true, false, false, true, false, false], "outline");
    compare(row("split"), [true, false, false, true, true, true], "split");
    compare(row("underline"), [false, false, true, true, false, false], "underline");
    compare(row("accentText"), [false, false, false, true, false, false], "colored icons");
    compare(row("plain"), [false, false, false, false, false, false], "plain text");
    const merged = {
      "widgetGrouping": "merged"
    };
    compare(row("filled", merged), [true, true, false, true, false, true], "a merged filled run: the text reads on the run");
    compare(row("split", merged), [true, true, false, true, true, true], "a merged split run: the icon parts keep theirs");
    compare(row("underline", merged)[1], false, "merged as drawn: an unboxed style draws separate");
    compare(row("tinted", {
      "hoverFill": true
    })[4], true, "filled on hover");
    compare(row("underline", {
      "hoverFill": true
    })[4], false, "no fill on hover where it doesn't apply");
    compare(row("filled", {
      "widgetTextColor": "base05"
    })[4], false, "the bar's own text color");
  }

  // BarStyle.yaml's own conditions (on its sibling keys: the settings page
  // has no `$bar` context) list styles; each list is the styles of one
  // trait, so the two can't drift: [field, the list in its condition, the
  // trait as a predicate of a style's name]
  function test_bar_style_conditions_agree_with_the_traits() {
    const props = root.schema.definitions.BarStyle.properties;
    const styles = props.widgetStyle.enum;
    const traits = style => root.look({
        "widgetStyle": style
      }, null).traits;
    const has = trait => style => traits(style)[trait];
    // A box whatever the split icon: what chains in a powerline or hangs
    // as a tab
    const steadyBox = style => {
      const record = BarLook.table[style];
      return record.hasBox(root.look({
        "widgetStyle": style,
        "splitIcon": "badge"
      }, null)) === record.hasBox(root.look({
        "widgetStyle": style,
        "splitIcon": "joined"
      }, null));
    };
    const showIf = field => props[field]["x-showIf"];
    const separators = ["separatorStyle", "separatorColor", "separatorThickness", "separatorGap"].map(field => [field, showIf(field).anyOf[1].widgetStyle, style => !traits(style).boxed]);
    const rules = [["splitIcon", showIf("splitIcon").widgetStyle, has("iconPart")], ["splitLabelFill", showIf("splitLabelFill").widgetStyle, has("iconPart")], ["splitLabelColor", showIf("splitLabelColor").widgetStyle, has("iconPart")], ["splitDivider", showIf("splitDivider").widgetStyle, has("iconPart")], ["tintOpacity", showIf("tintOpacity").anyOf[0].widgetStyle, has("tints")], ["tintOpacity (split's label)", showIf("tintOpacity").anyOf[1].widgetStyle, has("iconPart")], ["tintOpacity (split's run)", showIf("tintOpacity").anyOf[2].widgetStyle, has("runTints")], ["outlineWidth", showIf("outlineWidth").widgetStyle, has("stroke")], ["outlineStroke", showIf("outlineStroke").widgetStyle, has("stroke")], ["hoverFill", showIf("hoverFill").widgetStyle, has("hoverFills")], ["lineWidth", showIf("lineWidth").widgetStyle, has("line")], ["lineSide", showIf("lineSide").widgetStyle, has("line")], ["widgetShape", showIf("widgetShape").widgetStyle, has("boxed")], ["widgetShape: tab", props.widgetShape["x-enumShowIf"].tab.anyOf[0].widgetStyle, steadyBox], ["widgetGrouping", showIf("widgetGrouping").widgetStyle, has("boxed")], ["widgetGrouping: powerline", props.widgetGrouping["x-enumShowIf"].powerline.anyOf[0].widgetStyle, steadyBox], ["tabCorners", showIf("tabCorners").widgetStyle, has("boxed")], ["widgetEnds", showIf("widgetEnds").widgetStyle, has("boxed")], ["widgetEnds (split)", showIf("widgetEnds").anyOf[0].widgetStyle, steadyBox], ["groupColor", showIf("groupColor").widgetStyle, style => traits(style).boxed && !traits(style).stroke], ["groupStrokeColor", showIf("groupStrokeColor").widgetStyle, has("stroke")], ["gradient", showIf("gradient").widgetStyle, has("colored")], ["gradientFrom", showIf("gradientFrom").widgetStyle, has("colored")], ["gradientTo", showIf("gradientTo").widgetStyle, has("colored")], ["gradientVia", showIf("gradientVia").widgetStyle, has("colored")]].concat(separators);
    for (const [field, list, trait] of rules) {
      verify(list !== undefined, field + " lists styles");
      const listed = styles.filter(style => SchemaLayout.showIfHolds({
          "widgetStyle": list
        }, () => style));
      compare(listed, styles.filter(trait), field);
    }
  }

  // What a widget's content keeps clear of at its ends (BarShapes.segment):
  // the look's radius and outline, and whether a box is drawn there at all
  function test_shape_carries_what_content_keeps_clear_of() {
    const outlined = root.look({
      "widgetStyle": "outline",
      "outlineWidth": 3,
      "outlineStroke": "double"
    }).shape;
    compare([outlined.radius, outlined.outline.width, outlined.outline.stroke, outlined.capped], [8, 3, "double", true]);
    compare(root.look({
      "widgetStyle": "filled"
    }).shape.outline, null);
    const capped = (style, icon, grouping) => root.look({
        "widgetStyle": style,
        "splitIcon": icon,
        "widgetGrouping": grouping
      }).shape.capped;
    compare(capped("underline", "joined", "separate"), false, "no box");
    compare(capped("plain", "joined", "merged"), false, "no box");
    compare(capped("split", "joined", "separate"), true);
    compare(capped("split", "badge", "separate"), false, "a badge: no box round it");
    compare(capped("split", "badge", "merged"), true, "a merged run of badges: the run's box");
  }
}
