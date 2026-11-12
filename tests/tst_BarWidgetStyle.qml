import QtQuick
import QtTest
import qs.components.methods
import "barstyle/Bars.js" as Bars

// What a bar widget or a Workspaces cell paints each part in
// (BarWidgetStyle), for the looks BarLook.resolve makes of a bar's
// BarStyle keys, on enriched bars (barstyle/Bars.js). Three blocks: exact
// rows for the small functions, one row per look for where its state color
// shows, and the invariant sweep: every look × grouping × hover × gradient
// × split × level × muted on a dark and a light theme and
// three accents, and the same for cells, asserting what must hold of every
// one (contrast floors, the gradient's slice,
// muted differing). The sweep never asks the core's `_widget` for an
// expected value: it compares only with the pure helpers.
TestCase {
  id: root

  name: "BarWidgetStyle"

  function same(actual, expected, message) {
    verify(Qt.colorEqual(actual, expected), `${message}: ${actual} != ${expected}`);
  }

  // Equal to within 8-bit rounding (a composite is computed in floats)
  function close(actual, expected, message) {
    const a = Qt.color(actual), e = Qt.color(expected);
    verify(Math.abs(a.r - e.r) < 0.01 && Math.abs(a.g - e.g) < 0.01 && Math.abs(a.b - e.b) < 0.01, `${message}: ${actual} != ${expected}`);
  }

  // ---- Exact rows ----

  function test_over_composites_opaque() {
    same(BarWidgetStyle.over("#ffffff", "#000000"), "#ffffff", "opaque top");
    close(BarWidgetStyle.over(Qt.rgba(1, 1, 1, 0.5), "#000000"), Qt.rgba(0.5, 0.5, 0.5, 1), "half");
  }

  function test_faded_keeps_a_clear_color_clear() {
    fuzzyCompare(Qt.color(BarWidgetStyle.faded("#80ff0000", 0.5)).a, 0.25, 0.01, "from its own alpha");
    compare(Qt.color(BarWidgetStyle.faded("transparent", 0.5)).a, 0, "clear stays clear");
  }

  function test_nudged() {
    same(BarWidgetStyle.nudged(["#000000"], "#ffffff", 4.5), "#ffffff", "a readable color is kept");
    // By the least that reaches it, its hue kept, lighter on a dark back
    const back = BarWidgetStyle.over(BarWidgetStyle.faded("#31748f", 0.2), "#191724");
    const out = Qt.color(BarWidgetStyle.nudged([back], "#31748f", 4.5));
    verify(Utils.contrast(back, "#31748f") < 4.5, "the live case is unreadable");
    verify(Utils.contrast(back, out) >= 4.5 && Utils.contrast(back, out) < 4.8, "by the least: " + Utils.contrast(back, out));
    verify(out.r > 0x31 / 255 && out.b > out.r, "lighter, hue kept");
    // A light back goes darker
    const dark = Qt.color(BarWidgetStyle.nudged(["#f0f0f0"], "#7090a0", 4.5));
    verify(Utils.contrast("#f0f0f0", dark) >= 4.5 && dark.r < 0x70 / 255, "darker on light");
    // Every back
    const both = BarWidgetStyle.nudged(["#202020", "#808080"], "#909090", 3);
    verify(Utils.contrast("#202020", both) >= 3 && Utils.contrast("#808080", both) >= 3, "both");
    // No mix reaches it: a pole
    const pole = BarWidgetStyle.nudged(["#777777"], "#777777", 21);
    verify(Qt.colorEqual(pole, "#000000") || Qt.colorEqual(pole, "#ffffff"), "a pole");
  }

  function test_readable_on() {
    same(BarWidgetStyle.readableOn("#000000", "#ffffff"), "#ffffff", "contrasting");
    same(BarWidgetStyle.readableOn("#ffffff", "#eeeeee"), "#000000", "too close");
    // By contrast, not a luma split: gruvbox's dark text on its red reads
    // at about 4.3, black at 6.1
    same(BarWidgetStyle.readableOn("#fb4934", "#282828"), "#000000", "black beats the dark text");
    same(BarWidgetStyle.readableOn("#777777", "#ffffff", ["#000000"]), "#000000", "the one with the most contrast");
  }

  function test_mix() {
    same(BarWidgetStyle.mix("#ff0000", "#0000ff", 0), "#ff0000", "none");
    same(BarWidgetStyle.mix("#ff0000", "#0000ff", 1), "#0000ff", "all");
    close(BarWidgetStyle.mix("#000000", "#ffffff", 0.25), "#404040", "a quarter");
  }

  // Muted: mixed mutedMix toward the first back, floored at mutedContrast
  function test_muted() {
    const backs = ["#202020"];
    const m = BarWidgetStyle.muted(backs, "#ffffff");
    close(m, BarWidgetStyle.mix("#ffffff", "#202020", 0.45), "mixed toward the back");
    verify(Utils.contrast("#202020", m) >= 3, "above the floor");
    // Where the mix falls short of the floor it is nudged up to it
    const low = BarWidgetStyle.muted(["#202020"], "#505050");
    verify(Utils.contrast("#202020", low) >= 3 && Utils.contrast("#202020", low) < 3.3, "floored: " + Utils.contrast("#202020", low));
  }

  function test_mix_colors_meets_in_between() {
    const bar = Bars.bar({});
    const rest = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {});
    const dim = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {
      "muted": true
    });
    compare(BarWidgetStyle.mixColors(rest, dim, 0), rest, "0 is the first");
    const mid = BarWidgetStyle.mixColors(rest, dim, 0.5);
    close(mid.fill, BarWidgetStyle.mix(rest.fill, dim.fill, 0.5), "fill");
    verify(Utils.contrast(mid.iconBack[0], mid.icon) >= 3, "the mid-point's icon reads");
  }

  function test_mix_colors_keys_match_the_full_mix() {
    const bar = Bars.bar({});
    const rest = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {});
    const dim = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {
      "muted": true
    });
    const full = BarWidgetStyle.mixColors(rest, dim, 0.4);
    const part = BarWidgetStyle.mixColors(rest, dim, 0.4, ["text", "textBack", "fill"]);
    compare(Object.keys(part).sort(), ["fill", "text", "textBack"], "only its keys");
    for (const key of ["fill", "text", "textBack"])
      compare(part[key], full[key], key);
  }

  function test_state() {
    const palette = {
      "gradientStops": ["#000000", "#ffffff"]
    };
    const s = BarWidgetStyle.state(palette, {
      "spot": 0.5,
      "auto": true,
      "muted": true
    });
    same(s.gradient, Qt.rgba(0.5, 0.5, 0.5, 1), "the gradient at its spot");
    compare([s.auto, s.muted, s.splits, s.hovered, s.pressed, s.run, s.group, s.solid, s.level, s.hover], [true, true, false, false, false, false, false, false, false, null]);
    compare(BarWidgetStyle.state(palette, {}).gradient, null, "no spot");
    compare(BarWidgetStyle.state({
      "gradientStops": null
    }, {
      "spot": 0.5
    }).gradient, null, "no gradient");
  }

  // The palette resolves every bar color once; a user's colors are as set
  function test_palette() {
    const resolve = Bars.resolverOf(Bars.theme);
    const p = Bars.bar({
      "gradient": true,
      "gradientFrom": "base08",
      "gradientVia": "",
      "gradientTo": "base0D",
      "widgetTextColor": "base0B",
      "separatorColor": "base0E",
      "accentLine": "inner",
      "accentLineColor": "base0A",
      "accentLineFade": "base0D",
      "groupColor": "base02",
      "groupStrokeColor": "base03"
    }).palette;
    same(p.barText, Bars.theme.foreground, "the bar's text");
    same(p.background, Bars.theme.background, "the background");
    [["override", "base0B"], ["group", "base02"], ["groupStroke", "base03"], ["separator", "base0E"]].forEach(([key, name]) => same(p[key], resolve(name), key));
    compare(p.gradientStops.length, 2, "stops");
    same(p.accentLine.from, resolve("base0A"), "accent line from");
    same(p.accentLine.to, resolve("base0D"), "accent line fades to");
    same(p.hoverOutline, Bars.theme.border, "hover outline");
    same(p.cellHover, Bars.theme.backgroundHighlight, "cell hover");
    same(p.highlight, Bars.theme.accent, "editor highlight");
    const plain = Bars.bar({}).palette;
    compare([plain.override, plain.gradientStops, plain.accentLine], [null, null, null], "Auto text, no gradient, no line");
    same(Bars.bar({
      "accentLine": "outer",
      "accentLineColor": "base0A"
    }).palette.accentLine.to, resolve("base0A"), "no fade: one color");
  }

  // A field's color: the gradient's where it gives way; under the bar's
  // text color an Auto one takes it unless it is a state color (warning, critical, rise, fall)
  function test_field_color() {
    const stops = {
      "override": null,
      "gradientStops": ["#000000", "#ffffff"]
    };
    same(BarWidgetStyle.fieldColor(stops, 0.5, "#ff0000", true, "accent"), Qt.rgba(0.5, 0.5, 0.5, 1), "on the fade");
    same(BarWidgetStyle.fieldColor(stops, 0.5, "#ff0000", false, "accent"), "#ff0000", "not giving way");
    same(BarWidgetStyle.fieldColor(stops, -1, "#ff0000", true, "accent"), "#ff0000", "no place on the bar");
    same(BarWidgetStyle.fieldColor({
      "override": null,
      "gradientStops": null
    }, 0.5, "#ff0000", true, "accent"), "#ff0000", "no gradient");
    const set = {
      "override": Qt.color("#00ff00"),
      "gradientStops": null
    };
    ["accent", "alt", "off", "neutral"].forEach(role => same(BarWidgetStyle.fieldColor(set, 0.5, "#ff0000", true, role), "#00ff00", role + " takes the override"));
    ["warning", "critical", "rise", "fall", ""].forEach(role => same(BarWidgetStyle.fieldColor(set, 0.5, "#ff0000", true, role), "#ff0000", (role || "a set colour") + " keeps its own"));
  }

  function test_press_mixes_content_toward_its_back_and_still_reads() {
    const bar = Bars.bar({
      "widgetStyle": "tinted"
    });
    const rest = BarWidgetStyle.widgetColors(bar, "#458588", "#282828", {});
    const pressed = BarWidgetStyle.widgetColors(bar, "#458588", "#282828", {
      "pressed": true
    });
    verify(!Qt.colorEqual(rest.text, pressed.text) && !Qt.colorEqual(rest.icon, pressed.icon), "content differs");
    verify(Utils.contrast(pressed.textBack[0], pressed.text) >= 4.5 && Utils.contrast(pressed.iconBack[0], pressed.icon) >= 3, "and reads");
    same(pressed.fill, rest.fill, "the fill stays");
  }

  // A pill level is a second backdrop its content reads on: the icon's
  // color at 35% where that works, else a white or black sheen
  function test_level_is_a_backdrop_the_content_reads_on() {
    const level = (style, accent) => BarWidgetStyle.widgetColors(Bars.bar({
        "widgetStyle": style
      }), accent, "#282828", {
        "level": true
      });
    const c = level("filled", "#458588");
    compare(c.textBack.length, 2, "two backdrops");
    same(Qt.rgba(c.level.r, c.level.g, c.level.b, 1), "#ffffff", "a white sheen on a mid fill");
    fuzzyCompare(c.level.a, 0.35, 0.01, "at the same strength");
    c.textBack.forEach(back => verify(Utils.contrast(back, c.text) >= 4.5, "text reads on each: " + back));
  }

  // A cell's content in an empty cell is mixed emptyMix toward what it
  // sits on, floored at mutedContrast
  function test_empty_cells_are_muted_by_the_empty_mix() {
    const bar = Bars.bar({
      "widgetStyle": "plain"
    });
    const c = BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, {}), "#665c54", Bars.theme.foreground, "empty");
    const back = BarWidgetStyle.over(bar.palette.background, bar.palette.background);
    const want = BarWidgetStyle.nudged([back], BarWidgetStyle.mix(Bars.theme.foreground, back, BarWidgetStyle.emptyMix), 3);
    same(c.content, want, "mixed toward the bar");
  }

  // WidgetCell pulses with mixColors of the cell and its muted self
  function test_cell_pulse_goes_between_the_cell_and_its_muted_self() {
    const bar = Bars.bar({
      "widgetStyle": "filled"
    });
    const cell = muted => BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, {
        "muted": muted
      }), "#fb4934", "#282828", "urgent");
    same(cell(false).fill, "#fb4934", "at rest");
    same(BarWidgetStyle.mixColors(cell(false), cell(true), 1).fill, cell(true).fill, "fully pulsed is muted");
    const mid = BarWidgetStyle.mixColors(cell(false), cell(true), 0.5);
    close(mid.fill, BarWidgetStyle.mix(cell(false).fill, cell(true).fill, 0.5), "between");
    mid.back.forEach(back => verify(Utils.contrast(back, mid.content) >= 3, "the mid-point reads"));
    compare(cell(false).hover.toString(), Bars.theme.backgroundHighlight, "a cell's hover is the palette's");
    same(BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, {
      "hover": "#123456"
    }), "#fb4934", "#282828", "active").hover, "#123456", "or its own");
  }

  function test_run_colors() {
    const run = style => {
      const bar = Bars.bar({
        "widgetStyle": style,
        "widgetGrouping": "merged",
        "groupColor": "base02",
        "groupStrokeColor": "base08"
      });
      return BarWidgetStyle.runColors(bar.look, bar.palette, -1);
    };
    same(run("filled").fill, Bars.theme.base02, "filled run");
    same(run("outline").stroke, Bars.theme.base08, "an outline run's line");
    compare(run("outline").gradient, null, "no gradient");
    const merged = BarWidgetStyle.widgetColors(Bars.bar({
      "widgetStyle": "filled",
      "widgetGrouping": "merged",
      "gradient": true
    }), "#fb4934", "#282828", {
      "spot": 0.3,
      "auto": true
    });
    compare(merged.gradient, null, "a merged widget draws no gradient of its own");
  }

  // ---- Hover and backdrops ----

  // A widget's colors on a look (BarStyle keys), accent #fb4934 over the
  // dark theme's #282828, `widget` its state
  function colorsOf(over, widget) {
    const bar = Bars.bar(Object.assign({
      "tintOpacity": 25
    }, over));
    return BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", widget);
  }

  // Fill on hover: a hovered tinted or outlined widget draws filled in its
  // state color (an outline keeps its stroke, not in a run), its text and
  // icon reading on it; a filled one already is, a split one never fills
  // and without the setting nothing does. [look, BarStyle keys, widget,
  // fill, stroke, textOnFill]
  readonly property var hoverRows: [["tinted", "widgetStyle=tinted",
      {},
      "#fb4934", "transparent", true], ["tinted, no fill on hover", "widgetStyle=tinted;hoverFill=false",
      {},
      "tint", "transparent", false], ["outline", "widgetStyle=outline",
      {},
      "#fb4934", "#fb4934", true], ["filled", "widgetStyle=filled",
      {},
      "#fb4934", "transparent", true], ["split icon part", "widgetStyle=split;splitIcon=joined;splitLabelFill=tint",
      {
        "splits": true
      },
      "tint", "transparent", false], ["split label color", "widgetStyle=split;splitIcon=joined;splitLabelFill=color",
      {
        "splits": true
      },
      "labelColor", "transparent", true], ["split without parts", "widgetStyle=split",
      {
        "splits": false
      },
      "#fb4934", "transparent", true], ["merged tinted", "widgetStyle=tinted;widgetGrouping=merged",
      {},
      "#fb4934", "transparent", true], ["merged outline", "widgetStyle=outline;widgetGrouping=merged",
      {},
      "#fb4934", "transparent", true]]

  function parse(keys) {
    return keys.split(";").reduce((o, kv) => Object.assign(o, {
        [kv.split("=")[0]]: kv.split("=")[1] === "false" ? false : kv.split("=")[1] === "true" ? true : kv.split("=")[1]
      }), {});
  }

  function test_hover_rows() {
    const fails = [];
    for (const [name, keys, widget, fill, stroke, onFill] of root.hoverRows) {
      const over = Object.assign({
        "hoverFill": true
      }, root.parse(keys));
      const c = root.colorsOf(over, Object.assign({
        "hovered": true
      }, widget));
      const labelColor = Bars.bar(over).palette.labelColor;
      const want = fill === "tint" ? BarWidgetStyle.faded("#fb4934", 0.25) : fill === "labelColor" ? labelColor : fill;
      if (!Qt.colorEqual(c.fill, want))
        fails.push(`${name}: fill ${c.fill}, not ${want}`);
      if (!Qt.colorEqual(c.stroke, stroke))
        fails.push(`${name}: stroke ${c.stroke}, not ${stroke}`);
      if (c.textOnFill !== onFill)
        fails.push(`${name}: textOnFill ${c.textOnFill}`);
      // What a split never does: fill the widget in the accent as a whole
      if (name.startsWith("split icon") && Qt.colorEqual(c.fill, "#fb4934"))
        fails.push(`${name}: filled on hover`);
      c.textBack.forEach(b => {
        if (Utils.contrast(b, c.text) < 4.5)
          fails.push(`${name}: text ${c.text} under 4.5 on ${b}`);
      });
    }
    verify(fails.length === 0, fails.join("\n"));
  }

  // What the text and the icon sit on (opaque; two with a pill level) and
  // whether the text sits on a fill it must read on. [look, BarStyle keys,
  // widget, textBack, iconBack, textOnFill]; a color name is a palette key,
  // `tint` the accent's tint over the bar, `accent` the accent over it
  readonly property var backdropRows: [["filled", "widgetStyle=filled",
      {},
      "accent", "accent", true], ["tinted", "widgetStyle=tinted",
      {},
      "tint", "tint", false], ["plain", "widgetStyle=plain",
      {},
      "bar", "bar", false], ["split label tint", "widgetStyle=split;splitIcon=joined;splitLabelFill=tint",
      {
        "splits": true
      },
      "tint", "accent", false], ["split label color", "widgetStyle=split;splitIcon=joined;splitLabelFill=color",
      {
        "splits": true
      },
      "labelColor", "accent", true], ["split label none", "widgetStyle=split;splitIcon=joined;splitLabelFill=none",
      {
        "splits": true
      },
      "bar", "accent", false], ["split, no parts", "widgetStyle=split",
      {
        "splits": false
      },
      "accent", "accent", true], ["merged filled", "widgetStyle=filled;widgetGrouping=merged;groupColor=base02",
      {},
      "group", "group", true], ["merged plain", "widgetStyle=plain;widgetGrouping=merged;groupColor=base02",
      {},
      "bar", "bar", false], ["tinted hovered", "widgetStyle=tinted;hoverFill=true",
      {
        "hovered": true
      },
      "accent", "accent", true]]

  function test_backdrop_rows() {
    const fails = [];
    const bg = Bars.theme.background;
    for (const [name, keys, widget, text, icon, onFill] of root.backdropRows) {
      const over = root.parse(keys);
      const palette = Bars.bar(over).palette;
      const c = root.colorsOf(over, widget);
      const named = (key, back) => key === "accent" ? BarWidgetStyle.over("#fb4934", back) : key === "tint" ? BarWidgetStyle.over(BarWidgetStyle.faded("#fb4934", 0.25), back) : key === "bar" ? back : BarWidgetStyle.over(palette[key], back);
      if (c.textBack.length !== 1 || !root.close2(c.textBack[0], named(text, bg)))
        fails.push(`${name}: textBack ${c.textBack}, not ${text}`);
      if (c.iconBack.length !== 1 || !root.close2(c.iconBack[0], named(icon, bg)))
        fails.push(`${name}: iconBack ${c.iconBack}, not ${icon}`);
      if (c.textOnFill !== onFill)
        fails.push(`${name}: textOnFill ${c.textOnFill}, not ${onFill}`);
    }
    // A pill level adds a second backdrop: the level over each
    const level = root.colorsOf({
      "widgetStyle": "filled"
    }, {
      "level": true
    });
    compare(level.textBack.length, 2, "level: two text backdrops");
    compare(level.iconBack.length, 2, "level: two icon backdrops");
    if (!root.close2(level.textBack[1], BarWidgetStyle.over(level.level, level.textBack[0])))
      fails.push("level: the second textBack is not the level over the first");
    if (!root.close2(level.iconBack[1], BarWidgetStyle.over(level.level, level.iconBack[0])))
      fails.push("level: the second iconBack is not the level over the first");
    verify(fails.length === 0, fails.join("\n"));
  }

  function close2(a, b) {
    const x = Qt.color(a), y = Qt.color(b);
    return Math.abs(x.r - y.r) < 0.01 && Math.abs(x.g - y.g) < 0.01 && Math.abs(x.b - y.b) < 0.01;
  }

  // ---- One row per look ----

  // Each look, split as each of its kinds: where its state color shows
  // (`show`: a key of colors(); `as`: the color itself, its tint, or read
  // as the icon) and what of it the bar's gradient takes (`part`, and
  // `whole` for a widget that doesn't split: the style's fallback)
  // [key, BarStyle keys ("k=v;…"), show, as, part, flags: s(plit) or m(erged)]
  readonly property var lookRows: [["filled", "widgetStyle=filled", "fill", "color", "fill@1", ""], ["tinted", "widgetStyle=tinted", "fill", "tint", "fill@tint", ""], ["outline", "widgetStyle=outline", "stroke", "color", "stroke@1", ""], ["underline", "widgetStyle=underline", "indicator", "color", "indicator@1", ""], ["accentText", "widgetStyle=accentText", "icon", "icon", "-", ""], ["plain", "widgetStyle=plain", "", "none", "-", ""], ["split.joined.tint", "widgetStyle=split;splitIcon=joined;splitLabelFill=tint", "iconFill", "color", "iconFill@1", "s"], ["split.joined.color", "widgetStyle=split;splitIcon=joined;splitLabelFill=color", "iconFill", "color", "iconFill@1", "s"], ["split.joined.none", "widgetStyle=split;splitIcon=joined;splitLabelFill=none", "iconFill", "color", "iconFill@1", "s"], ["split.badge.tint", "widgetStyle=split;splitIcon=badge;splitLabelFill=tint", "iconFill", "color", "iconFill@1", "s"], ["split.badge.color", "widgetStyle=split;splitIcon=badge;splitLabelFill=color", "iconFill", "color", "iconFill@1", "s"]]

  readonly property var looks: lookRows.map(r => ({
        "key": r[0],
        "over": r[1].split(";").reduce((o, kv) => Object.assign(o, {
            [kv.split("=")[0]]: kv.split("=")[1]
          }), {}),
        "show": r[2] || null,
        "as": r[3],
        "part": r[4],
        "split": r[5] === "s"
      }))

  readonly property var accents: ["#fb4934", "#fabd2f", "#458588"]
  readonly property var groupings: ["separate", "merged", "powerline"]

  function part(g) {
    return g ? `${g.part}@${g.alpha}` : "-";
  }

  // A look's own row: alone on a bar, at rest, its color Auto-less
  function test_each_look_shows_its_state_color_where_it_draws_it() {
    const fails = [];
    for (const look of root.looks) {
      const bar = Bars.bar(Object.assign({
        "tintOpacity": 25
      }, look.over));
      for (const split of look.split ? [false, true] : [false]) {
        const c = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {
          "splits": split
        });
        const tag = `${look.key}${split ? " split" : ""}`;
        const key = !split && look.split ? "fill" : look.show;
        const expected = look.as === "tint" ? BarWidgetStyle.faded("#fb4934", 0.25) : look.as === "icon" ? BarWidgetStyle.nudged(c.iconBack, "#fb4934", 3) : "#fb4934";
        if (key === null) {
          const other = BarWidgetStyle.widgetColors(bar, "#458588", "#282828", {});
          if (!Qt.colorEqual(c.text, other.text) || !Qt.colorEqual(c.icon, other.icon) || !Qt.colorEqual(c.fill, other.fill))
            fails.push(`${tag}: the accent shows on plain text`);
        } else if (!Qt.colorEqual(c[key], expected)) {
          fails.push(`${tag}: ${key} is ${c[key]}, not ${expected}`);
        }
      }
    }
    verify(fails.length === 0, fails.join("\n"));
  }

  // Which parts sit on the widget's own fill (a cool System Stats metric in
  // a warning box reads in the widget's colors there, its own field off
  // it): [BarStyle keys, text, icon]
  function test_parts_on_the_own_fill() {
    const rows = [["widgetStyle=filled", true, true], ["widgetStyle=plain", false, false], ["widgetStyle=underline", false, false], ["widgetStyle=outline", false, false], ["widgetStyle=split;splitIcon=joined;splitLabelFill=none", false, true]];
    for (const [keys, text, icon] of rows) {
      const c = BarWidgetStyle.widgetColors(Bars.bar(parse(keys)), "#fb4934", "#282828", {
        "splits": keys.indexOf("split") >= 0
      });
      compare(BarWidgetStyle.onOwnFill(c, "text"), text, keys + " text");
      compare(BarWidgetStyle.onOwnFill(c, "icon"), icon, keys + " icon");
      compare(BarWidgetStyle.onOwnFill(c, "headText"), icon, keys + " headText");
    }
  }

  function test_each_look_gradient_takes_its_part() {
    const fails = [];
    for (const look of root.looks) {
      const bar = Bars.bar(Object.assign({
        "gradient": true,
        "tintOpacity": 25
      }, look.over));
      for (const split of look.split ? [false, true] : [false]) {
        const c = BarWidgetStyle.widgetColors(bar, "#fb4934", "#282828", {
          "splits": split,
          "spot": 0.3,
          "auto": true
        });
        const want = !split && look.split ? "fill@1" : look.part;
        const got = root.part(c.gradient).replace("@0.25", "@tint");
        if (got !== want) {
          fails.push(`${look.key}${split ? " split" : ""}: gradient ${got}, not ${want}`);
        }
        // A split label's fill per splitLabelFill: a tint of the slice, the label color, or none
        if (split && look.split) {
          const label = look.key.startsWith("split.joined.") ? look.key.split(".")[2] : "none";
          const fill = label === "tint" ? BarWidgetStyle.faded(c.accent, 0.25) : label === "color" ? bar.palette.labelColor : "transparent";
          if (!Qt.colorEqual(c.fill, fill))
            fails.push(`${look.key}: label fill ${c.fill}, not ${fill}`);
        }
      }
    }
    verify(fails.length === 0, fails.join("\n"));
  }

  // A cell's own row (a non-solid one at rest): its state color shows where
  // the look draws it, mapped for a cell (iconFill is a filled box; icon the
  // content, read at 4.5), the text and the plain look's states as colors
  function test_each_look_cell_shows_its_state_color() {
    const fails = [];
    for (const look of root.looks) {
      const bar = Bars.bar(Object.assign({
        "tintOpacity": 25
      }, look.over));
      for (const state of ["active", "urgent"]) {
        const c = BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, {}), "#fb4934", "#282828", state);
        const tag = `${look.key} ${state}`;
        const key = look.show === "iconFill" ? "fill" : look.show === "icon" ? "content" : look.show;
        const read = BarWidgetStyle.nudged(c.back, "#fb4934", 4.5);
        if (key === null) {
          const want = state === "active" ? bar.palette.barText : read;
          if (!Qt.colorEqual(c.content, want))
            fails.push(`${tag}: content ${c.content}, not ${want}`);
        } else {
          const want = look.as === "tint" ? BarWidgetStyle.faded("#fb4934", 0.25) : key === "content" ? read : "#fb4934";
          if (!Qt.colorEqual(c[key], want))
            fails.push(`${tag}: ${key} is ${c[key]}, not ${want}`);
        }
      }
    }
    verify(fails.length === 0, fails.join("\n"));
  }

  // A cell's `auto` is given, never read from its spot: with it the cell's
  // gradient is the look's part and its color the gradient's; without it, a
  // spot changes nothing
  function test_each_look_cell_gradient_takes_its_part() {
    const fails = [];
    for (const look of root.looks) {
      const bar = Bars.bar(Object.assign({
        "gradient": true,
        "tintOpacity": 25
      }, look.over));
      const key = look.show === "iconFill" ? "fill" : look.show === "icon" ? "content" : look.show;
      const cellOf = auto => BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, {
          "spot": 0.3,
          "auto": auto
        }), "#fb4934", "#282828", "active");
      const on = cellOf(true);
      const off = cellOf(false);
      const want = look.part === "-" ? "-" : look.part === "iconFill@1" ? "fill@1" : look.part;
      const got = root.part(on.gradient).replace("@0.25", "@tint");
      if (got !== want)
        fails.push(`${look.key}: gradient ${got}, not ${want}`);
      if (off.gradient !== null)
        fails.push(`${look.key}: a spot alone grades the cell`);
      if (key !== null && key !== "content") {
        const at = BarGradient.gradientAt(bar.palette.gradientStops, 0.3);
        const wantOn = look.as === "tint" ? BarWidgetStyle.faded(at, 0.25) : at;
        if (!Qt.colorEqual(on[key], wantOn))
          fails.push(`${look.key}: ${key} ${on[key]}, not the gradient's ${wantOn}`);
        const wantOff = look.as === "tint" ? BarWidgetStyle.faded("#fb4934", 0.25) : "#fb4934";
        if (!Qt.colorEqual(off[key], wantOff))
          fails.push(`${look.key}: ${key} ${off[key]} with auto off, not ${wantOff}`);
      }
    }
    verify(fails.length === 0, fails.join("\n"));
  }

  // ---- The invariant sweep ----

  readonly property var themes: [["dark", Bars.theme], ["light", Bars.lightTheme]]
  // Fill on hover [off, on], hovered
  readonly property var hovers: [[false, false], [true, false], [true, true]]
  // The gradient [off, on] and whether the widget's color gives way to it
  readonly property var gradients: [[false, false], [true, true], [true, false]]

  property var _bars: ({})

  // The bar of a theme and a look, cached
  function barOf(themeKey, theme, look, grouping, hoverFill, gradient, textColor) {
    const key = [themeKey, look.key, grouping, hoverFill, gradient, textColor].join("/");
    if (!root._bars[key])
      root._bars[key] = Bars.bar(Object.assign({
        "tintOpacity": 25,
        "widgetGrouping": grouping,
        "widgetShape": grouping === "powerline" ? "arrow" : "rounded",
        "hoverFill": hoverFill,
        "gradient": gradient,
        "widgetTextColor": textColor
      }, look.over), Bars.themeEnv(theme));
    return root._bars[key];
  }

  // Whether `color` is white or black, a pole nothing was nudged to by
  // the least
  function pole(color) {
    return Qt.colorEqual(color, "#000000") || Qt.colorEqual(color, "#ffffff");
  }

  // `color` reads on every one of `backs` at `floor`
  function reads(backs, color, floor) {
    return backs.every(b => Utils.contrast(b, color) >= floor - 1e-6);
  }

  // What must hold of the colors() of a widget in `ctx`, whether `muted`
  // or not: pushes what doesn't to `fails`
  function checkWidget(fails, tag, c, muted, ctx) {
    const parts = [["text", c.text, c.textBack, c.textOwnFill, 4.5, c.textOnFill], ["icon", c.icon, c.iconBack, c.iconOwnFill, 3, c.iconOnFill], ["headText", c.headText, c.iconBack, c.iconOwnFill, 4.5, c.iconOnFill], ["mark", c.mark, c.iconBack, c.iconOwnFill, 3, c.iconOnFill], ["graphic.line", c.graphic.line, c.iconBack, c.iconOwnFill, 3, c.iconOnFill], ["graphic.subcaption", c.graphic.subcaption, c.iconBack, c.iconOwnFill, 3, c.iconOnFill]];
    for (const [name, color, backs, onFill, min, onAFill] of parts) {
      const floor = muted && !onFill ? BarWidgetStyle.mutedContrast : min;
      if (ctx.override) {
        // The set text color is the content's, as set; muted, mixed and floored
        if (!muted && name === "text" && !Qt.colorEqual(color, ctx.override))
          fails.push(`${tag}: text is not the set color`);
        if (muted && !onFill && !root.reads(backs, color, floor))
          fails.push(`${tag}: muted ${name} ${color} under ${floor} on ${backs}`);
        continue;
      }
      if (!root.reads(backs, color, floor))
        fails.push(`${tag}: ${name} ${color} under ${floor} on ${backs}`);
      if (!onAFill && name !== "graphic.line" && root.pole(color) && ["#ffffff", "#000000"].some(p => root.reads(backs, p, floor)))
        fails.push(`${tag}: ${name} is a pole (${color})`);
    }
    root.checkBadge(fails, tag, c, ctx);
    // The state color shows where it is asked to: the gradient's slice
    // exactly where it gives way, the widget's own else (under the bar's
    // text color too: it replaces content only)
    const stops = ctx.bar.palette.gradientStops;
    const slice = stops ? BarGradient.gradientAt(stops, 0.3) : null;
    const gives = ctx.gradient && ctx.auto && stops !== null;
    const base = gives ? slice : ctx.accent;
    const want = muted ? BarWidgetStyle.mix(base, ctx.bar.palette.background, BarWidgetStyle.mutedMix) : base;
    if (Math.abs(Qt.color(c.accent).r - Qt.color(want).r) > 0.01 || Math.abs(Qt.color(c.accent).g - Qt.color(want).g) > 0.01 || Math.abs(Qt.color(c.accent).b - Qt.color(want).b) > 0.01)
      fails.push(`${tag}: accent ${c.accent} is not ${gives ? "the slice" : "its own"} ${want}`);
  }

  // A muted widget's gradient is (1 - mutedMix) as strong, which over the
  // opaque background is its color mixed mutedMix toward it; the pulse's
  // mid-point is between
  function checkMutedGradient(fails, tag, rest, dim, mid) {
    if ((rest.gradient === null) !== (dim.gradient === null)) {
      fails.push(`${tag}: muted gradient ${root.part(dim.gradient)}, unmuted ${root.part(rest.gradient)}`);
      return;
    }
    if (rest.gradient === null)
      return;
    const want = rest.gradient.alpha * (1 - BarWidgetStyle.mutedMix);
    if (dim.gradient.part !== rest.gradient.part || Math.abs(dim.gradient.alpha - want) > 1e-6)
      fails.push(`${tag}: muted gradient ${root.part(dim.gradient)}, not ${rest.gradient.part}@${want}`);
    if (mid && Math.abs(mid.gradient.alpha - (rest.gradient.alpha + dim.gradient.alpha) / 2) > 1e-6)
      fails.push(`${tag}: pulse mid-point gradient ${root.part(mid.gradient)}`);
  }

  // A badge reads (3) where it sits, its text 4.5, and a fill gives it a ring
  function checkBadge(fails, tag, c, ctx) {
    if (ctx.override !== null && ctx.override !== undefined)
      return;
    const palette = ctx.bar.palette;
    const badge = BarWidgetStyle.badge(palette, c, ctx.accent);
    const backs = c.iconOnFill ? c.iconBack : c.iconBack.concat([BarWidgetStyle.over(palette.background, palette.background)]);
    if (!root.reads(backs, badge.fill, 3))
      fails.push(`${tag}: badge fill ${badge.fill} under 3 on ${backs}`);
    if (Utils.contrast(BarWidgetStyle.over(badge.fill, palette.background), badge.text) < 4.5)
      fails.push(`${tag}: badge text ${badge.text} under 4.5`);
    if (!Qt.colorEqual(badge.ring, c.iconOnFill ? c.iconBack[0] : "transparent"))
      fails.push(`${tag}: badge ring ${badge.ring}`);
  }

  // [tag, bar keys, widget state (JSON), light bar, accent, ring (a colors() key)]
  readonly property var badgeRows: [["filled, a dark accent on a light bar", '{"widgetStyle":"filled"}', "{}", true, "#458588", "fill"], ["split icon part", '{"widgetStyle":"split"}', '{"splits":true}', false, "#fabd2f", "iconFill"], ["tinted", '{"widgetStyle":"tinted"}', "{}", true, "#458588", ""], ["tinted, hovered", '{"widgetStyle":"tinted","hoverFill":true}', '{"hovered":true}', false, "#fb4934", "fill"]]

  function test_badge_data() {
    return root.badgeRows.map(r => ({
          "tag": r[0],
          "row": r
        }));
  }

  // On a fill a badge has a ring and reads on that alone, its hue kept
  function test_badge(data) {
    const r = data.row;
    const bar = Bars.bar(JSON.parse(r[1]), Bars.themeEnv(r[3] ? Bars.lightTheme : Bars.theme));
    const c = BarWidgetStyle.widgetColors(bar, r[4], "#282828", JSON.parse(r[2]));
    const b = BarWidgetStyle.badge(bar.palette, c, r[4]);
    verify(root.reads(r[5] ? c.iconBack : c.iconBack.concat([bar.palette.background]), b.fill, 3), "the fill reads");
    verify(!r[5] || !root.pole(b.fill), "its hue is kept");
    same(b.ring, r[5] ? c[r[5]] : "transparent", "the ring");
  }

  // Muted shows: some color of the widget differs from its unmuted self
  function differs(a, b, keys) {
    return keys.some(k => !Qt.colorEqual(a[k], b[k]));
  }

  // One widget case, at rest and muted, and the pulse's mid-point between
  // them: what must hold of it
  function widgetCase(fails, bar, tag, accent, own, widget, ctx) {
    const rest = BarWidgetStyle.widgetColors(bar, accent, own, widget);
    const dim = BarWidgetStyle.widgetColors(bar, accent, own, Object.assign({
      "muted": true
    }, widget));
    ctx.bar = bar;
    ctx.accent = accent;
    root.checkWidget(fails, tag, rest, false, ctx);
    root.checkWidget(fails, tag + " muted", dim, true, ctx);
    if (!root.differs(rest, dim, ["fill", "stroke", "indicator", "iconFill", "text", "icon"]))
      fails.push(`${tag}: muted looks as unmuted`);
    if (widget.level && Qt.color(rest.level).a > 0.35 + 1e-6)
      fails.push(`${tag}: level stronger than 35%`);
    const mid = BarWidgetStyle.mixColors(rest, dim, 0.5);
    root.checkMutedGradient(fails, tag, rest, dim, mid);
    if (!ctx.override)
      for (const [name, color, backs] of [["text", mid.text, mid.textBack], ["icon", mid.icon, mid.iconBack], ["headText", mid.headText, mid.iconBack], ["mark", mid.mark, mid.iconBack], ["graphic.line", mid.graphic.line, mid.iconBack], ["graphic.subcaption", mid.graphic.subcaption, mid.iconBack]])
        if (!root.reads(backs, color, BarWidgetStyle.mutedContrast))
          fails.push(`${tag}: pulse mid-point ${name} ${color} under 3 on ${backs}`);
  }

  function test_the_sweep_holds_for_every_widget() {
    const started = Date.now();
    const fails = [];
    let cases = 0;
    for (const [themeKey, theme] of root.themes) {
      const own = Bars.resolverOf(theme).call(null, "base00");
      const set = Bars.resolverOf(theme).call(null, "base0D");
      // The bar's text color set: on a subset (no level, one accent)
      for (const override of ["", "base0D"])
        for (const look of root.looks)
          for (const grouping of root.groupings)
            for (const [hoverFill, hovered] of root.hovers)
              for (const [gradient, auto] of root.gradients) {
                const bar = root.barOf(themeKey, theme, look, grouping, hoverFill, gradient, override);
                for (const split of look.split ? [false, true] : [false])
                  for (const level of override ? [false] : [false, true])
                    for (const accent of override ? [root.accents[0]] : root.accents) {
                      const tag = [themeKey, override ? "override" : "", look.key + (split ? "+split" : ""), grouping, hoverFill ? (hovered ? "hovered" : "hover") : "nohover", gradient ? (auto ? "auto" : "set") : "flat", level ? "level" : "", accent].join(" ");
                      cases += 1;
                      root.widgetCase(fails, bar, tag, accent, own, {
                        "splits": split,
                        "hovered": hovered,
                        "spot": 0.3,
                        "auto": auto,
                        "level": level
                      }, {
                        "gradient": gradient,
                        "auto": auto,
                        "override": override ? set : null
                      });
                    }
              }
    }
    console.info(`sweep: ${cases} widget cases in ${Date.now() - started} ms`);
    verify(fails.length === 0, `${fails.length} of ${cases} cases fail:\n` + fails.slice(0, 12).join("\n"));
  }

  // The same of a cell: every cell state, solid or not
  function checkCell(fails, tag, c, muted, state, ctx) {
    const floor = state === "empty" || (muted && !c.onFill) ? BarWidgetStyle.mutedContrast : 4.5;
    // plain's occupied and unmuted active text is the bar's text, as set
    const seen = c.back.map(b => BarWidgetStyle.over(c.content, b));
    if (ctx.override) {
      if (muted && !c.onFill && !c.back.every((b, i) => Utils.contrast(b, seen[i]) >= floor - 1e-6))
        fails.push(`${tag}: muted content under ${floor}`);
      return;
    }
    c.back.forEach((b, i) => {
      if (Utils.contrast(b, seen[i]) < floor - 1e-6)
        fails.push(`${tag}: content ${c.content} under ${floor} on ${b}`);
    });
    if (!c.onFill && root.pole(c.content))
      fails.push(`${tag}: content is a pole`);
    if (!Qt.colorEqual(c.hover, ctx.bar.palette.cellHover))
      fails.push(`${tag}: hover is not the palette's`);
  }

  function test_the_sweep_holds_for_every_cell() {
    const started = Date.now();
    const fails = [];
    let cases = 0;
    const keys = ["fill", "stroke", "indicator", "content"];
    for (const [themeKey, theme] of root.themes) {
      const resolve = Bars.resolverOf(theme);
      for (const override of ["", "base0D"])
        for (const look of root.looks)
          for (const grouping of ["separate", "merged"])
            for (const [hoverFill, hovered] of root.hovers)
              for (const [gradient, auto] of root.gradients) {
                const bar = root.barOf(themeKey, theme, look, grouping, hoverFill, gradient, override);
                for (const solid of [false, true])
                  for (const cellState of ["active", "occupied", "urgent", "empty"])
                    for (const accent of cellState === "empty" || override ? [root.accents[0]] : root.accents) {
                      const color = cellState === "empty" ? resolve("base03") : accent;
                      const ownColor = cellState === "empty" ? bar.palette.barText : resolve("base00");
                      const state = {
                        "hovered": hovered,
                        "spot": 0.3,
                        "auto": auto,
                        "solid": solid,
                        "group": grouping === "merged"
                      };
                      const tag = [themeKey, override ? "override" : "", look.key, grouping, hoverFill ? (hovered ? "hovered" : "hover") : "nohover", gradient ? (auto ? "auto" : "set") : "flat", solid ? "solid" : "own", cellState, accent].join(" ");
                      const rest = BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, state), color, ownColor, cellState);
                      const dim = BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, Object.assign({
                        "muted": true
                      }, state)), color, ownColor, cellState);
                      const ctx = {
                        "bar": bar,
                        "override": override ? resolve(override) : null
                      };
                      root.checkCell(fails, tag, rest, false, cellState, ctx);
                      root.checkCell(fails, tag + " muted", dim, true, cellState, ctx);
                      if (!root.differs(rest, dim, keys))
                        fails.push(`${tag}: muted looks as unmuted`);
                      const mid = BarWidgetStyle.mixColors(rest, dim, 0.5);
                      if (!ctx.override)
                        mid.back.forEach(b => {
                          if (Utils.contrast(b, BarWidgetStyle.over(mid.content, b)) < BarWidgetStyle.mutedContrast - 1e-6)
                            fails.push(`${tag}: pulse mid-point content ${mid.content} under 3 on ${b}`);
                        });
                      root.checkMutedGradient(fails, tag, rest, dim, mid);
                      // Under the text color, occupied plain text still differs from the active's
                      const active = BarWidgetStyle.cell(bar.look, bar.palette, BarWidgetStyle.state(bar.palette, state), color, ownColor, "active");
                      if (override && cellState === "occupied" && look.key === "plain" && !solid && Qt.colorEqual(rest.content, active.content))
                        fails.push(`${tag}: occupied reads as active`);
                      cases += 2;
                    }
              }
    }
    console.info(`sweep: ${cases} cell cases in ${Date.now() - started} ms`);
    verify(fails.length === 0, `${fails.length} of ${cases} cases fail:\n` + fails.slice(0, 12).join("\n"));
  }
}
