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
}
