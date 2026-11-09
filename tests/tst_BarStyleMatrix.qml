import QtQuick
import QtTest
import qs.components.methods
import "barstyle/Matrix.js" as Matrix

// The bar widget style system's characterization: every widget style,
// grouping, shape, split, Fill on hover, gradient and cell state run
// through the style helpers, and what they give recorded once
// (barstyle/Matrix.js) from the code before the style rework. The
// expected data is never edited: only the adapters below change, to reach
// the same results through a new API. Colour the text by state
// (textByState) is left out: the rework changes it on purpose.
TestCase {
  id: root

  name: "BarStyleMatrix"

  // True only while recording the expected data (never committed true):
  // each case is logged as `MATRIX <group> <key>\t<value>` instead of
  // compared
  readonly property bool recording: false

  RepoFiles {
    id: files
  }

  // Theme stand-ins: what Theme.resolveColor gives for a name
  readonly property var theme: ({
      "foreground": "#ebdbb2",
      "background": "#282828",
      "backgroundAlt": "#3c3836",
      "accent": "#83a598",
      "accentAlt": "#d3869b",
      "base00": "#282828",
      "base03": "#665c54",
      "base0B": "#b8bb26",
      "base0D": "#458588",
      "warning": "#fabd2f",
      "error": "#fb4934"
    })
  // Widget.radius's stand-in, for a look with no widgetRadius
  readonly property int widgetRadius: 8

  function resolve(name) {
    return Qt.color(root.theme[name] ?? name);
  }

  // A BarStyle look (lookOf's flat keys, shadow flat), the schema's
  // defaults with `over` on top
  function rawLook(over) {
    return Object.assign({
      "textScale": 100,
      "widgetRadius": null,
      "widgetStyle": "filled",
      "splitIcon": "joined",
      "splitLabelFill": "tint",
      "tintOpacity": 20,
      "splitLabelColor": "backgroundAlt",
      "splitDivider": "match",
      "outlineWidth": 2,
      "outlineStroke": "solid",
      "hoverFill": false,
      "lineWidth": 2,
      "lineSide": "inner",
      "widgetShape": "rounded",
      "widgetGrouping": "separate",
      "tabCorners": "square",
      "widgetEnds": "shaped",
      "groupColor": "backgroundAlt",
      "groupStrokeColor": "accent",
      "widgetTextColor": "",
      "gradient": false,
      "gradientFrom": "accent",
      "gradientTo": "accentAlt",
      "gradientVia": "",
      "separatorStyle": "none",
      "separatorColor": "base03",
      "separatorThickness": 2,
      "separatorGap": 2,
      "accentLine": "none",
      "accentLineColor": "accent",
      "accentLineFade": "",
      "accentLineWidth": 2,
      "shadow": false,
      "shadowColor": "",
      "shadowSize": 12
    }, over);
  }

  // The bar's geometry beside its look
  function geometry(over) {
    return Object.assign({
      "thickness": 26,
      "innerPadding": 6,
      "innerGap": 4,
      "widgetGap": 6,
      "location": "top",
      // BarEnds.tabEndRoom's result for the bar
      "endRoom": 5
    }, over);
  }

  // ---- Adapters: the only part of this file a later stage changes ----

  // The shared BarStyle a raw look stands for (its shadow an object)
  function sectionOf(raw) {
    const section = Object.assign({}, raw, {
      "shadow": {
        "enabled": raw.shadow,
        "color": raw.shadowColor,
        "size": raw.shadowSize
      }
    });
    delete section.shadowColor;
    delete section.shadowSize;
    return section;
  }

  // A bar's look as enrichBarConfig resolves it (a pure copy of its look
  // block: BarsConfig needs Theme and the config). The returned bar is
  // what the other adapters take.
  function enrich(raw, geo) {
    const thickness = geo.thickness;
    const scale = thickness / 26;
    const innerPadding = Math.round(geo.innerPadding * scale);
    const innerGap = Math.round(geo.innerGap * scale);
    const far = geo.location === "right" || geo.location === "bottom";
    const look = BarLook.resolve(root.sectionOf(raw), {}, {
      "thickness": thickness,
      "innerPadding": innerPadding,
      "innerGap": innerGap,
      "radius": root.widgetRadius,
      "far": far
    });
    const separators = look.separators;
    const groupSpacing = look.grouping === "powerline" ? 0 : separators.style !== "none" ? BarLayout.dividerGap(separators.style, separators.thickness, thickness, separators.gap) : geo.widgetGap;
    const bar = {
      "thickness": thickness,
      "innerPadding": innerPadding,
      "innerGap": innerGap,
      "groupSpacing": groupSpacing,
      "radius": look.radius,
      "right": geo.location === "right",
      "bottom": geo.location === "bottom",
      "vertical": geo.location === "left" || geo.location === "right",
      "look": look,
      "splitRoom": look.split ? look.split.room : -1
    };
    look.shape.tabFillet = BarShapes.tabFillet(bar.radius, thickness, look.shape.tabCorners, groupSpacing, geo.endRoom);
    return bar;
  }

  // What the matrix records of an enriched bar, by the old flat names. A
  // split value off split (where the look has no split) is what main
  // derived from the saved values there.
  function derived(bar) {
    const look = bar.look;
    return {
      "boxed": look.traits.boxed,
      "shape": look.shape.name,
      "grouping": look.grouping,
      "splitCap": look.split ? look.split.cap : BarShapes.dividerCap(look.values.widgetShape, look.values.splitDivider),
      "splitRoom": bar.splitRoom,
      "badgePad": look.split ? look.split.badgePad : bar.innerGap,
      "tint": look.tint,
      "gradient": look.gradient,
      "separators": look.separators.style,
      "groupSpacing": bar.groupSpacing,
      "tabFillet": look.shape.tabFillet,
      "radius": bar.radius,
      "opaque": look.traits.opaque,
      "autoContrast": [look.traits.autoContrast.onRun, look.traits.autoContrast.minContrast]
    };
  }

  // Every other style key of an enriched bar, by the old flat names (a
  // part the look's style doesn't draw, as saved)
  function passed(bar) {
    const look = bar.look, values = look.values;
    return [look.style, look.outline?.width ?? values.outlineWidth, look.outline?.stroke ?? values.outlineStroke, values.hoverFill, look.line?.width ?? values.lineWidth, look.line?.side ?? values.lineSide, look.textColor, look.shape.ends, look.shape.tabCorners, look.group.color, look.group.strokeColor, look.split?.icon ?? values.splitIcon, look.split?.labelFill ?? values.splitLabelFill, look.split?.labelColor ?? values.splitLabelColor, look.split?.divider ?? values.splitDivider, look.separators.color, look.separators.thickness, look.accentLine?.side ?? "none", look.accentLine?.color ?? values.accentLineColor, look.accentLine?.fade ?? values.accentLineFade, look.accentLine?.width ?? values.accentLineWidth];
  }

  // `$bar.<key>` for a bar widget's x-showIf (BarLook.context)
  function context(raw) {
    const context = BarLook.context(BarLook.resolve(root.sectionOf(raw), {}, null));
    return root.styleKeys.reduce((out, key) => {
      out["$bar." + key] = context["$bar." + key];
      return out;
    }, {});
  }

  // The bar's palette (enrichBarConfig's)
  function palette(bar) {
    return BarWidgetStyle.palette(bar.look, name => root.resolve(name), root.resolve("foreground"), root.resolve("background"));
  }

  // A widget's colors (BarsConfig.widgetColors)
  function widgetColors(bar, accent, foregroundName, widget) {
    const palette = root.palette(bar);
    return BarWidgetStyle.colors(bar.look, palette, BarWidgetStyle.state(palette, {
      "splits": widget?.splits,
      "hovered": widget?.hovered,
      "spot": widget?.spot,
      "auto": widget?.auto,
      "group": bar.look.grouping === "merged"
    }), accent, root.resolve(foregroundName));
  }

  // A cell's colors (BarsConfig.cellColors)
  function cellColors(bar, color, own, state, cell) {
    const palette = root.palette(bar);
    return BarWidgetStyle.cell(bar.look, palette, BarWidgetStyle.state(palette, {
      "hovered": cell?.hovered,
      "spot": cell?.spot,
      "auto": (cell?.spot ?? -1) >= 0,
      "solid": cell?.solid,
      "group": cell?.onBar === true && bar.look.grouping === "merged"
    }), color, own, state);
  }

  // A merged run's own background (BarsConfig.groupColors)
  function groupColors(bar, spot) {
    return BarWidgetStyle.runColors(bar.look, root.palette(bar), spot);
  }

  function cellFlags(bar, solid) {
    const traits = BarLook.cellTraits(bar.look, solid);
    return [traits.cellOpaque, traits.boxedInRun];
  }

  function segment(shape, ends, grouping, opaque, index, count, across) {
    return BarShapes.segment(shape, ends, grouping, opaque, index, count, across);
  }

  function cellShape(bar, run, boxed, opaque, gap, cell, cells) {
    return BarShapes.cellShape(bar, run, boxed, opaque, gap, cell, cells);
  }

  function cellRoom(bar, run, boxed, cell, cells) {
    return BarShapes.cellRoom(bar, run, boxed, cell, cells);
  }

  function runDraws(bar, run) {
    return BarShapes.runDraws(bar, run);
  }

  function cellMargins(first, last, vertical) {
    return BarShapes.cellMargins(first, last, vertical);
  }

  // The outline family for one outline `o` ({ length, across, radius,
  // startCap, endCap, vertical, seamStart, seamEnd, tab, openStart,
  // openEnd }) at `inset`
  function outlines(o, inset) {
    return {
      "fill": BarShapes.path(o.length, o.across, o.radius, o.startCap, o.endCap, o.vertical, 0, o.seamStart, o.seamEnd, o.tab, false, o.openStart, o.openEnd),
      "stroke": BarShapes.path(o.length, o.across, o.radius, o.startCap, o.endCap, o.vertical, inset, o.seamStart, o.seamEnd, o.tab, true, o.openStart, o.openEnd),
      "offset": BarShapes.offsetPath(o.length, o.across, o.radius, o.startCap, o.endCap, o.vertical, inset * 3, o.seamStart ? 0 : inset * 3, o.seamEnd ? 0 : inset * 3, o.tab, o.openStart, o.openEnd),
      "dash": BarShapes.dashPath(o.length, o.across, o.radius, o.startCap, o.endCap, o.vertical, inset, o.seamStart, o.seamEnd, o.tab, o.openStart, o.openEnd),
      "marks": BarShapes.marks(o.length, o.across, o.radius, o.startCap, o.endCap, o.vertical, inset, o.seamStart, o.seamEnd, o.tab, o.openStart, o.openEnd),
      "fillets": BarShapes.fillets(o.length, o.across, o.startCap, o.endCap, o.vertical, inset, o.tab, o.openStart, o.openEnd)
    };
  }

  function tab(radius, thickness, fillet, outerStart, limits) {
    return BarShapes.tab(radius, thickness, fillet, outerStart, limits);
  }

  function tabLimits(start, end, bounds) {
    return BarShapes.tabLimits(start, end, bounds);
  }

  function contains(u, v, length, across, startCap, endCap) {
    return BarShapes.contains(u, v, length, across, startCap, endCap);
  }

  // ---- Inputs ----

  // The BarStyle keys, from the built schema
  property var styleKeys: []

  function initTestCase() {
    root.styleKeys = Object.keys(files.json("qml/config/json/config.schema.json").definitions.BarStyle.properties);
  }

  readonly property var styles: ["filled", "tinted", "outline", "split", "underline", "accentText", "plain"]
  // Split's icon part and label fill, as cases of their own
  readonly property var splitKinds: [["joined", "tint"], ["joined", "color"], ["joined", "none"], ["badge", "tint"], ["badge", "color"]]
  // A shape and its ends: only slant and arrow read the ends
  readonly property var shapeEnds: [["rounded", "shaped"], ["capsule", "shaped"], ["slant", "shaped"], ["slant", "pointed"], ["slant", "rounded"], ["arrow", "shaped"], ["arrow", "pointed"], ["arrow", "rounded"], ["tab", "shaped"]]

  // Each style, split as each of splitKinds: [key, raw over]
  function styleLooks() {
    return [].concat(...root.styles.map(style => style === "split" ? root.splitKinds.map(k => [`split.${k[0]}.${k[1]}`,
          {
            "widgetStyle": "split",
            "splitIcon": k[0],
            "splitLabelFill": k[1]
          }
        ]) : [[style,
          {
            "widgetStyle": style
          }
        ]]));
  }

  function hex(c) {
    if (c === "transparent")
      return "T";
    const q = Qt.color(c);
    return [q.a, q.r, q.g, q.b].map(x => Math.round(x * 255).toString(16).padStart(2, "0")).join("");
  }

  function part(g) {
    return g ? `${g.part}@${g.alpha}` : "-";
  }

  // Widget colors: fill stroke indicator text icon iconFill gradient
  function colorsRow(c) {
    return [root.hex(c.fill), root.hex(c.stroke), root.hex(c.indicator), root.hex(c.text), root.hex(c.icon), root.hex(c.iconFill), root.part(c.gradient)].join(" ");
  }

  // Cell colors: fill stroke indicator content showsHover gradient
  function cellRow(c) {
    return [root.hex(c.fill), root.hex(c.stroke), root.hex(c.indicator), root.hex(c.content), c.showsHover ? 1 : 0, root.part(c.gradient)].join(" ");
  }

  // Gradient and override cases: [key, raw over, widget over]
  readonly property var gradientCases: [["g0",
      {},
      {}
    ], ["g1-nospot",
      {
        "gradient": true
      },
      {}
    ], ["g1-set",
      {
        "gradient": true
      },
      {
        "spot": 0.3
      }
    ], ["g1-auto",
      {
        "gradient": true
      },
      {
        "spot": 0.3,
        "auto": true
      }
    ]]
  readonly property var hoverCases: [["h00", false, false], ["h01", false, true], ["h10", true, false], ["h11", true, true]]

  function colorCases() {
    const out = {};
    for (const [styleKey, styleOver] of root.styleLooks())
      for (const grouping of ["separate", "merged"])
        for (const [gKey, gOver, gWidget] of root.gradientCases)
          for (const [hKey, hoverFill, hovered] of root.hoverCases)
            for (const textColor of ["", "base0D"])
              for (const splits of styleOver.widgetStyle === "split" ? [false, true] : [false]) {
                const raw = root.rawLook(Object.assign({
                  "widgetGrouping": grouping,
                  "hoverFill": hoverFill,
                  "widgetTextColor": textColor
                }, styleOver, gOver));
                const bar = root.enrich(raw, root.geometry({}));
                const widget = Object.assign({
                  "hovered": hovered,
                  "splits": splits
                }, gWidget);
                const key = [styleKey, grouping, gKey, hKey, textColor ? "ovr" : "auto", splits ? "splits" : "whole"].join("/");
                out[key] = root.colorsRow(root.widgetColors(bar, Qt.color("#fb4934"), "base00", widget));
              }
    // A tab bar's grouping as drawn, and a light accent, on a few looks
    for (const [styleKey, styleOver] of root.styleLooks())
      for (const grouping of ["merged", "powerline"]) {
        const raw = root.rawLook(Object.assign({
          "widgetGrouping": grouping,
          "widgetShape": "tab"
        }, styleOver));
        const bar = root.enrich(raw, root.geometry({}));
        out[`${styleKey}/tab/${grouping}/light`] = root.colorsRow(root.widgetColors(bar, Qt.color("#fabd2f"), "base00", {
          "splits": true
        }));
      }
    return out;
  }

  readonly property var cellStates: [["active", "#83a598"], ["occupied", "#b8bb26"], ["urgent", "#fb4934"], ["empty", "#665c54"]]

  function cellCases() {
    const out = {};
    const groupCases = [["separate", true], ["merged", true], ["merged", false]];
    const gradients = [["g0", false, -1], ["g1-nospot", true, -1], ["g1-spot", true, 0.3]];
    const hovers = [["h00", false, false], ["h10", true, false], ["h11", true, true]];
    for (const style of root.styles)
      for (const solid of [false, true])
        for (const [grouping, onBar] of groupCases)
          for (const [gKey, gradient, spot] of gradients)
            for (const [hKey, hoverFill, hovered] of hovers)
              for (const [state, color] of root.cellStates)
                for (const textColor of gKey === "g0" && hKey === "h00" ? ["", "base0D"] : [""]) {
                  const bar = root.enrich(root.rawLook({
                    "widgetStyle": style,
                    "widgetGrouping": grouping,
                    "gradient": gradient,
                    "hoverFill": hoverFill,
                    "widgetTextColor": textColor
                  }), root.geometry({}));
                  const own = state === "empty" ? root.resolve("foreground") : root.resolve("base00");
                  const key = [style, solid ? "solid" : "own", grouping, onBar ? "onBar" : "popout", gKey, hKey, state, textColor ? "ovr" : "auto"].join("/");
                  out[key] = root.cellRow(root.cellColors(bar, Qt.color(color), own, state, {
                    "hovered": hovered,
                    "spot": spot,
                    "solid": solid,
                    "onBar": onBar
                  }));
                }
    return out;
  }

  function runCases() {
    const out = {};
    for (const [styleKey, styleOver] of root.styleLooks())
      for (const [gKey, gradient, spot] of [["g0", false, -1], ["g1-nospot", true, -1], ["g1-spot", true, 0.5]])
        for (const textColor of ["", "base0D"]) {
          const bar = root.enrich(root.rawLook(Object.assign({
            "widgetGrouping": "merged",
            "gradient": gradient,
            "widgetTextColor": textColor
          }, styleOver)), root.geometry({}));
          out[[styleKey, gKey, textColor ? "ovr" : "auto"].join("/")] = root.colorsRow(root.groupColors(bar, spot));
        }
    return out;
  }

  function lookCases() {
    const out = {};
    const add = (key, over, geo) => {
      const raw = root.rawLook(over);
      const bar = root.enrich(raw, root.geometry(geo));
      const ctx = root.context(raw);
      const changed = Object.keys(ctx).filter(k => ctx[k] !== raw[k.slice(5)]).sort().reduce((m, k) => {
        m[k] = ctx[k];
        return m;
      }, {});
      out[key] = JSON.stringify([root.derived(bar), changed, root.cellFlags(bar, false), root.cellFlags(bar, true)]);
    };
    for (const [styleKey, styleOver] of root.styleLooks())
      for (const grouping of ["separate", "merged", "powerline"])
        for (const [shape, ends] of root.shapeEnds)
          add([styleKey, grouping, shape, ends].join("/"), Object.assign({
            "widgetGrouping": grouping,
            "widgetShape": shape,
            "widgetEnds": ends
          }, styleOver), {});
    for (const [styleKey, styleOver] of root.styleLooks()) {
      for (const grouping of ["separate", "merged"])
        add([styleKey, grouping, "tab", "flared"].join("/"), Object.assign({
          "widgetGrouping": grouping,
          "widgetShape": "tab",
          "tabCorners": "flared"
        }, styleOver), {});
      add([styleKey, "gradient"].join("/"), Object.assign({
        "gradient": true
      }, styleOver), {});
      add([styleKey, "gradient-via"].join("/"), Object.assign({
        "gradient": true,
        "gradientVia": "base0B"
      }, styleOver), {});
      for (const separator of ["line", "dot", "slash", "chevron"])
        for (const grouping of ["separate", "powerline"])
          add([styleKey, "separator", separator, grouping].join("/"), Object.assign({
            "separatorStyle": separator,
            "separatorThickness": 3,
            "separatorGap": 4,
            "widgetGrouping": grouping
          }, styleOver), {});
      for (const divider of ["match", "straight", "slant", "arrow", "curve"])
        for (const shape of ["rounded", "slant", "arrow"])
          add([styleKey, "divider", divider, shape].join("/"), Object.assign({
            "splitDivider": divider,
            "widgetShape": shape
          }, styleOver), {});
      add([styleKey, "thick-radius"].join("/"), Object.assign({
        "widgetRadius": 14,
        "tintOpacity": 45,
        "widgetShape": "tab",
        "tabCorners": "flared"
      }, styleOver), {
        "thickness": 40,
        "widgetGap": 20,
        "endRoom": 30
      });
    }
    // Every other key passed through: one look with every key set
    const custom = {
      "widgetStyle": "outline",
      "outlineWidth": 3,
      "outlineStroke": "dashed",
      "hoverFill": true,
      "lineWidth": 4,
      "lineSide": "outer",
      "widgetTextColor": "base0D",
      "widgetEnds": "pointed",
      "tabCorners": "flared",
      "groupColor": "base03",
      "groupStrokeColor": "base0B",
      "splitIcon": "badge",
      "splitLabelFill": "color",
      "splitLabelColor": "base0D",
      "splitDivider": "curve",
      "separatorColor": "base0B",
      "separatorThickness": 4,
      "accentLine": "inner",
      "accentLineColor": "base0B",
      "accentLineFade": "base0D",
      "accentLineWidth": 3
    };
    for (const style of root.styles) {
      const bar = root.enrich(root.rawLook(Object.assign({}, custom, {
        "widgetStyle": style
      })), root.geometry({}));
      out[`passed/${style}`] = JSON.stringify(root.passed(bar));
    }
    return out;
  }

  function segmentRow(s) {
    return JSON.stringify([s.startCap, s.shownStart, s.endCap, s.levelStartCap, s.levelEndCap, s.back, s.lead, s.trail, s.seamStart, s.seamEnd]);
  }

  function segmentCases() {
    const out = {};
    for (const [shape, ends] of root.shapeEnds)
      for (const grouping of ["separate", "merged", "powerline"])
        for (const opaque of [false, true])
          for (let count = 1; count <= 3; count++)
            for (let index = 0; index < count; index++)
              out[[shape, ends, grouping, opaque ? "opaque" : "clear", `${index}of${count}`].join("/")] = root.segmentRow(root.segment(shape, ends, grouping, opaque, index, count, 26));
    return out;
  }

  function cellShapeCases() {
    const out = {};
    const runs = [["alone", null], ["first",
        {
          "drawn": {
            "index": 0,
            "count": 1
          },
          "sized": {
            "index": 0,
            "count": 1
          },
          "tabLimits": [null, null],
          "reachStart": 0,
          "reachEnd": 0
        }
      ], ["middle",
        {
          "drawn": {
            "index": 1,
            "count": 3
          },
          "sized": {
            "index": 1,
            "count": 3
          },
          "tabLimits": [
            {
              "gap": 2,
              "radius": 6
            },
            null],
          "reachStart": 3,
          "reachEnd": 0
        }
      ]];
    for (const [shape, ends] of root.shapeEnds)
      for (const grouping of ["separate", "merged", "powerline"])
        for (const [corners, location] of shape === "tab" ? [["square", "top"], ["flared", "top"], ["flared", "bottom"], ["flared", "left"], ["flared", "right"]] : [["square", "top"]])
          for (const [runKey, run] of runs)
            for (const [boxed, opaque] of [[false, false], [true, true]]) {
              const geo = root.geometry({
                "location": location,
                "widgetGap": 8
              });
              const bar = root.enrich(root.rawLook({
                "widgetStyle": "filled",
                "widgetShape": shape,
                "widgetEnds": ends,
                "widgetGrouping": grouping,
                "tabCorners": corners
              }), geo);
              const first = root.cellShape(bar, run, boxed, opaque, 4, 0, 2);
              const second = root.cellShape(bar, run, boxed, opaque, 4, 1, 2);
              const key = [shape, ends, grouping, corners, location, runKey, boxed ? "boxed" : "bare"].join("/");
              out[key] = JSON.stringify({
                "shapes": [first, second].map(s => [JSON.parse(root.segmentRow(Object.assign({
                      "levelStartCap": null,
                      "levelEndCap": null
                    }, s.segment))), s.tab, s.reachStart, s.reachEnd, s.drawStart, s.drawEnd]),
                "rooms": [root.cellRoom(bar, run, boxed, 0, 2), root.cellRoom(bar, run, boxed, 1, 2)],
                "margins": root.cellMargins(first, second, bar.vertical),
                "draws": root.runDraws(bar, run)
              });
            }
    return out;
  }

  readonly property var capPairs: [["round", "round"], ["capsule", "capsule"], ["slant", "slant"], ["arrowIn", "arrowOut"], ["arrowOut", "arrowOut"], ["roundIn", "roundOut"], ["flat", "curve"], ["slant", "flat"], ["flat", "roundOut"]]

  function outlineCases() {
    const out = {};
    const base = (caps, size) => ({
          "length": size[0],
          "across": size[1],
          "radius": size[2],
          "startCap": caps[0],
          "endCap": caps[1],
          "vertical": false,
          "seamStart": false,
          "seamEnd": false,
          "tab": null,
          "openStart": false,
          "openEnd": false
        });
    const variants = [["plain",
        {}
      ], ["vertical",
        {
          "vertical": true
        }
      ], ["seamStart",
        {
          "seamStart": true
        }
      ], ["seamEnd",
        {
          "seamEnd": true
        }
      ], ["openStart",
        {
          "openStart": true
        }
      ], ["openEnd",
        {
          "openEnd": true
        }
      ], ["openBoth",
        {
          "openStart": true,
          "openEnd": true
        }
      ]];
    for (const caps of root.capPairs) {
      for (const [vKey, over] of variants)
        out[[caps.join("-"), "80x26", vKey].join("/")] = JSON.stringify(root.outlines(Object.assign(base(caps, [80, 26, 8]), over), 1));
      out[[caps.join("-"), "30x16", "plain"].join("/")] = JSON.stringify(root.outlines(base(caps, [30, 16, 12]), 2));
    }
    const tabs = [["square-top", root.tab(8, 26, 0, true, [null, null])], ["flared-bottom", root.tab(8, 26, 4, false, [null, null])], ["flared-corner", root.tab(8, 26, 4, true, [
          {
            "gap": 1,
            "radius": 10
          },
          null])]];
    for (const caps of [["tab", "tab"], ["tab", "flat"], ["flat", "tab"], ["tab", "curve"]])
      for (const [tKey, t] of tabs)
        for (const [vKey, over] of [["plain",
            {}
          ], ["openEnd",
            {
              "openEnd": true
            }
          ], ["vertical",
            {
              "vertical": true
            }
          ]])
          out[[caps.join("-"), tKey, vKey].join("/")] = JSON.stringify(root.outlines(Object.assign(base(caps, [80, 26, 8]), {
            "tab": t
          }, over), 1));
    return out;
  }

  function tabCases() {
    const out = {};
    for (const radius of [0, 8, 20])
      for (const fillet of [0, 4])
        for (const outerStart of [true, false])
          for (const [lKey, limits] of [["none", [null, null]], ["start", [
                {
                  "gap": 2,
                  "radius": 8
                },
                null]], ["both-far", [
                {
                  "gap": 12,
                  "radius": 8
                },
                {
                  "gap": 0,
                  "radius": 8
                }
              ]]])
            out[["tab", radius, fillet, outerStart, lKey].join("/")] = JSON.stringify(root.tab(radius, 26, fillet, outerStart, limits));
    const bounds = [
      {
        "start": 0,
        "end": 300,
        "startRadius": 10,
        "endRadius": 6
      }
    ];
    for (const [start, end] of [[2, 40], [20, 60], [250, 296], [120, 160], [310, 330]])
      out[["limits", start, end].join("/")] = JSON.stringify(root.tabLimits(start, end, bounds));
    out["limits/none"] = JSON.stringify(root.tabLimits(2, 40, null));
    return out;
  }

  function containsCases() {
    const out = {};
    const us = [0, 1, 3, 6, 10, 20, 40, 60, 70, 74, 77, 79, 80];
    const vs = [0, 3, 7, 13, 19, 23, 26];
    for (const caps of root.capPairs.concat([["tab", "tab"], ["curve", "curve"], ["arrowIn", "arrowIn"]]))
      out[caps.join("-")] = vs.map(v => us.map(u => root.contains(u, v, 80, 26, caps[0], caps[1]) ? "1" : "0").join("")).join(" ");
    return out;
  }

  function groups() {
    return {
      "colors": root.colorCases(),
      "cells": root.cellCases(),
      "runs": root.runCases(),
      "looks": root.lookCases(),
      "segments": root.segmentCases(),
      "cellShapes": root.cellShapeCases(),
      "outlines": root.outlineCases(),
      "tabs": root.tabCases(),
      "contains": root.containsCases()
    };
  }

  function test_context_keys_are_the_bar_styles() {
    compare(Object.keys(root.context(root.rawLook({}))).sort().join(","), root.styleKeys.map(k => "$bar." + k).sort().join(","));
  }

  function test_matrix() {
    const all = root.groups();
    if (root.recording) {
      for (const group in all)
        for (const key in all[group])
          console.log(`MATRIX ${group} ${key}\t${all[group][key]}`);
      skip("recording");
    }
    const bad = [];
    for (const group in all) {
      const expected = Matrix.expected[group];
      verify(expected !== undefined, `no expected ${group}`);
      const keys = Object.keys(all[group]);
      compare(keys.length, Object.keys(expected).length, `${group}: case count`);
      for (const key of keys)
        if (all[group][key] !== expected[key])
          bad.push(`${group} ${key}\n  got      ${all[group][key]}\n  expected ${expected[key]}`);
    }
    verify(bad.length === 0, `${bad.length} cases differ:\n` + bad.slice(0, 20).join("\n"));
  }
}
