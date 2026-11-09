import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarWidgetStyle"

  readonly property color accent: "#ff0000"
  readonly property color own: "#000000"
  readonly property color barText: "#ffffff"
  readonly property color custom: "#00ff00"

  function same(actual, expected, message) {
    verify(Qt.colorEqual(actual, expected), `${message}: ${actual} != ${expected}`);
  }

  // The rows give a widget's style flat, as one object ({ fill, barText,
  // override, tint, group (a merged run's color, or null), splits,
  // splitIcon, labelFill, labelColor, hoverFill, hovered, gradient, auto,
  // run }; a `fill` of "solid" a cell's solid box): as the look, palette
  // and state paint takes
  function lookOf(style) {
    const name = style.fill === "solid" ? "filled" : style.fill;
    const look = {
      "style": name,
      "tint": style.tint ?? 0.2,
      "textColor": "",
      "split": name === "split" ? {
        "icon": style.splitIcon ?? "joined",
        "labelFill": style.labelFill ?? "tint",
        "labelColor": ""
      } : null,
      "grouping": style.group ? "merged" : "separate",
      "group": {
        "color": "",
        "strokeColor": ""
      },
      "gradient": null
    };
    look.traits = BarLook.traitsOf(name, look);
    look.hoverFill = style.hoverFill === true && look.traits.hoverFills;
    return look;
  }

  function paletteOf(style) {
    return {
      "barText": style.barText,
      "override": style.override ?? null,
      "labelColor": style.labelColor ?? null,
      "group": style.group ?? null,
      "groupStroke": null,
      "gradientStops": null
    };
  }

  function stateOf(style) {
    return {
      "gradient": style.gradient ?? null,
      "splits": style.splits === true,
      "hovered": style.hovered === true,
      "auto": style.auto === true,
      "run": style.run === true,
      "group": !!style.group,
      "solid": style.fill === "solid"
    };
  }

  function paint(style, accent, own) {
    return BarWidgetStyle.colors(lookOf(style), paletteOf(style), stateOf(style), accent, own);
  }

  function paintCell(style, color, own, state) {
    return BarWidgetStyle.cell(lookOf(style), paletteOf(style), stateOf(style), color, own, state);
  }

  function styled(fill, override = null, group = null) {
    return paint({
      "fill": fill,
      "barText": barText,
      "override": override,
      "tint": 0.25,
      "group": group
    }, accent, own);
  }

  function test_filled_keeps_the_widgets_own_colors() {
    const c = styled("filled");
    same(c.fill, accent, "fill");
    same(c.text, own, "text");
    same(c.icon, own, "icon");
    same(c.stroke, "transparent", "stroke");
    same(c.indicator, "transparent", "indicator");
  }

  function test_unknown_fill_is_filled() {
    same(styled("nonsense").fill, accent, "fill");
  }

  function test_tinted_is_the_accent_faded_with_accent_text() {
    const c = styled("tinted");
    same(c.fill, Qt.alpha(accent, 0.25), "fill");
    same(c.text, accent, "text");
    same(c.icon, accent, "icon");
  }

  // A widget with no color of its own (a clear one) tints nothing,
  // rather than black at the tint's opacity
  function test_a_clear_color_stays_clear_where_faded() {
    const clear = c => paint({
        "fill": c,
        "barText": barText,
        "override": null,
        "tint": 0.25,
        "splits": true,
        "splitIcon": "joined",
        "labelFill": "tint",
        "group": null
      }, "transparent", own);
    compare(Qt.color(clear("tinted").fill).a, 0, "tinted");
    compare(Qt.color(clear("split").fill).a, 0, "split's label tint");
    fuzzyCompare(Qt.color(cell("tinted", "active").fill).a, 0.25, 0.01, "a color's tint keeps its strength");
    fuzzyCompare(Qt.color(BarWidgetStyle.faded("#80ff0000", 0.5)).a, 0.25, 0.01, "a part-clear color fades from its own");
    compare(Qt.color(BarWidgetStyle.levelColor({
      "icon": "transparent"
    })).a, 0, "a level in a clear color");
  }

  function test_outline_strokes_in_the_accent() {
    const c = styled("outline");
    same(c.fill, "transparent", "fill");
    same(c.stroke, accent, "stroke");
    same(c.text, accent, "text");
  }

  function test_underline_marks_the_accent_with_bar_text() {
    const c = styled("underline");
    same(c.fill, "transparent", "fill");
    same(c.indicator, accent, "indicator");
    same(c.text, barText, "text");
    same(c.icon, barText, "icon");
  }

  function test_accent_text_colors_only_the_icon() {
    const c = styled("accentText");
    same(c.fill, "transparent", "fill");
    same(c.text, barText, "text");
    same(c.icon, accent, "icon");
  }

  function test_plain_is_bar_text_only() {
    const c = styled("plain");
    same(c.fill, "transparent", "fill");
    same(c.text, barText, "text");
    same(c.icon, barText, "icon");
  }

  function test_override_replaces_the_automatic_text_color() {
    ["filled", "tinted", "outline", "underline", "plain"].forEach(fill => {
      const c = styled(fill, custom);
      same(c.text, custom, fill + " text");
      same(c.icon, custom, fill + " icon");
    });
    // The icon stays the state color: that's the point of the style
    const c = styled("accentText", custom);
    same(c.text, custom, "accentText text");
    same(c.icon, accent, "accentText icon");
  }

  function test_merged_widgets_leave_the_background_to_their_run() {
    const light = "#eeeeee", dark = "#222222";
    const c = styled("filled", null, light);
    same(c.fill, "transparent", "fill");
    same(c.icon, accent, "the icon keeps the state");
    // White bar text can't be read on a light run: black instead
    same(c.text, "#000000", "text on a light run");
    same(styled("filled", null, dark).text, barText, "bar text where it reads");
    // A tint or outline shows the bar through
    same(styled("tinted", null, light).text, barText, "tinted run text");
    same(styled("filled", custom, light).text, custom, "override");
  }

  function cell(fill, state, override = null) {
    return paintCell({
      "fill": fill,
      "barText": barText,
      "override": override,
      "tint": 0.25,
      "group": null
    }, accent, own, state);
  }

  function test_filled_cells_are_boxes_in_their_color() {
    const c = cell("filled", "empty");
    same(c.fill, accent, "fill");
    same(c.content, own, "content reads on the fill");
  }

  function test_boxless_cells_carry_their_color_as_style_says() {
    same(cell("tinted", "active").fill, Qt.alpha(accent, 0.25), "tinted fill");
    same(cell("tinted", "active").content, accent, "tinted content");
    same(cell("outline", "occupied").stroke, accent, "outline stroke");
    same(cell("outline", "occupied").fill, "transparent", "outline fill");
    same(cell("underline", "active").indicator, accent, "underline line");
    same(cell("underline", "active").content, barText, "underline content");
    same(cell("accentText", "active").content, accent, "colored content");
    same(cell("accentText", "active").fill, "transparent", "no fill");
  }

  function test_solid_cells_are_filled_boxes_whatever_the_style() {
    const c = cell("solid", "occupied");
    same(c.fill, accent, "fill");
    same(c.stroke, accent, "the outline matches the fill");
    same(c.indicator, accent, "and the line");
    same(c.content, own, "content reads on the fill");
    same(cell("solid", "empty").content, own, "an empty one's too: it sits on its fill");
  }

  function test_urgent_cells_carry_their_color() {
    same(cell("plain", "urgent").content, accent, "plain: the content takes it, or urgency wouldn't show");
    same(cell("plain", "urgent", custom).content, accent, "even over the bar's text color");
    same(cell("filled", "urgent").fill, accent, "filled: the box, as occupied");
    same(cell("underline", "urgent").indicator, accent, "underline: the line");
    same(cell("tinted", "urgent").content, accent, "not faded as an empty one");
  }

  function test_empty_cells_on_the_bar_fade_the_bar_text() {
    ["tinted", "outline", "underline", "accentText", "plain"].forEach(fill => {
      same(cell(fill, "empty").content, Qt.alpha(barText, 0.4), fill);
    });
  }

  function test_plain_cells_tell_states_apart_by_fading() {
    same(cell("plain", "active").content, barText, "active");
    same(cell("plain", "occupied").content, Qt.alpha(barText, 0.7), "occupied");
    same(cell("plain", "active", custom).content, custom, "override");
  }

  function mergedCell(fill, state, group, hovered = false) {
    return paintCell({
      "fill": fill,
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "hoverFill": true,
      "hovered": hovered,
      "group": group
    }, accent, own, state);
  }

  // In a merged run the run draws the background, as for a widget: a
  // cell's color moves to its content
  function test_merged_cells_carry_their_color_in_their_content() {
    const light = "#eeeeee";
    ["filled", "tinted", "outline"].forEach(fill => {
      const c = mergedCell(fill, "active", light);
      compare(Qt.color(c.fill).a, 0, fill + " no box");
      same(c.stroke, "transparent", fill + " no border");
      same(c.content, accent, fill + " content in its color");
      same(mergedCell(fill, "occupied", light).content, accent, fill + " occupied");
    });
    // An empty one faded, reading on what it sits on: a filled run's color,
    // else the bar through the tint or outline
    same(mergedCell("filled", "empty", light).content, Qt.alpha("#000000", 0.4), "filled empty on a light run");
    same(mergedCell("outline", "empty", light).content, Qt.alpha(barText, 0.4), "outline empty on the bar");
    // Solid boxes stay boxes; split's fill theirs, as a widget that doesn't split
    same(mergedCell("solid", "active", light).fill, accent, "solid");
    same(mergedCell("split", "active", light).fill, accent, "split");
    // Filled on hover in its own part, no border of its own
    const hovered = mergedCell("outline", "active", light, true);
    same(hovered.fill, accent, "hovered fills");
    same(hovered.stroke, "transparent", "hovered draws no border");
    same(mergedCell("outline", "active", light).fill, Qt.alpha(accent, 0), "fades in from its own color");
  }

  function hovering(fill, hovered, hoverFill = true, group = null) {
    return paint({
      "fill": fill,
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "hoverFill": hoverFill,
      "hovered": hovered,
      "group": group
    }, accent, own);
  }

  // "Fill on hover": a tinted or outlined widget under the pointer draws as
  // filled, its text and icon reading on the fill
  function test_hover_fills_tinted_and_outline() {
    ["tinted", "outline"].forEach(fill => {
      const c = hovering(fill, true);
      same(c.fill, accent, fill + " fill");
      same(c.text, own, fill + " text");
      same(c.icon, own, fill + " icon");
    });
    // The outline keeps its stroke under the fill
    same(hovering("outline", true).stroke, accent, "outline stroke");
    same(hovering("tinted", true).stroke, "transparent", "tinted stroke");
  }

  function test_hover_fill_leaves_the_rest_alone() {
    // Not hovered, or the option off: as ever
    same(hovering("tinted", false).fill, Qt.alpha(accent, 0.25), "tinted at rest");
    same(hovering("tinted", true, false).fill, Qt.alpha(accent, 0.25), "option off");
    same(hovering("outline", true, false).text, accent, "outline, option off");
    // Styles with no box to fill, or filled already
    ["filled", "underline", "accentText", "plain"].forEach(fill => {
      const hovered = hovering(fill, true), rest = hovering(fill, false);
      same(hovered.fill, rest.fill, fill + " fill");
      same(hovered.text, rest.text, fill + " text");
    });
  }

  function test_hover_fill_fades_in_from_its_own_color() {
    // At rest an outline's fill is its color cleared, not black cleared
    const rest = hovering("outline", false);
    compare(Qt.color(rest.fill).a, 0, "clear");
    same(Qt.alpha(rest.fill, 1), accent, "its own color");
    same(hovering("outline", false, false).fill, "transparent", "option off");
  }

  function test_hover_fills_a_merged_widgets_own_part() {
    const light = "#eeeeee";
    const c = hovering("tinted", true, true, light);
    same(c.fill, accent, "its own part fills");
    same(c.stroke, "transparent", "no outline of its own in a run");
    same(c.text, own, "text");
    same(c.icon, own, "icon");
    compare(Qt.color(hovering("outline", false, true, light).fill).a, 0, "clear at rest");
  }

  function hoveredCell(fill, state, hovered, hoverFill = true) {
    return paintCell({
      "fill": fill,
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "hoverFill": hoverFill,
      "hovered": hovered,
      "group": null
    }, accent, own, state);
  }

  function test_split_never_fills_on_hover() {
    const c = split("tint", {
      "hoverFill": true,
      "hovered": true
    });
    same(c.fill, Qt.alpha(accent, 0.25), "the label keeps its tint");
    same(c.iconFill, accent, "the icon part its fill");
  }

  function test_hovered_cells_fill() {
    ["tinted", "outline"].forEach(fill => {
      ["active", "occupied", "empty"].forEach(state => {
        const c = hoveredCell(fill, state, true);
        same(c.fill, accent, fill + " " + state + " fill");
        same(c.content, own, fill + " " + state + " content");
        verify(c.showsHover, fill + " " + state + " shows the hover");
      });
    });
    const rest = hoveredCell("tinted", "active", false);
    same(rest.fill, Qt.alpha(accent, 0.25), "at rest");
    verify(!rest.showsHover, "at rest the cell lights itself");
    verify(!hoveredCell("tinted", "active", true, false).showsHover, "option off");
    verify(!hoveredCell("filled", "active", true).showsHover, "filled");
    verify(!cell("outline", "active").showsHover, "no hover given");
  }

  // Solid boxes are filled already: hovered, they keep their look and
  // light in the hover color; an urgent cell fills in its own
  function test_solid_and_urgent_cells_under_fill_on_hover() {
    const solid = hoveredCell("solid", "occupied", true);
    verify(!solid.showsHover, "solid lights itself");
    same(solid.fill, accent, "solid keeps its fill");
    same(solid.stroke, accent, "and its outline");
    const urgent = hoveredCell("outline", "urgent", true);
    same(urgent.fill, accent, "urgent fills in its color");
    verify(urgent.showsHover, "urgent shows the hover");
  }

  function test_level_color_is_the_icon_faded() {
    const c = styled("filled");
    same(BarWidgetStyle.levelColor(c), Qt.alpha(c.icon, 0.35), "level");
  }

  function test_text_by_state_only_off_a_fill() {
    const on = {
      "colorText": true
    };
    verify(BarWidgetStyle.textByState(styled("tinted"), on), "tinted");
    verify(!BarWidgetStyle.textByState(styled("filled"), on), "filled");
    verify(!BarWidgetStyle.textByState(styled("tinted"), {
      "colorText": false
    }), "off");
  }

  // The bar's gradient where a widget sits: a light color, which the
  // bar's white text can't be read on
  readonly property color graded: "#ffff00"

  function gradientStyled(fill, auto, group = null, override = null, options = {}) {
    return paint(Object.assign({
      "fill": fill,
      "barText": barText,
      "override": override,
      "tint": 0.25,
      "group": group,
      "gradient": graded,
      "auto": auto
    }, options), accent, "#ffffff");
  }

  function test_gradient_takes_the_place_of_an_auto_color() {
    const c = gradientStyled("filled", true);
    same(c.fill, graded, "fill");
    // Its own text no longer reads on the fill: black instead
    same(c.text, "#000000", "text reads on the gradient");
    compare(c.gradient.part, "fill");
    compare(c.gradient.alpha, 1);
  }

  function test_a_set_or_state_color_keeps_its_own() {
    const c = gradientStyled("filled", false);
    same(c.fill, accent, "fill");
    compare(c.gradient, null, "no gradient");
    // No gradient on the bar: as before
    compare(styled("filled").gradient, null, "none on the bar");
  }

  function test_gradient_parts_by_style() {
    compare(gradientStyled("tinted", true).gradient.part, "fill", "tinted");
    compare(gradientStyled("tinted", true).gradient.alpha, 0.25, "tinted alpha");
    same(gradientStyled("tinted", true).text, graded, "tinted text");
    compare(gradientStyled("outline", true).gradient.part, "stroke", "outline");
    same(gradientStyled("outline", true).stroke, graded, "outline stroke");
    compare(gradientStyled("underline", true).gradient.part, "indicator", "underline");
    same(gradientStyled("underline", true).text, barText, "underline text");
    // Colored icons: the icon takes the color where it sits, no background
    compare(gradientStyled("accentText", true).gradient, null, "accentText");
    same(gradientStyled("accentText", true).icon, graded, "accentText icon");
  }

  function test_a_merged_run_is_one_gradient_strip() {
    const c = gradientStyled("filled", true, "#222222");
    // The run draws it, its widgets nothing
    compare(c.gradient, null, "the widget's own");
    same(c.fill, "transparent", "fill");
    // Label and Auto icon read on the strip where the widget sits, not on
    // the run's own color
    same(c.text, "#000000", "label");
    same(c.icon, "#000000", "Auto icon");
    // A set color keeps it on its icon
    same(gradientStyled("filled", false, "#222222").icon, accent, "set icon");
    // Through a tint the icon takes the gradient's color
    same(gradientStyled("tinted", true, "#222222").icon, graded, "tinted icon");
  }

  function test_an_auto_cell_takes_the_gradient() {
    const style = {
      "fill": "filled",
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "group": null,
      "gradient": graded,
      "auto": true
    };
    const c = paintCell(style, accent, "#ffffff", "active");
    same(c.fill, graded, "fill");
    same(c.content, "#000000", "content reads on it");
    same(paintCell(Object.assign({}, style, {
      "auto": false
    }), accent, own, "active").fill, accent, "set color");
  }

  function test_an_auto_solid_cell_takes_the_gradient() {
    const c = paintCell({
      "fill": "solid",
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "group": null,
      "gradient": graded,
      "auto": true
    }, accent, "#ffffff", "active");
    same(c.fill, graded, "fill");
    same(c.stroke, graded, "outline");
    same(c.indicator, graded, "line");
    same(c.content, "#000000", "content reads on it");
  }

  // Split under the gradient: its icon part takes its slice (the widget's
  // own, or in a merged run each icon part its own over the run's tint)
  function test_split_icon_part_takes_the_gradient() {
    const split = {
      "splits": true,
      "splitIcon": "joined",
      "labelFill": "tint"
    };
    const c = gradientStyled("split", true, null, null, split);
    compare(c.gradient, {
      "part": "iconFill",
      "alpha": 1
    });
    same(c.iconFill, graded, "icon part");
    same(c.fill, Qt.alpha(graded, 0.25), "label on its tint");
    const merged = gradientStyled("split", true, "#222222", null, split);
    compare(merged.gradient.part, "iconFill", "merged: its own icon part");
    same(merged.text, graded, "merged label in its color, on the run's tint");
    // The run's own background: the labels' tint of the strip
    const run = gradientStyled("split", true, null, null, {
      "run": true
    });
    compare(run.gradient, {
      "part": "fill",
      "alpha": 0.25
    });
    same(run.fill, Qt.alpha(graded, 0.25), "run tint");
    // A filled or tinted run: the strip in full, or its tint
    compare(gradientStyled("filled", true, null, null, {
      "run": true
    }).gradient.alpha, 1, "filled run");
    compare(gradientStyled("tinted", true, null, null, {
      "run": true
    }).gradient.alpha, 0.25, "tinted run");
    // A widget that doesn't split draws filled, its fill the slice
    compare(gradientStyled("split", true).gradient.part, "fill", "unsplit");
  }

  // Fill on hover under the gradient: the fill takes the slice in full
  function test_hover_fills_with_the_gradient() {
    for (const fill of ["tinted", "outline"]) {
      const c = gradientStyled(fill, true, null, null, {
        "hoverFill": true,
        "hovered": true
      });
      compare(c.gradient, {
        "part": "fill",
        "alpha": 1
      }, fill);
      same(c.fill, graded, fill + " fill");
      same(c.text, "#000000", fill + " text reads on it");
    }
    // In a merged run, the hovered widget's own part
    compare(gradientStyled("tinted", true, "#222222", null, {
      "hoverFill": true,
      "hovered": true
    }).gradient.part, "fill", "merged");
    // At rest, as without the option
    compare(gradientStyled("outline", true, null, null, {
      "hoverFill": true
    }).gradient.part, "stroke", "rest");
  }

  function test_readable_on() {
    same(BarWidgetStyle.readableOn("#000000", "#ffffff"), "#ffffff", "contrasting");
    same(BarWidgetStyle.readableOn("#ffffff", "#eeeeee"), "#000000", "too close");
  }

  function split(labelFill, options = {}) {
    return paint(Object.assign({
      "fill": "split",
      "barText": barText,
      "override": null,
      "tint": 0.25,
      "group": null,
      "splits": true,
      "splitIcon": "joined",
      "labelFill": labelFill,
      "labelColor": "#eeeeee"
    }, options), accent, own);
  }

  // In a merged split run, a widget that doesn't split (icon or text
  // alone, one drawing its own content) fills its own box: a tab in the
  // row, as the others' icon parts are
  function test_unsplit_widget_fills_its_box_in_a_merged_split_run() {
    const c = split("tint", {
      "splits": false,
      "group": "#222222"
    });
    same(c.fill, accent, "its box");
    same(c.text, own, "text on it");
    same(c.icon, own, "icon on it");
    // Separate, it draws as filled anyway
    same(split("tint", {
      "splits": false
    }).fill, accent, "separate");
    // Under the gradient its box takes its slice
    compare(gradientStyled("split", true, "#222222").gradient, {
      "part": "fill",
      "alpha": 1
    });
  }

  function test_split_fills_the_icon_part_and_sets_the_label_apart() {
    const tint = split("tint");
    same(tint.iconFill, accent, "icon part");
    same(tint.icon, own, "icon reads on it");
    same(tint.fill, Qt.alpha(accent, 0.25), "label on a tint");
    same(tint.text, accent, "label in the color");
    const color = split("color");
    same(color.fill, "#eeeeee", "label on its color");
    same(color.text, "#000000", "label reads on it");
    same(split("color", {
      "override": custom
    }).text, custom, "override");
    const none = split("none");
    same(none.fill, "transparent", "label on the bar");
    same(none.text, accent, "label in the color");
  }

  function test_split_badge_leaves_the_label_on_the_bar() {
    const c = split("color", {
      "splitIcon": "badge"
    });
    same(c.iconFill, accent, "badge");
    same(c.fill, "transparent", "no label background");
    same(c.text, accent, "label in the color");
  }

  function test_split_without_parts_is_filled() {
    const c = split("tint", {
      "splits": false
    });
    same(c.fill, accent, "fill");
    same(c.text, own, "text");
    same(c.iconFill, "transparent", "no icon part");
    same(styled("filled").iconFill, "transparent", "other styles have none");
  }

  function test_split_merged_keeps_the_icon_part_on_the_run() {
    const light = "#eeeeee";
    const c = split("tint", {
      "group": light
    });
    same(c.fill, "transparent", "the run draws the label's");
    same(c.iconFill, accent, "icon part");
    same(c.icon, own, "icon reads on it");
    same(c.text, "#000000", "label reads on the run");
    // A widget with no parts fills its own box on the run
    // (test_unsplit_widget_fills_its_box_in_a_merged_split_run)
    same(split("tint", {
      "group": light,
      "splits": false
    }).fill, accent, "its own box");
  }

  function test_split_cells_are_filled() {
    const c = cell("split", "empty");
    same(c.fill, accent, "fill");
    same(c.content, own, "content");
  }

  // Cells as segments of a merged run (Workspaces with its Background
  // off): the run draws the box, the content takes the state's color
  function test_cells_in_a_merged_run_leave_the_box_to_it() {
    const groupCell = (fill, state, extra) => paintCell(Object.assign({
        "fill": fill,
        "barText": barText,
        "override": null,
        "tint": 0.25,
        "group": "#000000"
      }, extra ?? {}), accent, own, state);
    ["filled", "tinted", "outline"].forEach(fill => {
      const c = groupCell(fill, "active");
      same(c.fill, "transparent", fill + ": no fill");
      same(c.stroke, "transparent", fill + ": no stroke");
      same(c.content, accent, fill + ": its color in the content");
    });
    same(groupCell("outline", "occupied").content, accent, "occupied too");
    same(groupCell("tinted", "empty").content, Qt.alpha(barText, 0.4), "empty: faded");
    same(groupCell("filled", "empty", {
      "group": "#ffffff"
    }).content, Qt.alpha("#000000", 0.4), "faded, reading on a filled run");
    same(groupCell("solid", "active").fill, accent, "a solid box stays filled");
    same(groupCell("split", "active").fill, accent, "split's fill too");
    same(groupCell("outline", "active", {
      "hoverFill": true,
      "hovered": true
    }).fill, accent, "filled on hover, its own part");
  }

  // What of a cell's box takes the bar's gradient, under an Auto color
  function test_cell_gradient_parts() {
    const part = (fill, extra) => paintCell(Object.assign({
        "fill": fill,
        "barText": barText,
        "override": null,
        "tint": 0.25,
        "group": null,
        "gradient": graded,
        "auto": true
      }, extra ?? {}), accent, own, "active").gradient;
    compare(part("filled"), {
      "part": "fill",
      "alpha": 1
    });
    compare(part("tinted"), {
      "part": "fill",
      "alpha": 0.25
    });
    compare(part("outline").part, "stroke");
    compare(part("solid").part, "fill");
    compare(part("plain"), null);
    compare(part("outline", {
      "group": "#000000"
    }), null, "content only in a merged run");
    compare(part("filled", {
      "auto": false
    }), null, "a set color: none");
  }

  // The look's colors resolved once
  function test_palette() {
    const names = {
      "accent": "#ff0000",
      "base03": "#333333",
      "red": "#aa0000",
      "fg": "#ffffff"
    };
    const resolve = name => Qt.color(names[name] ?? "#000000");
    const look = {
      "textColor": "",
      "split": null,
      "group": {
        "color": "base03",
        "strokeColor": "accent"
      },
      "gradient": ["accent", "red"]
    };
    const p = BarWidgetStyle.palette(look, resolve, "#ffffff");
    compare(p.override, null, "Auto text");
    compare(p.labelColor, null, "no split");
    same(p.group, "#333333", "group");
    same(p.groupStroke, "#ff0000", "group stroke");
    same(p.gradientStops[1], "#aa0000", "stops");
    const own = BarWidgetStyle.palette(Object.assign({}, look, {
      "textColor": "fg",
      "split": {
        "labelColor": "red"
      },
      "gradient": null
    }), resolve, "#ffffff");
    same(own.override, "#ffffff", "set text color");
    same(own.labelColor, "#aa0000", "split's label color");
    compare(own.gradientStops, null, "no gradient");
  }

  // A spot along the bar stands for the gradient's color there
  function test_state() {
    const palette = {
      "gradientStops": ["#000000", "#ffffff"]
    };
    const s = BarWidgetStyle.state(palette, {
      "spot": 0.5,
      "auto": true
    });
    same(s.gradient, Qt.rgba(0.5, 0.5, 0.5, 1), "the gradient at its spot");
    compare([s.auto, s.splits, s.hovered, s.run, s.group, s.solid], [true, false, false, false, false, false]);
    compare(BarWidgetStyle.state(palette, {}).gradient, null, "no spot");
    compare(BarWidgetStyle.state({
      "gradientStops": null
    }, {
      "spot": 0.5
    }).gradient, null, "no gradient");
  }

  // A merged run's own background: its group color, an outline run's line
  // its stroke color
  function test_run_colors() {
    const look = lookOf({
      "fill": "filled"
    });
    const palette = {
      "barText": barText,
      "override": null,
      "labelColor": null,
      "group": "#333333",
      "groupStroke": "#ff0000",
      "gradientStops": null
    };
    same(BarWidgetStyle.runColors(look, palette, -1).fill, "#333333", "filled run");
    const outline = BarWidgetStyle.runColors(lookOf({
      "fill": "outline"
    }), palette, -1);
    same(outline.stroke, "#ff0000", "outline run's line");
    compare(outline.gradient, null, "no gradient");
  }
}
