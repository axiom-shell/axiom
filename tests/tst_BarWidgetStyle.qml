import QtQuick
import QtTest
import qs.components.methods

// What a widget or a Workspaces cell paints each part in (BarWidgetStyle),
// for a look BarLook.resolve makes of a bar's BarStyle keys
TestCase {
  id: root

  name: "BarWidgetStyle"

  RepoFiles {
    id: files
  }

  property var schema: null

  function initTestCase() {
    root.schema = files.json("qml/config/json/config.schema.json");
  }

  readonly property color accent: "#ff8080"
  readonly property color own: "#000000"
  readonly property color barText: "#ffffff"
  readonly property color custom: "#00ff00"

  function same(actual, expected, message) {
    verify(Qt.colorEqual(actual, expected), `${message}: ${actual} != ${expected}`);
  }

  // Equal to within 8-bit rounding (a composite is computed in floats)
  function close(actual, expected, message) {
    const a = Qt.color(actual), e = Qt.color(expected);
    verify(Math.abs(a.r - e.r) < 0.01 && Math.abs(a.g - e.g) < 0.01 && Math.abs(a.b - e.b) < 0.01, `${message}: ${actual} != ${expected}`);
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

  // A bar's look from its own BarStyle keys (`bar`) over the defaults, its
  // tint 25% unless given
  function look(bar) {
    return BarLook.resolve(root.section(), Object.assign({
      "tintOpacity": 25
    }, bar), null);
  }

  // The bar's colors resolved (BarWidgetStyle.palette's shape), `given`'s
  // over white text on black, no set text color, group or gradient
  function palette(given) {
    return Object.assign({
      "barText": root.barText,
      "background": "#000000",
      "override": null,
      "labelColor": null,
      "group": null,
      "groupStroke": null,
      "gradientStops": null
    }, given ?? {});
  }

  // The widget's state (BarWidgetStyle.state's shape), `given`'s over a
  // widget alone at rest, no gradient
  function state(given) {
    return Object.assign({
      "gradient": null,
      "splits": false,
      "hovered": false,
      "auto": false,
      "run": false,
      "group": false,
      "solid": false
    }, given ?? {});
  }

  // A widget's colors on a bar of `bar`'s keys, in `given` state, on
  // `colors` (a palette's fields), in `color`, `ownColor` reading on it
  function paint(bar, given, colors, color, ownColor) {
    return BarWidgetStyle.colors(root.look(bar), root.palette(colors), root.state(given), color ?? root.accent, ownColor ?? root.own);
  }

  // A cell's, as `cellState` ("active", "occupied", "urgent", "empty")
  function paintCell(bar, given, colors, cellState, color, ownColor) {
    return BarWidgetStyle.cell(root.look(bar), root.palette(colors), root.state(given), color ?? root.accent, ownColor ?? root.own, cellState);
  }

  // A widget on a bar of `style`, with its text color set (`override`),
  // or in a merged run of `group`'s color
  function styled(style, override = null, group = null) {
    return root.paint({
      "widgetStyle": style,
      "widgetGrouping": group ? "merged" : "separate"
    }, {
      "group": group !== null
    }, {
      "override": override,
      "group": group
    });
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
    const clear = style => root.paint({
        "widgetStyle": style,
        "splitIcon": "joined",
        "splitLabelFill": "tint"
      }, {
        "splits": true
      }, {}, "transparent");
    compare(Qt.color(clear("tinted").fill).a, 0, "tinted");
    compare(Qt.color(clear("split").fill).a, 0, "split's label tint");
    fuzzyCompare(Qt.color(cell("tinted", "active").fill).a, 0.25, 0.01, "a color's tint keeps its strength");
    fuzzyCompare(Qt.color(BarWidgetStyle.faded("#80ff0000", 0.5)).a, 0.25, 0.01, "a part-clear color fades from its own");
    compare(Qt.color(clear("tinted").level).a, 0, "a level in a clear color");
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
    ["filled", "tinted", "outline", "underline", "plain"].forEach(style => {
      const c = styled(style, custom);
      same(c.text, custom, style + " text");
      same(c.icon, custom, style + " icon");
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
    // (nudged to read on the light run)
    same(c.icon, BarWidgetStyle.nudged([light], accent, 3), "the icon keeps the state");
    // White bar text can't be read on a light run: black instead
    same(c.text, "#000000", "text on a light run");
    same(styled("filled", null, dark).text, barText, "bar text where it reads");
    // A tint or outline shows the bar through
    same(styled("tinted", null, light).text, barText, "tinted run text");
    same(styled("filled", custom, light).text, custom, "override");
  }

  // A cell on a bar of `style` as `cellState`, with the bar's text color
  // set (`override`); `given`: its state's other fields (a solid box,
  // `solid`)
  function cell(style, cellState, override = null, given = {}) {
    return root.paintCell({
      "widgetStyle": style
    }, given, {
      "override": override
    }, cellState);
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

  // A Workspaces cell's solid box (its state's `solid`)
  readonly property var solid: ({
      "solid": true
    })

  function test_solid_cells_are_filled_boxes_whatever_the_style() {
    const c = cell("filled", "occupied", null, solid);
    same(c.fill, accent, "fill");
    same(c.stroke, accent, "the outline matches the fill");
    same(c.indicator, accent, "and the line");
    same(c.content, own, "content reads on the fill");
    same(cell("filled", "empty", null, solid).content, own, "an empty one's too: it sits on its fill");
  }

  function test_urgent_cells_carry_their_color() {
    same(cell("plain", "urgent").content, accent, "plain: the content takes it, or urgency wouldn't show");
    same(cell("plain", "urgent", custom).content, accent, "even over the bar's text color");
    same(cell("filled", "urgent").fill, accent, "filled: the box, as occupied");
    same(cell("underline", "urgent").indicator, accent, "underline: the line");
    same(cell("tinted", "urgent").content, accent, "not faded as an empty one");
  }

  function test_empty_cells_on_the_bar_fade_the_bar_text() {
    ["tinted", "outline", "underline", "accentText", "plain"].forEach(style => {
      same(cell(style, "empty").content, Qt.alpha(barText, 0.4), style);
    });
  }

  function test_plain_cells_tell_states_apart_by_fading() {
    same(cell("plain", "active").content, barText, "active");
    same(cell("plain", "occupied").content, Qt.alpha(barText, 0.7), "occupied");
    same(cell("plain", "active", custom).content, custom, "override");
  }

  // A cell in a merged run of `group`'s color on a bar of `style` with
  // Fill on hover, `given` its state's other fields
  function mergedCell(style, cellState, group, given = {}) {
    return root.paintCell({
      "widgetStyle": style,
      "widgetGrouping": "merged",
      "hoverFill": true
    }, Object.assign({
      "group": true
    }, given), {
      "group": group
    }, cellState);
  }

  // In a merged run the run draws the background, as for a widget: a
  // cell's color moves to its content
  function test_merged_cells_carry_their_color_in_their_content() {
    const light = "#eeeeee";
    ["filled", "tinted", "outline"].forEach(style => {
      const c = mergedCell(style, "active", light);
      compare(Qt.color(c.fill).a, 0, style + " no box");
      same(c.stroke, "transparent", style + " no border");
      // Read where it sits: on a filled run's color, else on the bar
      const read = style === "filled" ? BarWidgetStyle.nudged([light], accent, 4.5) : accent;
      same(c.content, read, style + " content in its color");
      same(mergedCell(style, "occupied", light).content, read, style + " occupied");
    });
    // An empty one faded, reading on what it sits on: a filled run's color,
    // else the bar through the tint or outline
    same(mergedCell("filled", "empty", light).content, Qt.alpha("#000000", 0.4), "filled empty on a light run");
    same(mergedCell("outline", "empty", light).content, Qt.alpha(barText, 0.4), "outline empty on the bar");
    // Solid boxes stay boxes; split's fill theirs, as a widget that doesn't split
    same(mergedCell("filled", "active", light, solid).fill, accent, "solid");
    same(mergedCell("split", "active", light).fill, accent, "split");
    // Filled on hover in its own part, no border of its own
    const hovered = mergedCell("outline", "active", light, {
      "hovered": true
    });
    same(hovered.fill, accent, "hovered fills");
    same(hovered.stroke, "transparent", "hovered draws no border");
    same(mergedCell("outline", "active", light).fill, Qt.alpha(accent, 0), "fades in from its own color");
  }

  // A widget on a bar of `style` with Fill on hover on or off, hovered or
  // not, alone or in a merged run of `group`'s color
  function hovering(style, hovered, hoverFill = true, group = null) {
    return root.paint({
      "widgetStyle": style,
      "widgetGrouping": group ? "merged" : "separate",
      "hoverFill": hoverFill
    }, {
      "hovered": hovered,
      "group": group !== null
    }, {
      "group": group
    });
  }

  // "Fill on hover": a tinted or outlined widget under the pointer draws as
  // filled, its text and icon reading on the fill
  function test_hover_fills_tinted_and_outline() {
    ["tinted", "outline"].forEach(style => {
      const c = hovering(style, true);
      same(c.fill, accent, style + " fill");
      same(c.text, own, style + " text");
      same(c.icon, own, style + " icon");
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
    ["filled", "underline", "accentText", "plain"].forEach(style => {
      const hovered = hovering(style, true), rest = hovering(style, false);
      same(hovered.fill, rest.fill, style + " fill");
      same(hovered.text, rest.text, style + " text");
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

  // A cell on a bar of `style` with Fill on hover on or off, hovered or
  // not; `given` its state's other fields
  function hoveredCell(style, cellState, hovered, hoverFill = true, given = {}) {
    return root.paintCell({
      "widgetStyle": style,
      "hoverFill": hoverFill
    }, Object.assign({
      "hovered": hovered
    }, given), {}, cellState);
  }

  function test_split_never_fills_on_hover() {
    const c = split("tint", {
      "hoverFill": true
    }, {
      "hovered": true
    });
    same(c.fill, Qt.alpha(accent, 0.25), "the label keeps its tint");
    same(c.iconFill, accent, "the icon part its fill");
  }

  function test_hovered_cells_fill() {
    ["tinted", "outline"].forEach(style => {
      ["active", "occupied", "empty"].forEach(cellState => {
        const c = hoveredCell(style, cellState, true);
        same(c.fill, accent, style + " " + cellState + " fill");
        same(c.content, own, style + " " + cellState + " content");
        verify(c.showsHover, style + " " + cellState + " shows the hover");
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
    const box = hoveredCell("filled", "occupied", true, true, solid);
    verify(!box.showsHover, "solid lights itself");
    same(box.fill, accent, "solid keeps its fill");
    same(box.stroke, accent, "and its outline");
    const urgent = hoveredCell("outline", "urgent", true);
    same(urgent.fill, accent, "urgent fills in its color");
    verify(urgent.showsHover, "urgent shows the hover");
  }

  function test_level_color_is_the_icon_faded() {
    const c = styled("filled");
    same(c.level, Qt.alpha(c.icon, 0.35), "level");
  }

  function test_state_content_by_backdrop() {
    const on = {
      "colorText": true
    };
    const state = "#ff8080";
    // Off a fill both take the state's color; on one, the colors' own
    for (const style of ["tinted", "outline", "underline", "accentText", "plain"]) {
      const c = styled(style);
      const content = BarWidgetStyle.stateContent(c, on, state, true);
      same(content.text, BarWidgetStyle.nudged(c.textBack, state, 4.5), style + " text");
      same(content.icon, BarWidgetStyle.nudged(c.iconBack, state, 3), style + " icon");
    }
    const filled = styled("filled");
    const both = BarWidgetStyle.stateContent(filled, on, state, true);
    same(both.text, filled.text, "filled text");
    same(both.icon, filled.icon, "filled icon");
    // No colorText, or no state: the colors'
    const tinted = styled("tinted");
    same(BarWidgetStyle.stateContent(tinted, {
      "colorText": false
    }, state, true).text, tinted.text, "off");
    same(BarWidgetStyle.stateContent(tinted, on, state, false).icon, tinted.icon, "no state");
    const run = styled("outline", null, "#222222");
    same(BarWidgetStyle.stateContent(run, on, state, true).text, BarWidgetStyle.nudged(run.textBack, state, 4.5), "an outline run's text");
    same(BarWidgetStyle.stateContent(styled("filled", null, "#222222"), on, state, true).text, styled("filled", null, "#222222").text, "a filled run's fill counts");
  }

  // The bug: split's icon part is filled in the state's color, so its icon
  // stays the colors' while the label takes the state's
  function test_state_content_on_split() {
    const bar = {
      "widgetStyle": "split",
      "splitIcon": "joined",
      "splitLabelFill": "tint"
    };
    const c = root.paint(bar, {
      "splits": true
    });
    const content = BarWidgetStyle.stateContent(c, {
      "colorText": true
    }, "#ff8080", true);
    same(content.icon, c.icon, "icon stays");
    same(content.text, BarWidgetStyle.nudged(c.textBack, "#ff8080", 4.5), "text takes the state");
    // The bar's text color of its own doesn't stop the state's color
    const set = root.paint(bar, {
      "splits": true
    }, {
      "override": "#123456"
    });
    same(BarWidgetStyle.stateContent(set, {
      "colorText": true
    }, "#ff8080", true).text, BarWidgetStyle.nudged(set.textBack, "#ff8080", 4.5), "override");
  }

  // Whether a widget's text sits on a fill it must read on (textOnFill):
  // every style, merged or not, split's label fills, and Fill on hover.
  // Each row: [tag, the bar's keys, the widget's state, on a fill]; a
  // state with `group` is in a merged run of #222222.
  function test_text_on_fill_data() {
    const merged = {
      "widgetGrouping": "merged"
    };
    const inRun = {
      "group": true
    };
    const graded = {
      "gradient": "#00ff00",
      "auto": true
    };
    const splits = {
      "splits": true
    };
    return [["filled",
        {
          "widgetStyle": "filled"
        },
        {},
        true], ["tinted",
        {
          "widgetStyle": "tinted"
        },
        {},
        false], ["outline",
        {
          "widgetStyle": "outline"
        },
        {},
        false], ["underline",
        {
          "widgetStyle": "underline"
        },
        {},
        false], ["accentText",
        {
          "widgetStyle": "accentText"
        },
        {},
        false], ["plain",
        {
          "widgetStyle": "plain"
        },
        {},
        false], ["merged filled", Object.assign({
          "widgetStyle": "filled"
        }, merged), inRun, true], ["merged filled, gradient", Object.assign({
          "widgetStyle": "filled"
        }, merged), Object.assign({}, inRun, graded), true], ["merged tinted", Object.assign({
          "widgetStyle": "tinted"
        }, merged), inRun, false], ["merged outline", Object.assign({
          "widgetStyle": "outline"
        }, merged), inRun, false], ["merged split", Object.assign({
          "widgetStyle": "split"
        }, merged), Object.assign({}, inRun, splits), true], ["merged split, gradient: the run is the labels' tint", Object.assign({
          "widgetStyle": "split"
        }, merged), Object.assign({}, inRun, splits, graded), false], ["merged split, a widget that doesn't split", Object.assign({
          "widgetStyle": "split"
        }, merged), inRun, true], ["split, label on its own color",
        {
          "widgetStyle": "split",
          "splitLabelFill": "color"
        },
        splits, true], ["split, label on a tint",
        {
          "widgetStyle": "split",
          "splitLabelFill": "tint"
        },
        splits, false], ["split, label on the bar",
        {
          "widgetStyle": "split",
          "splitLabelFill": "none"
        },
        splits, false], ["split badge",
        {
          "widgetStyle": "split",
          "splitIcon": "badge",
          "splitLabelFill": "color"
        },
        splits, false], ["split, a widget that doesn't split",
        {
          "widgetStyle": "split"
        },
        {},
        true], ["tinted, hovered with Fill on hover",
        {
          "widgetStyle": "tinted",
          "hoverFill": true
        },
        {
          "hovered": true
        },
        true], ["outline, hovered with Fill on hover",
        {
          "widgetStyle": "outline",
          "hoverFill": true
        },
        {
          "hovered": true
        },
        true], ["outline, at rest with Fill on hover",
        {
          "widgetStyle": "outline",
          "hoverFill": true
        },
        {},
        false], ["merged tinted, hovered with Fill on hover", Object.assign({
          "widgetStyle": "tinted",
          "hoverFill": true
        }, merged), Object.assign({
          "hovered": true
        }, inRun), true]].map(row => ({
          "tag": row[0],
          "bar": row[1],
          "given": row[2],
          "onFill": row[3]
        }));
  }
  function test_text_on_fill(data) {
    const c = root.paint(data.bar, data.given, {
      "group": data.given.group ? "#222222" : null,
      "labelColor": "#eeeeee"
    });
    compare(c.textOnFill, data.onFill, "textOnFill");
    same(BarWidgetStyle.stateContent(c, {
      "colorText": true
    }, "#ff8080", true).text, data.onFill ? c.text : BarWidgetStyle.nudged(c.textBack, "#ff8080", 4.5), "stateContent");
  }

  // The bar's gradient where a widget sits: a light color, which the
  // bar's white text can't be read on
  readonly property color graded: "#ffff00"

  // A widget on a bar of `style` with the gradient (its color here
  // `graded`), its own color Auto or not, alone or in a merged run of
  // `group`'s color; `bar` and `given` the look's other keys and its
  // state's other fields. Its own text white.
  function gradientStyled(style, auto, group = null, bar = {}, given = {}) {
    return root.paint(Object.assign({
      "widgetStyle": style,
      "widgetGrouping": group ? "merged" : "separate"
    }, bar), Object.assign({
      "gradient": graded,
      "auto": auto,
      "group": group !== null
    }, given), {
      "group": group
    }, accent, "#ffffff");
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
    same(gradientStyled("filled", false, "#222222").icon, BarWidgetStyle.nudged([graded], accent, 3), "set icon, nudged to read on the strip");
    // Through a tint the icon takes the gradient's color
    same(gradientStyled("tinted", true, "#222222").icon, graded, "tinted icon");
  }

  // A cell on a filled bar under the gradient (its color here `graded`),
  // its own color Auto or not; `given` its state's other fields
  function gradientCell(auto, ownColor, given = {}) {
    return root.paintCell({
      "widgetStyle": "filled"
    }, Object.assign({
      "gradient": graded,
      "auto": auto
    }, given), {}, "active", accent, ownColor);
  }

  function test_an_auto_cell_takes_the_gradient() {
    const c = gradientCell(true, "#ffffff");
    same(c.fill, graded, "fill");
    same(c.content, "#000000", "content reads on it");
    same(gradientCell(false, own).fill, accent, "set color");
  }

  function test_an_auto_solid_cell_takes_the_gradient() {
    const c = gradientCell(true, "#ffffff", solid);
    same(c.fill, graded, "fill");
    same(c.stroke, graded, "outline");
    same(c.indicator, graded, "line");
    same(c.content, "#000000", "content reads on it");
  }

  // Split under the gradient: its icon part takes its slice (the widget's
  // own, or in a merged run each icon part its own over the run's tint)
  function test_split_icon_part_takes_the_gradient() {
    const joined = {
      "splitIcon": "joined",
      "splitLabelFill": "tint"
    };
    const splits = {
      "splits": true
    };
    const c = gradientStyled("split", true, null, joined, splits);
    compare(c.gradient, {
      "part": "iconFill",
      "alpha": 1
    });
    same(c.iconFill, graded, "icon part");
    same(c.fill, Qt.alpha(graded, 0.25), "label on its tint");
    const merged = gradientStyled("split", true, "#222222", joined, splits);
    compare(merged.gradient.part, "iconFill", "merged: its own icon part");
    same(merged.text, graded, "merged label in its color, on the run's tint");
    // The run's own background: the labels' tint of the strip
    const ofRun = {
      "run": true
    };
    const run = gradientStyled("split", true, null, {}, ofRun);
    compare(run.gradient, {
      "part": "fill",
      "alpha": 0.25
    });
    same(run.fill, Qt.alpha(graded, 0.25), "run tint");
    // A filled or tinted run: the strip in full, or its tint
    compare(gradientStyled("filled", true, null, {}, ofRun).gradient.alpha, 1, "filled run");
    compare(gradientStyled("tinted", true, null, {}, ofRun).gradient.alpha, 0.25, "tinted run");
    // A widget that doesn't split draws filled, its fill the slice
    compare(gradientStyled("split", true).gradient.part, "fill", "unsplit");
  }

  // Fill on hover under the gradient: the fill takes the slice in full
  function test_hover_fills_with_the_gradient() {
    const option = {
      "hoverFill": true
    };
    const hovered = {
      "hovered": true
    };
    for (const style of ["tinted", "outline"]) {
      const c = gradientStyled(style, true, null, option, hovered);
      compare(c.gradient, {
        "part": "fill",
        "alpha": 1
      }, style);
      same(c.fill, graded, style + " fill");
      same(c.text, "#000000", style + " text reads on it");
    }
    // In a merged run, the hovered widget's own part
    compare(gradientStyled("tinted", true, "#222222", option, hovered).gradient.part, "fill", "merged");
    // At rest, as without the option
    compare(gradientStyled("outline", true, null, option).gradient.part, "stroke", "rest");
  }

  function test_readable_on() {
    same(BarWidgetStyle.readableOn("#000000", "#ffffff"), "#ffffff", "contrasting");
    same(BarWidgetStyle.readableOn("#ffffff", "#eeeeee"), "#000000", "too close");
    // By contrast, not a luma split: gruvbox's dark text on its red reads
    // at about 4.3, black at 6.1 (white, which a luma split picked, 3.4)
    same(BarWidgetStyle.readableOn("#fb4934", "#282828"), "#000000", "black beats the dark text");
    // Kept where it reads (4.5), though both are light by luma
    same(BarWidgetStyle.readableOn("#3060c0", "#ffffff"), "#ffffff", "white on a mid blue");
    // An alternate that reads better is taken
    same(BarWidgetStyle.readableOn("#808080", "#909090", ["#000000"]), "#000000", "an alternate");
    same(BarWidgetStyle.readableOn("#fb4934", "#282828", ["#101010"]), "#000000", "black still beats an alternate near it");
    same(BarWidgetStyle.readableOn("#777777", "#ffffff", ["#000000"]), "#000000", "the alternate with the most contrast");
    // Never less contrast than the luma split's choice (its two options
    // are among the candidates)
    for (const bg of ["#fb4934", "#458588", "#b8bb26", "#d3869b", "#665c54", "#fabd2f"]) {
      const old = Utils.isColorDark(bg) !== Utils.isColorDark("#282828") ? "#282828" : Utils.getContrastColor(bg);
      verify(Utils.contrast(bg, BarWidgetStyle.readableOn(bg, "#282828", ["#ebdbb2"])) >= Utils.contrast(bg, old) - 1e-9, bg);
    }
  }

  // Text and icons on a fill the widget paints read on it: filled, Fill on
  // hover, split's icon part, solid and filled cells. Not on the bar:
  // tinted, outline and the rest keep theirs.
  function test_text_on_a_fill_reads() {
    const red = "#fb4934", dark = "#282828";
    const onDark = {
      "background": dark
    };
    const widget = style => root.paint({
        "widgetStyle": style,
        "hoverFill": true
      }, {
        "splits": true,
        "hovered": style === "tinted"
      }, onDark, red, dark);
    same(widget("filled").text, "#000000", "filled");
    same(widget("filled").icon, "#000000", "filled icon");
    same(widget("tinted").text, "#000000", "filled on hover");
    same(widget("split").icon, "#000000", "split's icon part");
    same(widget("outline").text, BarWidgetStyle.nudged([dark], red, 4.5), "outline keeps its color, nudged to read on the bar");
    const cellOf = (style, cellState, given) => root.paintCell({
        "widgetStyle": style
      }, given ?? {}, onDark, cellState, red, dark);
    same(cellOf("filled", "active").content, "#000000", "a filled cell");
    same(cellOf("filled", "occupied", solid).content, "#000000", "a solid cell");
    // (nudged to read on its tint)
    same(cellOf("tinted", "active").content, BarWidgetStyle.nudged([BarWidgetStyle.over(BarWidgetStyle.faded(red, 0.25), "#282828")], red, 4.5), "a tinted cell's content is its color");
    // A clear fill is no fill: the text is on the bar
    same(root.paint({
      "widgetStyle": "filled"
    }, {}, onDark, "transparent", dark).text, BarWidgetStyle.nudged([dark], dark, 4.5), "a clear fill: the text is on the bar, nudged to read there");
  }

  // A widget on a split bar whose label sits on `labelFill`, splitting
  // into its parts; `bar` and `given` the look's other keys and its
  // state's other fields, `colors` the palette's (its label color #eeeeee)
  function split(labelFill, bar = {}, given = {}, colors = {}) {
    return root.paint(Object.assign({
      "widgetStyle": "split",
      "splitIcon": "joined",
      "splitLabelFill": labelFill
    }, bar), Object.assign({
      "splits": true
    }, given), Object.assign({
      "labelColor": "#eeeeee"
    }, colors));
  }

  // A merged run of `color` as split()'s [bar, given, colors]: the look's
  // grouping, the widget's place in it (`given`'s too) and the run's color
  function splitRun(color, given = {}) {
    return [
      {
        "widgetGrouping": "merged"
      },
      Object.assign({
        "group": true
      }, given),
      {
        "group": color
      }
    ];
  }

  // In a merged split run, a widget that doesn't split (icon or text
  // alone, one drawing its own content) fills its own box: a tab in the
  // row, as the others' icon parts are
  function test_unsplit_widget_fills_its_box_in_a_merged_split_run() {
    const c = split("tint", ...splitRun("#222222", {
      "splits": false
    }));
    same(c.fill, accent, "its box");
    same(c.text, own, "text on it");
    same(c.icon, own, "icon on it");
    // Separate, it draws as filled anyway
    same(split("tint", {}, {
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
    same(split("color", {}, {}, {
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
    const c = split("tint", {}, {
      "splits": false
    });
    same(c.fill, accent, "fill");
    same(c.text, own, "text");
    same(c.iconFill, "transparent", "no icon part");
    same(styled("filled").iconFill, "transparent", "other styles have none");
  }

  function test_split_merged_keeps_the_icon_part_on_the_run() {
    const light = "#eeeeee";
    const c = split("tint", ...splitRun(light));
    same(c.fill, "transparent", "the run draws the label's");
    same(c.iconFill, accent, "icon part");
    same(c.icon, own, "icon reads on it");
    same(c.text, "#000000", "label reads on the run");
    // A widget with no parts fills its own box on the run
    // (test_unsplit_widget_fills_its_box_in_a_merged_split_run)
    same(split("tint", ...splitRun(light, {
      "splits": false
    })).fill, accent, "its own box");
  }

  function test_split_cells_are_filled() {
    const c = cell("split", "empty");
    same(c.fill, accent, "fill");
    same(c.content, own, "content");
  }

  // Cells as segments of a merged run (Workspaces with its Background
  // off): the run draws the box, the content takes the state's color.
  // `extra`: { bar (the look's other keys), given (the state's other
  // fields), group (the run's color, else black) }
  function test_cells_in_a_merged_run_leave_the_box_to_it() {
    const groupCell = (style, cellState, extra) => root.paintCell(Object.assign({
        "widgetStyle": style,
        "widgetGrouping": "merged"
      }, extra?.bar ?? {}), Object.assign({
        "group": true
      }, extra?.given ?? {}), {
        "group": extra?.group ?? "#000000"
      }, cellState);
    ["filled", "tinted", "outline"].forEach(style => {
      const c = groupCell(style, "active");
      same(c.fill, "transparent", style + ": no fill");
      same(c.stroke, "transparent", style + ": no stroke");
      same(c.content, accent, style + ": its color in the content");
    });
    same(groupCell("outline", "occupied").content, accent, "occupied too");
    same(groupCell("tinted", "empty").content, Qt.alpha(barText, 0.4), "empty: faded");
    same(groupCell("filled", "empty", {
      "group": "#ffffff"
    }).content, Qt.alpha("#000000", 0.4), "faded, reading on a filled run");
    same(groupCell("filled", "active", {
      "given": solid
    }).fill, accent, "a solid box stays filled");
    same(groupCell("split", "active").fill, accent, "split's fill too");
    same(groupCell("outline", "active", {
      "bar": {
        "hoverFill": true
      },
      "given": {
        "hovered": true
      }
    }).fill, accent, "filled on hover, its own part");
  }

  // What of a cell's box takes the bar's gradient, under an Auto color.
  // `extra`: { given (the state's other fields), group (in a merged run
  // of that color) }
  function test_cell_gradient_parts() {
    const part = (style, extra) => root.paintCell({
        "widgetStyle": style,
        "widgetGrouping": extra?.group ? "merged" : "separate"
      }, Object.assign({
        "gradient": graded,
        "auto": true,
        "group": !!extra?.group
      }, extra?.given ?? {}), {
        "group": extra?.group ?? null
      }, "active").gradient;
    compare(part("filled"), {
      "part": "fill",
      "alpha": 1
    });
    compare(part("tinted"), {
      "part": "fill",
      "alpha": 0.25
    });
    compare(part("outline").part, "stroke");
    compare(part("filled", {
      "given": solid
    }).part, "fill", "solid");
    compare(part("plain"), null);
    compare(part("outline", {
      "group": "#000000"
    }), null, "content only in a merged run");
    compare(part("filled", {
      "given": {
        "auto": false
      }
    }), null, "a set color: none");
  }

  // The look's colors resolved once
  // ---- Backdrops and the nudge ----

  function test_over_composites_opaque() {
    same(BarWidgetStyle.over("#ffffff", "#000000"), "#ffffff", "opaque top");
    same(BarWidgetStyle.over("transparent", "#336699"), "#336699", "clear top");
    close(BarWidgetStyle.over(Qt.rgba(1, 1, 1, 0.5), "#000000"), Qt.rgba(0.5, 0.5, 0.5, 1), "half");
    // The under color is taken opaque
    compare(BarWidgetStyle.over(Qt.rgba(1, 0, 0, 0.5), Qt.rgba(0, 0, 0, 0.2)).a, 1, "alpha");
  }

  function test_nudged_keeps_a_readable_color() {
    same(BarWidgetStyle.nudged(["#000000"], "#ffffff", 4.5), "#ffffff", "white on black");
    same(BarWidgetStyle.nudged(["#000000"], "transparent", 4.5), "transparent", "clear");
  }

  function test_nudged_reaches_the_threshold_by_the_least() {
    const back = BarWidgetStyle.over(BarWidgetStyle.faded("#31748f", 0.2), "#191724");
    const out = BarWidgetStyle.nudged([back], "#31748f", 4.5);
    verify(Utils.contrast(back, "#31748f") < 4.5, "the live case is unreadable");
    verify(Utils.contrast(back, out) >= 4.5, "reads: " + Utils.contrast(back, out));
    verify(Utils.contrast(back, out) < 4.8, "by the least: " + Utils.contrast(back, out));
    verify(Qt.color(out).r > Qt.color("#31748f").r && Qt.color(out).b > Qt.color("#31748f").b, "lighter");
    verify(Qt.color(out).b > Qt.color(out).r, "hue kept");
    // A light backdrop goes darker
    const dark = BarWidgetStyle.nudged(["#f0f0f0"], "#7090a0", 4.5);
    verify(Utils.contrast("#f0f0f0", dark) >= 4.5, "reads on light");
    verify(Qt.color(dark).r < Qt.color("#7090a0").r, "darker");
  }

  function test_nudged_reads_on_every_back() {
    const backs = ["#202020", "#808080"];
    const out = BarWidgetStyle.nudged(backs, "#909090", 3);
    verify(Utils.contrast(backs[0], out) >= 3 && Utils.contrast(backs[1], out) >= 3, "both");
  }

  function test_nudged_unreachable_is_the_pole() {
    // Mid grey on mid grey at 7: no mix reaches it
    const out = BarWidgetStyle.nudged(["#777777"], "#777777", 21);
    verify(Qt.colorEqual(out, "#000000") || Qt.colorEqual(out, "#ffffff"), "a pole");
  }

  function test_nudged_keeps_alpha() {
    fuzzyCompare(Qt.color(BarWidgetStyle.nudged(["#000000"], Qt.rgba(0.1, 0.1, 0.1, 0.5), 4.5)).a, 0.5, 0.01);
  }

  // The backdrops each content part is checked against, row by row of the
  // table in BarWidgetStyle: bar black here
  function test_backdrops_data() {
    const bar = "#000000";
    const acc = accent;
    const tintOf = c => BarWidgetStyle.over(BarWidgetStyle.faded(c, 0.25), bar);
    const split = fill => ({
          "widgetStyle": "split",
          "splitIcon": "joined",
          "splitLabelFill": fill
        });
    const merged = style => ({
          "widgetStyle": style,
          "widgetGrouping": "merged"
        });
    return [
      {
        "tag": "hovered fill",
        "bar": {
          "widgetStyle": "tinted",
          "hoverFill": true
        },
        "given": {
          "hovered": true
        },
        "text": [acc],
        "icon": [acc]
      },
      {
        "tag": "filled",
        "bar": {
          "widgetStyle": "filled"
        },
        "given": {},
        "text": [acc],
        "icon": [acc]
      },
      {
        "tag": "tinted",
        "bar": {
          "widgetStyle": "tinted"
        },
        "given": {},
        "text": [tintOf(acc)],
        "icon": [tintOf(acc)]
      },
      {
        "tag": "outline",
        "bar": {
          "widgetStyle": "outline"
        },
        "given": {},
        "text": [bar],
        "icon": [bar]
      },
      {
        "tag": "split label on a tint",
        "bar": split("tint"),
        "given": {
          "splits": true
        },
        "text": [tintOf(acc)],
        "icon": [acc]
      },
      {
        "tag": "split label on its own color",
        "bar": split("color"),
        "given": {
          "splits": true
        },
        "colors": {
          "labelColor": "#333333"
        },
        "text": ["#333333"],
        "icon": [acc]
      },
      {
        "tag": "split label on the bar",
        "bar": split("none"),
        "given": {
          "splits": true
        },
        "text": [bar],
        "icon": [acc]
      },
      {
        "tag": "merged split, icon part",
        "bar": Object.assign(split("tint"), {
          "widgetGrouping": "merged"
        }),
        "given": {
          "splits": true,
          "group": true
        },
        "colors": {
          "group": "#222222"
        },
        "text": ["#222222"],
        "icon": [acc]
      },
      {
        "tag": "merged filled run",
        "bar": merged("filled"),
        "given": {
          "group": true
        },
        "colors": {
          "group": "#222222"
        },
        "text": ["#222222"],
        "icon": ["#222222"]
      },
      {
        "tag": "merged tinted run",
        "bar": merged("tinted"),
        "given": {
          "group": true
        },
        "colors": {
          "group": "#222222"
        },
        "text": [bar],
        "icon": [bar]
      }
    ].map(row => Object.assign({}, row, {
        "text": row.text.map(c => Qt.color(c)),
        "icon": row.icon.map(c => Qt.color(c))
      }));
  }

  function test_backdrops(data) {
    const c = root.paint(data.bar, data.given, data.colors);
    compare(c.textBack.length, data.text.length, "text backs");
    for (let i = 0; i < data.text.length; i++)
      close(c.textBack[i], data.text[i], "textBack " + i);
    for (let i = 0; i < data.icon.length; i++)
      close(c.iconBack[i], data.icon[i], "iconBack " + i);
  }

  function test_iconOnFill() {
    verify(styled("filled").iconOnFill, "filled");
    verify(!styled("tinted").iconOnFill, "tinted");
    verify(!styled("outline").iconOnFill, "outline");
    verify(root.paint({
      "widgetStyle": "split"
    }, {
      "splits": true
    }).iconOnFill, "split's icon part");
  }

  function test_a_pill_level_is_a_second_backdrop() {
    const c = root.paint({
      "widgetStyle": "tinted"
    }, {
      "level": true
    });
    compare(c.textBack.length, 2, "text");
    compare(c.iconBack.length, 2, "icon");
    same(c.textBack[1], BarWidgetStyle.over(c.level, c.textBack[0]), "over the level");
    compare(styled("tinted").textBack.length, 1, "none without");
    same(c.level, BarWidgetStyle.faded(styled("tinted").icon, 0.35), "level from the icon");
  }

  // An accent too dark for its tint: the live split label
  readonly property color dim: "#31748f"

  function test_split_label_on_a_tint_is_nudged() {
    const bar = {
      "widgetStyle": "split",
      "splitIcon": "joined",
      "splitLabelFill": "tint"
    };
    const c = root.paint(bar, {
      "splits": true
    }, {
      "background": "#191724"
    }, dim);
    verify(Utils.contrast(c.textBack[0], c.text) >= 4.5, "label reads on its tint");
    same(c.fill, BarWidgetStyle.faded(dim, 0.25), "the tint itself is not nudged");
    verify(Utils.contrast(c.iconBack[0], c.icon) >= 3, "icon reads");
    // Outline text and a tinted widget's likewise
    for (const style of ["tinted", "outline", "accentText"]) {
      const o = root.paint({
        "widgetStyle": style
      }, {}, {
        "background": "#191724"
      }, dim);
      verify(Utils.contrast(o.textBack[0], o.text) >= 4.5 || style === "accentText", style);
    }
  }

  function test_override_is_never_nudged() {
    const unreadable = "#101010";
    for (const style of ["filled", "tinted", "outline", "plain"]) {
      const c = styled(style, unreadable);
      same(c.text, unreadable, style + " text");
      same(c.icon, unreadable, style + " icon");
    }
  }

  function test_state_content_with_hasState_false_is_the_colors() {
    const c = styled("tinted");
    const on = {
      "colorText": true
    };
    same(BarWidgetStyle.stateContent(c, on, "#ff0000", false).text, c.text, "text");
    same(BarWidgetStyle.stateContent(c, null, "#ff0000", true).icon, c.icon, "no appearance");
  }

  function test_content_is_nudged_where_the_part_sits() {
    // A dim neutral on a split icon part (its fill the accent) and on a tint
    const part = root.paint({
      "widgetStyle": "split"
    }, {
      "splits": true
    });
    const neutral = "#ff9090";
    same(BarWidgetStyle.content(part, neutral, "icon"), BarWidgetStyle.nudged(part.iconBack, neutral, 3), "on the icon part");
    const tint = styled("tinted");
    same(BarWidgetStyle.content(tint, "#111111", "text"), BarWidgetStyle.nudged(tint.textBack, "#111111", 4.5), "text on a tint");
  }

  function test_cell_content_reads_on_what_it_sits_on() {
    const under = [Qt.color("#c0c0c0")];
    const own = style => root.paintCell({
        "widgetStyle": style
      }, {
        "under": under
      }, {}, "active", "#ff8080");
    // Outline: on what the widget's text sits on
    same(own("outline").content, BarWidgetStyle.nudged(under, "#ff8080", 4.5), "outline on the widget's backdrop");
    // Empty and plain's fading states are left as they are
    same(root.paintCell({
      "widgetStyle": "outline"
    }, {
      "under": under
    }, {}, "empty", "#ff8080").content, Qt.alpha(barText, 0.4), "empty");
    same(root.paintCell({
      "widgetStyle": "plain"
    }, {
      "under": under
    }, {}, "occupied", "#ff8080").content, Qt.alpha(barText, 0.7), "plain occupied");
    // Without `under`, the bar
    same(root.paintCell({
      "widgetStyle": "outline"
    }, {}, {}, "active", "#101010").content, BarWidgetStyle.nudged([Qt.color("#000000")], "#101010", 4.5), "the bar");
  }

  function test_palette() {
    const names = {
      "accent": "#ff0000",
      "base03": "#333333",
      "red": "#aa0000",
      "fg": "#ffffff"
    };
    const resolve = name => Qt.color(names[name] ?? "#000000");
    const graded = root.look({
      "groupColor": "base03",
      "groupStrokeColor": "accent",
      "gradient": true,
      "gradientFrom": "accent",
      "gradientVia": "",
      "gradientTo": "red"
    });
    const p = BarWidgetStyle.palette(graded, resolve, "#ffffff", "#101010");
    same(p.barText, "#ffffff", "the bar's text");
    same(p.background, "#101010", "the background");
    compare(p.override, null, "Auto text");
    compare(p.labelColor, null, "no split");
    same(p.group, "#333333", "group");
    same(p.groupStroke, "#ff0000", "group stroke");
    same(p.gradientStops[1], "#aa0000", "stops");
    const set = BarWidgetStyle.palette(root.look({
      "widgetStyle": "split",
      "widgetTextColor": "fg",
      "splitLabelColor": "red"
    }), resolve, "#ffffff", "#101010");
    same(set.override, "#ffffff", "set text color");
    same(set.labelColor, "#aa0000", "split's label color");
    compare(set.gradientStops, null, "no gradient");
  }

  // A spot along the bar stands for the gradient's color there
  function test_state() {
    const colors = {
      "gradientStops": ["#000000", "#ffffff"]
    };
    const s = BarWidgetStyle.state(colors, {
      "spot": 0.5,
      "auto": true
    });
    same(s.gradient, Qt.rgba(0.5, 0.5, 0.5, 1), "the gradient at its spot");
    compare([s.auto, s.splits, s.hovered, s.run, s.group, s.solid], [true, false, false, false, false, false]);
    compare(BarWidgetStyle.state(colors, {}).gradient, null, "no spot");
    compare(BarWidgetStyle.state({
      "gradientStops": null
    }, {
      "spot": 0.5
    }).gradient, null, "no gradient");
  }

  // A merged run's own background: its group color, an outline run's line
  // its stroke color
  function test_run_colors() {
    const colors = root.palette({
      "group": "#333333",
      "groupStroke": "#ff0000"
    });
    const run = style => BarWidgetStyle.runColors(root.look({
        "widgetStyle": style,
        "widgetGrouping": "merged"
      }), colors, -1);
    same(run("filled").fill, "#333333", "filled run");
    const outline = run("outline");
    same(outline.stroke, "#ff0000", "outline run's line");
    compare(outline.gradient, null, "no gradient");
  }
}
