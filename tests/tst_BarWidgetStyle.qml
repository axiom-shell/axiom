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

  function styled(fill, override = null, group = null) {
    return BarWidgetStyle.colors({
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
    return BarWidgetStyle.cell({
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

  function hovering(fill, hovered, hoverFill = true, group = null) {
    return BarWidgetStyle.colors({
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
    verify(!BarWidgetStyle.fillsOnHover({
      "fill": "filled",
      "hoverFill": true
    }), "filled");
    verify(BarWidgetStyle.fillsOnHover({
      "fill": "outline",
      "hoverFill": true
    }), "outline");
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
    return BarWidgetStyle.cell({
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
    return BarWidgetStyle.colors(Object.assign({
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

  function test_gradient_at_spreads_the_stops_evenly() {
    same(BarWidgetStyle.gradientAt(["#000000", "#ffffff"], 0), "#000000", "start");
    same(BarWidgetStyle.gradientAt(["#000000", "#ffffff"], 1), "#ffffff", "end");
    same(BarWidgetStyle.gradientAt(["#ff0000", "#00ff00", "#0000ff"], 0.5), "#00ff00", "via at the middle");
    same(BarWidgetStyle.gradientAt(["#ff0000", "#00ff00", "#0000ff"], 0.25), Qt.rgba(0.5, 0.5, 0, 1), "a quarter");
    same(BarWidgetStyle.gradientAt(["#000000", "#ffffff"], 2), "#ffffff", "clamped");
  }

  function test_gradient_slice_is_the_bars_between_its_ends() {
    const two = BarWidgetStyle.gradientSlice(["#000000", "#ffffff"], 0.25, 0.75, 1);
    compare(two.map(s => s.position), [0, 0.5, 1]);
    same(two[0].color, Qt.rgba(0.25, 0.25, 0.25, 1), "start");
    same(two[1].color, Qt.rgba(0.5, 0.5, 0.5, 1), "middle");
    same(two[2].color, Qt.rgba(0.75, 0.75, 0.75, 1), "end");
    // The via stop inside it is a stop of the slice
    const three = BarWidgetStyle.gradientSlice(["#ff0000", "#00ff00", "#0000ff"], 0.4, 0.8, 1);
    fuzzyCompare(three[1].position, 0.25, 1e-9);
    same(three[1].color, "#00ff00", "via");
    // Faded for a tint
    compare(BarWidgetStyle.gradientSlice(["#000000", "#ffffff"], 0, 1, 0.25)[2].color.a, 0.25);
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
    const c = BarWidgetStyle.cell(style, accent, "#ffffff", "active");
    same(c.fill, graded, "fill");
    same(c.content, "#000000", "content reads on it");
    same(BarWidgetStyle.cell(Object.assign({}, style, {
      "auto": false
    }), accent, own, "active").fill, accent, "set color");
  }

  function test_an_auto_solid_cell_takes_the_gradient() {
    const c = BarWidgetStyle.cell({
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
    return BarWidgetStyle.colors(Object.assign({
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

  function test_opaque_fills() {
    verify(BarWidgetStyle.opaque("filled", "joined", "tint"), "filled");
    verify(!BarWidgetStyle.opaque("tinted", "joined", "color"), "tinted");
    verify(BarWidgetStyle.opaque("split", "joined", "color"), "split on a color");
    verify(!BarWidgetStyle.opaque("split", "joined", "tint"), "split on a tint");
    verify(!BarWidgetStyle.opaque("split", "badge", "color"), "badge");
  }

  function look(style, splitIcon, shape, grouping) {
    return {
      "widgetStyle": style,
      "splitIcon": splitIcon,
      "widgetShape": shape,
      "widgetGrouping": grouping
    };
  }

  function test_badge_and_tab_have_no_powerline() {
    compare(BarWidgetStyle.grouping(look("split", "badge", "rounded", "powerline")), "separate");
    compare(BarWidgetStyle.grouping(look("split", "badge", "rounded", "merged")), "merged");
    compare(BarWidgetStyle.grouping(look("split", "joined", "rounded", "powerline")), "powerline");
    compare(BarWidgetStyle.grouping(look("filled", "badge", "rounded", "powerline")), "powerline");
    compare(BarWidgetStyle.grouping(look("filled", "joined", "tab", "powerline")), "separate");
    compare(BarWidgetStyle.grouping(look("split", "joined", "tab", "merged")), "merged");
  }

  function test_auto_contrast() {
    compare(BarWidgetStyle.autoContrast("filled", "separate", "joined", "tint"), {
      "onRun": false,
      "minContrast": 1.3
    });
    compare(BarWidgetStyle.autoContrast("filled", "merged", "joined", "tint"), {
      "onRun": true,
      "minContrast": 3
    });
    compare(BarWidgetStyle.autoContrast("tinted", "merged", "joined", "tint"), {
      "onRun": false,
      "minContrast": 3
    });
    // An outline run has no background: its widgets sit on the bar
    compare(BarWidgetStyle.autoContrast("outline", "merged", "joined", "tint"), {
      "onRun": false,
      "minContrast": 3
    });
    // Split's color is the label's text too, unless the label has its own
    compare(BarWidgetStyle.autoContrast("split", "separate", "joined", "tint").minContrast, 3);
    compare(BarWidgetStyle.autoContrast("split", "separate", "badge", "color").minContrast, 3);
    compare(BarWidgetStyle.autoContrast("split", "powerline", "joined", "color").minContrast, 1.3);
    compare(BarWidgetStyle.autoContrast("split", "merged", "joined", "tint"), {
      "onRun": true,
      "minContrast": 1.3
    });
  }
}
