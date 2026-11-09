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
    // A widget with no parts: as a filled merged one
    same(split("tint", {
      "group": light,
      "splits": false
    }).icon, accent, "the icon keeps the state");
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
