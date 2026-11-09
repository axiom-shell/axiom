pragma Singleton
import QtQuick

// A bar's widget style resolved once (`resolve`: barConfig.look): the
// shared BarStyle and the bar's own style merged, every "as drawn" rule
// applied, and the style's traits from one table (`table`). What a style
// is lives here alone: nothing else compares a widgetStyle name. No
// colors (BarWidgetStyle) and no geometry beyond what the look's own
// fields need (BarShapes).
QtObject {
  id: root

  // The traits of each widget style (BarStyle.widgetStyle's enum), and of
  // a Workspaces cell's solid box (`solid`). A trait that depends on the
  // look's other keys is a function of the look (traitsOf evaluates them):
  //   boxed           each widget sits on a box of its own: only these
  //                   styles have shapes, grouping and runs
  //   hasBox(look)    that box can chain in a powerline or hang from the
  //                   edge as a tab (split's badge has none)
  //   hoverFills      "Fill on hover" applies: a boxed style that isn't
  //                   filled already
  //   opaque(look)    a powerline segment's fill hides what's under it, so
  //                   the next starts square beneath its end cap
  //   cellOpaque      a cell's box hides what's under it (cells chained in
  //                   a powerline)
  //   boxedInRun      a widget or cell in a merged run still draws a box of
  //                   its own (split's: a widget that doesn't split, and a
  //                   cell; solid's)
  //   groupCell       a cell in a merged run draws no box: its color moves
  //                   to its content
  //   box             what a box of the style paints each part in ({ fill,
  //                   stroke, indicator, text, icon }): "color" (its own
  //                   color), "tint" (that at the look's tint), "unfilled"
  //                   (clear: its color cleared where it fills on hover),
  //                   "own" (what reads on its color: its content reads on
  //                   its own fill), "bar" (the bar's text), or null
  //                   (nothing); `keepsIcon`, the icon keeps its color under
  //                   the bar's text color (it carries the state). Null for
  //                   a style that draws parts apart instead (iconPart)
  //   iconPart        draws an icon part filled in its color and a label
  //                   apart (split: the label's fill is the look's
  //                   split.label)
  //   runTints        a merged run's strip of the bar gradient is a tint
  //                   (its labels'), under icon parts in their own slices
  //   colored         its widgets' own colors show at all: plain text tells
  //                   a cell's states apart by fading alone, and has
  //                   nothing for the bar gradient to color
  //   tints           its box is a see-through tint of its color (a box
  //                   at rest under another shows through it)
  //   line            draws a line along one side (underline)
  //   stroke          draws an outline (outline)
  //   gradientPart(look)  what of a widget's background takes the bar's
  //                   gradient ({ part, alpha }), or null: none
  //   autoContrast(look)  what an Auto color is seen against and how much
  //                   it must stand out ({ onRun, minContrast }): onRun,
  //                   a merged run's background instead of the bar; a
  //                   fill need only show (1.3), text, strokes and icons
  //                   must read (3)
  //   fallback        the style a widget that can't draw this one draws
  //                   in (split's, for a widget that doesn't split), or null
  readonly property var table: ({
      "filled": {
        "boxed": true,
        "hasBox": look => true,
        "hoverFills": false,
        "opaque": look => true,
        "cellOpaque": true,
        "boxedInRun": false,
        "groupCell": true,
        "box": {
          "fill": "color",
          "stroke": null,
          "indicator": null,
          "text": "own",
          "icon": "own",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": false,
        "line": false,
        "stroke": false,
        "gradientPart": look => root._part("fill", 1),
        "autoContrast": look => look.grouping === "merged" ? root._contrast(true, 3) : root._contrast(false, 1.3),
        "fallback": null
      },
      "tinted": {
        "boxed": true,
        "hasBox": look => true,
        "hoverFills": true,
        "opaque": look => false,
        "cellOpaque": false,
        "boxedInRun": false,
        "groupCell": true,
        "box": {
          "fill": "tint",
          "stroke": null,
          "indicator": null,
          "text": "color",
          "icon": "color",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": true,
        "line": false,
        "stroke": false,
        "gradientPart": look => root._part("fill", look.tint),
        "autoContrast": look => root._contrast(false, 3),
        "fallback": null
      },
      "outline": {
        "boxed": true,
        "hasBox": look => true,
        "hoverFills": true,
        "opaque": look => false,
        "cellOpaque": false,
        "boxedInRun": false,
        "groupCell": true,
        "box": {
          "fill": "unfilled",
          "stroke": "color",
          "indicator": null,
          "text": "color",
          "icon": "color",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": false,
        "line": false,
        "stroke": true,
        "gradientPart": look => root._part("stroke", 1),
        "autoContrast": look => root._contrast(false, 3),
        "fallback": null
      },
      // The icon part filled, the label apart: on a tint, a color of its
      // own or the bar. Split's color is its icon part's fill, and the
      // label's text too where the label sits on a tint of it or the bar.
      "split": {
        "boxed": true,
        "hasBox": look => look.split.icon !== "badge",
        "hoverFills": false,
        "opaque": look => look.split.label === "color",
        "cellOpaque": true,
        "boxedInRun": true,
        "groupCell": false,
        "box": null,
        "iconPart": true,
        "runTints": true,
        "colored": true,
        "tints": false,
        "line": false,
        "stroke": false,
        "gradientPart": look => root._part("iconFill", 1),
        "autoContrast": look => {
          const merged = look.grouping === "merged";
          return root._contrast(merged, merged || look.split.label === "color" ? 1.3 : 3);
        },
        "fallback": "filled"
      },
      "underline": {
        "boxed": false,
        "hasBox": look => false,
        "hoverFills": false,
        "opaque": look => false,
        "cellOpaque": false,
        "boxedInRun": false,
        "groupCell": false,
        "box": {
          "fill": null,
          "stroke": null,
          "indicator": "color",
          "text": "bar",
          "icon": "bar",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": false,
        "line": true,
        "stroke": false,
        "gradientPart": look => root._part("indicator", 1),
        "autoContrast": look => root._contrast(false, 3),
        "fallback": null
      },
      // Colored icons: the icon carries the state, the label the bar's text
      "accentText": {
        "boxed": false,
        "hasBox": look => false,
        "hoverFills": false,
        "opaque": look => false,
        "cellOpaque": false,
        "boxedInRun": false,
        "groupCell": false,
        "box": {
          "fill": null,
          "stroke": null,
          "indicator": null,
          "text": "bar",
          "icon": "color",
          "keepsIcon": true
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": false,
        "line": false,
        "stroke": false,
        "gradientPart": look => null,
        "autoContrast": look => root._contrast(false, 3),
        "fallback": null
      },
      "plain": {
        "boxed": false,
        "hasBox": look => false,
        "hoverFills": false,
        "opaque": look => false,
        "cellOpaque": false,
        "boxedInRun": false,
        "groupCell": false,
        "box": {
          "fill": null,
          "stroke": null,
          "indicator": null,
          "text": "bar",
          "icon": "bar",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": false,
        "tints": false,
        "line": false,
        "stroke": false,
        "gradientPart": look => null,
        "autoContrast": look => root._contrast(false, 3),
        "fallback": null
      },
      // A Workspaces cell's solid box (`solidBoxes`): filled whatever the
      // bar's style, its outline and line (where the bar draws them) in
      // its color too. Never a bar's style: its widget traits are a
      // filled box's.
      "solid": {
        "boxed": true,
        "hasBox": look => true,
        "hoverFills": false,
        "opaque": look => true,
        "cellOpaque": true,
        "boxedInRun": true,
        "groupCell": false,
        "box": {
          "fill": "color",
          "stroke": "color",
          "indicator": "color",
          "text": "own",
          "icon": "own",
          "keepsIcon": false
        },
        "iconPart": false,
        "runTints": false,
        "colored": true,
        "tints": false,
        "line": false,
        "stroke": false,
        "gradientPart": look => root._part("fill", 1),
        "autoContrast": look => root._contrast(false, 1.3),
        "fallback": null
      }
    })

  // A style's traits (table) for `look`, its functions evaluated: an
  // unknown style is filled's
  function traitsOf(name, look) {
    const t = root.table[name] ?? root.table.filled;
    return {
      "boxed": t.boxed,
      "hasBox": t.hasBox(look),
      "hoverFills": t.hoverFills,
      "opaque": t.opaque(look),
      "cellOpaque": t.cellOpaque,
      "boxedInRun": t.boxedInRun,
      "groupCell": t.groupCell,
      "box": t.box,
      "iconPart": t.iconPart,
      "runTints": t.runTints,
      "colored": t.colored,
      "tints": t.tints,
      "line": t.line,
      "stroke": t.stroke,
      "gradientPart": t.gradientPart(look),
      "autoContrast": t.autoContrast(look),
      "fallback": t.fallback
    };
  }

  // A Workspaces cell's traits on `look`: a solid box's (`solid`), else
  // the look's own
  function cellTraits(look, solid) {
    return solid ? root.traitsOf("solid", look) : look.traits;
  }

  // A bar's BarStyle values: its own style's (`own`), each key it leaves
  // null the shared one's (`section`, BarStyle.values), the shadow as flat
  // shadow / shadowColor / shadowSize
  function merge(section, own) {
    const values = {};
    for (const key in section) {
      if (key === "shadow")
        continue;
      values[key] = own[key] ?? section[key];
    }
    const shadow = own.shadow ?? {};
    values.shadow = shadow.enabled ?? section.shadow.enabled;
    values.shadowColor = shadow.color ?? section.shadow.color;
    values.shadowSize = shadow.size ?? section.shadow.size;
    return values;
  }

  // A bar's look (barConfig.look) from the shared style (`section`) and
  // its own (`own`, merge), on a bar of `bar`'s geometry ({ thickness,
  // innerPadding, innerGap (as scaled), radius (the interior radius, for a
  // look with no widget radius), far (its outer edge is at the far side:
  // a bottom or right bar) }, or null for the look alone, its geometry's
  // fields then null):
  //   values      the merged BarStyle values, as saved
  //   style       widgetStyle
  //   traits      its traits (traitsOf)
  //   radius      the widgets' corner radius
  //   textScale   the text size (%)
  //   tint        a tint's opacity (0-1)
  //   textColor   one text color for every widget (a name), "" for Auto
  //   hoverFill   "Fill on hover", as drawn: on, for a style it applies to
  //   outline     { width, stroke }: an outline's, or null
  //   line        { width, side, farSide (the side further from the bar's
  //               outer edge, in item coordinates) }: underline's, or null
  //   shape       { name (as drawn: rounded for an unboxed style, and for
  //               a separate split badge saved as a tab), ends,
  //               tabCorners, tabFillet (BarShapes.tabFillet: the bar
  //               fills it in, BarsConfig.enrichBarConfig; else 0) }
  //   grouping    as drawn: separate for unboxed styles, and a powerline
  //               of what can't chain (a badge, tabs)
  //   split       { icon, labelFill, label (the label's fill as drawn:
  //               a badge's none), labelColor (a name), divider, cap
  //               (BarShapes.dividerCap), room (BarShapes.splitRoom),
  //               badgePad }: an icon part's (split's), or null
  //   group       { color, strokeColor }: a merged run's (names)
  //   gradient    the bar gradient's colors (names, start to end), or
  //               null: none, or a style with no color of its own to show
  //               (`colored`: plain text)
  //   separators  { style (as drawn: none in a powerline, where widgets
  //               touch), color, thickness, gap }
  //   accentLine  { side, color, fade, width }, or null for none
  function resolve(section, own, bar) {
    const values = root.merge(section, own);
    const style = values.widgetStyle;
    const table = root.table[style] ?? root.table.filled;
    const thickness = bar?.thickness ?? null;
    const splitCap = BarShapes.dividerCap(values.widgetShape, values.splitDivider);
    const look = {
      "values": values,
      "style": style,
      "radius": values.widgetRadius ?? bar?.radius ?? null,
      "textScale": values.textScale,
      "tint": values.tintOpacity / 100,
      "textColor": values.widgetTextColor,
      "split": table.iconPart ? {
        "icon": values.splitIcon,
        "labelFill": values.splitLabelFill,
        "label": values.splitIcon === "badge" ? "none" : values.splitLabelFill,
        "labelColor": values.splitLabelColor,
        "divider": values.splitDivider,
        "cap": splitCap,
        "room": bar ? BarShapes.splitRoom(values.splitIcon, splitCap, thickness, bar.innerPadding, bar.innerGap * 1.5, bar.innerGap) : -1,
        "badgePad": bar?.innerGap ?? null
      } : null,
      "group": {
        "color": values.groupColor,
        "strokeColor": values.groupStrokeColor
      },
      "gradient": values.gradient && table.colored ? [values.gradientFrom].concat(values.gradientVia ? [values.gradientVia] : [], [values.gradientTo]) : null,
      "accentLine": values.accentLine !== "none" ? {
        "side": values.accentLine,
        "color": values.accentLineColor,
        "fade": values.accentLineFade,
        "width": values.accentLineWidth
      } : null
    };
    look.grouping = root._groupingOf(look, table);
    look.shape = {
      "name": table.boxed ? root._shapeOf(look, table) : "rounded",
      "ends": values.widgetEnds,
      "tabCorners": values.tabCorners,
      "tabFillet": 0
    };
    look.traits = root.traitsOf(style, look);
    look.hoverFill = values.hoverFill && look.traits.hoverFills;
    look.outline = look.traits.stroke ? {
      "width": values.outlineWidth,
      "stroke": values.outlineStroke
    } : null;
    look.line = look.traits.line ? {
      "width": values.lineWidth,
      "side": values.lineSide,
      "farSide": (values.lineSide === "inner") !== (bar?.far ?? false)
    } : null;
    look.separators = {
      "style": look.grouping === "powerline" ? "none" : values.separatorStyle,
      "color": values.separatorColor,
      "thickness": values.separatorThickness,
      "gap": values.separatorGap
    };
    return look;
  }

  // The look as `$bar.<key>` for a bar widget's options' x-showIf: its
  // BarStyle values, with shape and grouping as drawn
  function context(look) {
    const table = root.table[look.style] ?? root.table.filled;
    const drawn = Object.assign({}, look.values, {
      "widgetShape": root._shapeOf(look, table),
      "widgetGrouping": look.grouping
    });
    return Object.keys(drawn).filter(key => key !== "shadowColor" && key !== "shadowSize").reduce((context, key) => {
      context["$bar." + key] = drawn[key];
      return context;
    }, {});
  }

  // Grouping as drawn: a powerline draws as separate where there's
  // nothing to chain: an unboxed style, a split badge (no box), tabs
  // (each hangs from the edge; the option is hidden for them)
  function _groupingOf(look, table) {
    const grouping = look.values.widgetGrouping;
    if (!table.boxed)
      return "separate";
    if (grouping !== "powerline")
      return grouping;
    return !table.hasBox(look) || look.values.widgetShape === "tab" ? "separate" : "powerline";
  }

  // The shape as drawn of a boxed look: a separate split badge has no box
  // to hang from the edge, so a tab saved with it draws rounded (the
  // option is hidden there); a merged run of badges is one tab still
  function _shapeOf(look, table) {
    const shape = look.values.widgetShape;
    return !table.hasBox(look) && table.boxed && look.values.widgetGrouping !== "merged" && shape === "tab" ? "rounded" : shape;
  }

  function _part(part, alpha) {
    return {
      "part": part,
      "alpha": alpha
    };
  }

  function _contrast(onRun, minContrast) {
    return {
      "onRun": onRun,
      "minContrast": minContrast
    };
  }
}
