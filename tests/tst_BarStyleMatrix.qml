import QtQuick
import QtTest
import qs.components.methods
import "barstyle/Bars.js" as Bars
import "barstyle/Matrix.js" as Matrix

// The bar widget style system's geometry characterization of looks, cell
// shapes and outlines (the rest is in the dedicated tests), run through the helpers, and
// what they give recorded (barstyle/Matrix.js): main's behaviour before
// the style rework, plus its intended changes, each re-recorded in the
// commit that made it. The expected data is never edited by hand:
// otherwise only the adapters below change, to reach the same results
// through a new API. What colours draw is tst_BarWidgetStyle's sweep.
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

  // A bar as BarsConfig.enrichBarConfig makes it (BarEnrich, through the
  // Bars.js fixture): the raw look is the Bars section's style, the
  // geometry the bar's own. A pills bar's `endRoom` is its edge padding
  // and the border's stroke (BarEnds.tabEndRoom). The returned bar is what
  // the other adapters take.
  function enrich(raw, geo) {
    return Bars.bar(Object.assign({}, root.sectionOf(raw), {
      "thickness": geo.thickness,
      "innerPadding": geo.innerPadding,
      "innerGap": geo.innerGap,
      "widgetGap": geo.widgetGap,
      "edge": geo.location,
      "edgePadding": geo.endRoom - 1
    }));
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
    return [look.style, look.outline?.width ?? values.outlineWidth, look.outline?.stroke ?? values.outlineStroke, values.hoverFill, look.line?.width ?? values.lineWidth, look.line?.side ?? values.lineSide, look.textColor, look.shape.ends, look.shape.tabCorners, look.group.color, look.group.strokeColor, look.split?.icon ?? values.splitIcon, values.splitLabelFill, look.split?.labelColor ?? values.splitLabelColor, values.splitDivider, look.separators.color, look.separators.thickness, look.accentLine?.side ?? "none", look.accentLine?.color ?? values.accentLineColor, look.accentLine?.fade ?? values.accentLineFade, look.accentLine?.width ?? values.accentLineWidth];
  }

  // `$bar.<key>` for a bar widget's x-showIf (BarLook.context)
  function context(raw) {
    const context = BarLook.context(BarLook.resolve(root.sectionOf(raw), {}, null));
    return root.styleKeys.reduce((out, key) => {
      out["$bar." + key] = context["$bar." + key];
      return out;
    }, {});
  }

  function cellFlags(bar, solid) {
    const traits = BarLook.cellTraits(bar.look, solid);
    return [traits.cellOpaque, traits.boxedInRun];
  }

  // A cell's content across: its label (no app icons)
  function cellShape(bar, run, boxed, opaque, gap, cell, cells) {
    return BarCells.cellShape(bar, run, boxed, opaque, gap, cell, cells, WorkspaceCells.contentSize(bar.thickness, bar.fontSize, false));
  }

  function cellRoom(bar, run, boxed, cell, cells) {
    return BarCells.cellRoom(bar, run, boxed, cell, cells, WorkspaceCells.contentSize(bar.thickness, bar.fontSize, false));
  }

  function runDraws(bar, run) {
    return BarCells.runDraws(bar, run);
  }

  function cellMargins(first, last, vertical) {
    return BarCells.cellMargins(first, last, vertical);
  }

  // The outline family for one outline `o` ({ length, across, radius,
  // startCap, endCap, vertical, seamStart, seamEnd, tab, openStart,
  // openEnd }) at `inset`
  function outlines(o, inset) {
    const spec = BarShapes.outline(o);
    return {
      "fill": BarOutlines.path(spec, 0, false),
      "stroke": BarOutlines.path(spec, inset, true),
      "offset": BarOutlines.offsetPath(spec, inset * 3, o.seamStart ? 0 : inset * 3, o.seamEnd ? 0 : inset * 3),
      "dash": BarOutlines.dashPath(spec, inset),
      "marks": BarOutlines.marks(spec, inset),
      "fillets": BarOutlines.fillets(spec, inset)
    };
  }

  function tab(radius, thickness, fillet, outerStart, limits) {
    return BarTabs.tab(radius, thickness, fillet, outerStart, limits);
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

  function groups() {
    return {
      "looks": root.lookCases(),
      "cellShapes": root.cellShapeCases(),
      "outlines": root.outlineCases()
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
