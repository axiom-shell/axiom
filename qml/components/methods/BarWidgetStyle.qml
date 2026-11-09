pragma Singleton
import QtQuick

// What a bar widget draws in, by its bar's widget style: { fill, stroke,
// indicator, text, icon, iconFill }. `accent` is the widget's own color for its state
// (its background while filled), `own` its text color (picked to read on
// that background). `style` is the bar's, colors resolved by the caller:
//   fill      the bar's widgetStyle
//   barText   what reads on the bar itself
//   override  the bar's text color, replacing the automatic one, or null
//   tint      a tinted fill's opacity (0-1)
//   group     the shared background of a merged run the widget sits in,
//             or null; the run's own background is colors(style, group)
//   splits    the widget shows an icon part and a label apart (split:
//             an icon or a lead graphic, and a label); without, a split
//             bar draws it filled
//   splitIcon split's icon part: joined (one box cut in two) or badge
//   labelFill split's label part: tint, color or none
//   labelColor that color
//   hoverFill the bar's "Fill on hover"
//   hovered   the pointer is over the widget (its hit area): a tinted or
//             outlined widget then draws as filled (fillsOnHover)
//   gradient  the bar gradient's color where the widget sits (its middle),
//             or null: no gradient (or no place on a bar, a preview)
//   auto      `accent` is the widget's Auto own color (its `accent` role
//             left empty, BarsConfig.withAutoColors): only that gives way
//             to the bar's gradient. A color set on the widget and its
//             state colors keep theirs.
//   run       the style is a merged run's own background (groupColors)
// `iconFill` is split's icon part (its icon or badge), else transparent.
// The result's `gradient` says what of the background draws the bar's
// gradient (gradientPart), else null.
QtObject {
  id: root

  function colors(style, accent, own) {
    const graded = (style.gradient ?? null) !== null && style.auto === true;
    const result = root._colors(style, graded ? style.gradient : accent, graded ? root.readableOn(style.gradient, own) : own, graded);
    result.gradient = graded ? root.gradientPart(style) : null;
    return result;
  }

  // What of a background in `style` takes the bar's gradient, and how
  // clear: { part: "fill" | "stroke" | "indicator" | "iconFill", alpha },
  // or null where the gradient colors no background (colored icons: the
  // icon takes the color where it sits). A widget filled on hover fills
  // with it. In a merged run the run draws it (a split run's at the
  // labels' tint), so a widget there has none, but for a split icon part
  // or the box of one that doesn't split.
  function gradientPart(style) {
    const fill = root.drawnFill(style);
    if (style.hovered === true && root.fillsOnHover(style))
      return root._part("fill", 1);
    if (style.run && style.fill === "split")
      return root._part("fill", style.tint);
    if (style.group)
      return fill === "split" ? root._part("iconFill", 1) : style.fill === "split" ? root._part("fill", 1) : null;
    switch (fill) {
    case "split":
      return root._part("iconFill", 1);
    case "tinted":
      return root._part("fill", style.tint);
    case "outline":
      return root._part("stroke", 1);
    case "underline":
      return root._part("indicator", 1);
    case "accentText":
    case "plain":
      return null;
    default:
      return root._part("fill", 1);
    }
  }

  // The bar gradient's color `t` along it (0 its start, 1 its end), its
  // `stops` (colors, from first to last) spread evenly
  function gradientAt(stops, t) {
    const n = stops.length - 1;
    if (n <= 0)
      return Qt.color(stops[0]);
    const x = Math.max(0, Math.min(1, t)) * n;
    const k = Math.min(n - 1, Math.floor(x));
    return root._mix(stops[k], stops[k + 1], x - k);
  }

  // The part of the bar gradient from `start` to `end` along the bar (0 to
  // 1), as three stops 0 to 1 along it ({ position, color }, `alpha` its
  // opacity): its ends and the one bar stop inside it (a three-stop
  // gradient's middle), or its middle where none is (the gradient straight
  // there). Linear between them, as the bar's is, so slices meet seamlessly.
  function gradientSlice(stops, start, end, alpha) {
    const span = end - start;
    const n = stops.length - 1;
    let inner = 0.5;
    for (let k = 1; k < n; k++) {
      if (span > 0 && k / n > start && k / n < end) {
        inner = (k / n - start) / span;
        break;
      }
    }
    const at = position => ({
          "position": position,
          "color": Qt.alpha(root.gradientAt(stops, start + span * position), alpha)
        });
    return [at(0), at(inner), at(1)];
  }

  function _colors(style, accent, own, graded) {
    const none = "transparent";
    const text = c => style.override ?? c;
    const fill = root.drawnFill(style);
    const fills = root.fillsOnHover(style);
    // No fill, as its own color cleared where it fills on hover, so the
    // fill fades in from nothing rather than through black
    const unfilled = fills ? Qt.alpha(accent, 0) : none;
    if (style.hovered === true && fills)
      // Filled in its own color, its text and icon reading on it; an
      // outline keeps its stroke (unseen on the fill) so it doesn't fade
      // out and back. In a merged run, the widget's own part alone
      return root._make(accent, fill === "outline" && !style.group ? accent : none, none, text(own), text(own));
    if (style.run && graded && style.fill === "split")
      // A split run's strip of the gradient is its labels' tint, under
      // icon parts each in their own slice of it
      return root._make(root.faded(accent, style.tint), none, none, text(own), text(own));
    if (style.group) {
      // The run draws the background: the icon keeps the state, the label
      // reads on the run (or on the bar, through a tint or outline). A
      // split icon part keeps its own fill on the run, its label on the
      // run's color, or on a gradient's tint in the widget's color. On a
      // gradient run the run's color is the gradient's where the widget
      // sits, and an Auto icon reads on it as the label does (through a
      // tint or outline it takes that color)
      if (fill === "split")
        return root._make(none, none, none, text(style.gradient ? accent : root.readableOn(style.group, style.barText)), text(own), accent);
      if (style.fill === "split")
        // One that doesn't split fills its own box in the run, a tab in
        // the row of them
        return root._make(accent, none, none, text(own), text(own));
      const group = style.gradient ?? style.group;
      const label = text(fill === "filled" ? root.readableOn(group, style.barText) : style.barText);
      return root._make(unfilled, none, none, label, graded && fill === "filled" ? label : accent);
    }
    switch (fill) {
    case "split":
      {
        // The icon part filled, the label on a tint of it, on a color of
        // its own (reading on it) or on the bar; a badge's always on the bar
        const label = style.splitIcon === "badge" ? "none" : style.labelFill;
        if (label === "color")
          return root._make(style.labelColor, none, none, text(root.readableOn(style.labelColor, style.barText)), text(own), accent);
        return root._make(label === "tint" ? root.faded(accent, style.tint) : none, none, none, text(accent), text(own), accent);
      }
    case "tinted":
      return root._make(root.faded(accent, style.tint), none, none, text(accent), text(accent));
    case "outline":
      return root._make(unfilled, accent, none, text(accent), text(accent));
    case "underline":
      return root._make(none, none, accent, text(style.barText), text(style.barText));
    case "accentText":
      // The icon carries the state, the label reads as the bar's text
      return root._make(none, none, none, text(style.barText), accent);
    case "plain":
      return root._make(none, none, none, text(style.barText), text(style.barText));
    default:
      return root._make(accent, none, none, text(own), text(own));
    }
  }

  // Whether a widget (or a cell) in `style` fills while hovered: "Fill on
  // hover" on a style with a box that isn't filled already
  function fillsOnHover(style) {
    return style.hoverFill === true && (style.fill === "tinted" || style.fill === "outline");
  }

  // A cell inside a widget (a workspace) in the same style: { fill, stroke,
  // indicator, content, showsHover }; a `fill` of "solid" is a filled box
  // whatever the bar's style, its outline and line (where the bar draws
  // them) its color too. `color` is the cell's color for its state, `own`
  // what reads on it filled, `state` "active" | "occupied" | "urgent" |
  // "empty"; `style.hovered` the pointer over it. Where the content sits on
  // the bar rather than on the cell's color, an empty cell's is the bar's
  // text faded (its own color is meant to barely show), and plain text
  // tells the states apart by fading alone, but for an urgent cell, whose
  // content takes its color. `showsHover`: hovered, it's filled
  // (fillsOnHover), so the cell draws no hover box of its own. An Auto
  // color (`style.auto`) gives way to the bar gradient's where the cell
  // sits (style.gradient), as a widget's does; `gradient` then says what of
  // its box shows the gradient itself (as colors' does: { part, alpha }),
  // else null. In a merged run (`style.group`) the run draws the
  // background, as for a widget: a filled, tinted or outlined cell draws no
  // box, its color moving to its content (an empty one's faded, reading on
  // the run); a solid cell stays a filled box, and a split one fills its
  // box, a tab in the row as a widget that doesn't split (cellBoxedInRun).
  function cell(style, color, own, state) {
    const graded = (style.gradient ?? null) !== null && style.auto === true;
    if (graded) {
      own = root.readableOn(style.gradient, own);
      color = style.gradient;
    }
    const result = root._cell(style, color, own, state);
    result.gradient = graded ? root._cellGradient(style, result) : null;
    return result;
  }

  // What of a cell's box takes the bar's gradient (cell)
  function _cellGradient(style, look) {
    if (look.showsHover)
      return root._part("fill", 1);
    if (root._groupCell(style))
      return null;
    switch (style.fill) {
    case "tinted":
      return root._part("fill", style.tint);
    case "outline":
      return root._part("stroke", 1);
    case "underline":
      return root._part("indicator", 1);
    case "accentText":
    case "plain":
      return null;
    default:
      return root._part("fill", 1);
    }
  }

  // A cell in a merged run that draws no box of its own (cell)
  function _groupCell(style) {
    return !!style.group && ["filled", "tinted", "outline"].includes(style.fill);
  }

  // Whether a cell as a segment of a merged run (cell's `group`) still
  // draws a box of its own there: a solid one, and split's fill
  function cellBoxedInRun(fill, solid) {
    return solid || fill === "solid" || fill === "split";
  }

  function _cell(style, color, own, state) {
    const none = "transparent";
    const text = c => style.override ?? c;
    if (style.hovered === true && root.fillsOnHover(style))
      return root._makeCell(color, style.fill === "outline" && !style.group ? color : none, none, text(own), true);
    const merged = root._groupCell(style);
    // What the content sits on: the run's color where it's filled, else
    // the bar (through a tint or an outline)
    const under = merged && style.fill === "filled" ? root.readableOn(style.group, style.barText) : style.barText;
    const faded = Qt.alpha(text(under), 0.4);
    const onBar = c => state === "empty" ? faded : text(c);
    if (merged)
      return root._makeCell(root.fillsOnHover(style) ? Qt.alpha(color, 0) : none, none, none, onBar(color));
    switch (style.fill) {
    case "solid":
      return root._makeCell(color, color, color, text(own));
    case "split":
      // A cell has no label apart: filled
      return root._makeCell(color, none, none, text(own));
    case "tinted":
      return root._makeCell(root.faded(color, style.tint), none, none, onBar(color));
    case "outline":
      return root._makeCell(root.fillsOnHover(style) ? Qt.alpha(color, 0) : none, color, none, onBar(color));
    case "underline":
      return root._makeCell(none, none, color, onBar(style.barText));
    case "accentText":
      return root._makeCell(none, none, none, onBar(color));
    case "plain":
      return root._makeCell(none, none, none, state === "active" ? text(style.barText) : state === "urgent" ? color : state === "occupied" ? Qt.alpha(text(style.barText), 0.7) : faded);
    default:
      return root._makeCell(color, none, none, text(own));
    }
  }

  // The style a widget draws in: split only where it splits (an icon part
  // and a label), filled otherwise
  function drawnFill(style) {
    return style.fill === "split" && !style.splits ? "filled" : style.fill;
  }

  // A boxed look's grouping as drawn (`look`: a BarStyle's widgetStyle,
  // splitIcon, widgetShape, widgetGrouping): a powerline draws as separate
  // where there's nothing to chain, a split badge (no box) and tabs (each
  // hangs from the edge; the option is hidden for them)
  function grouping(look) {
    if (look.widgetGrouping !== "powerline")
      return look.widgetGrouping;
    const unchained = (look.widgetStyle === "split" && look.splitIcon === "badge") || look.widgetShape === "tab";
    return unchained ? "separate" : "powerline";
  }

  // Whether a cell's box (cell) hides what's under it, so the next cell
  // in a powerline of them can start square beneath it: filled, split's
  // (filled) and solid boxes
  function cellOpaque(fill, solid) {
    return solid || fill === "filled" || fill === "split";
  }

  // A boxed look's shape as drawn (`look` as grouping's): a separate split
  // badge has no box to hang from the edge, so a tab saved with it draws
  // rounded (the option is hidden there); a merged run of badges is one
  // tab still
  function shape(look) {
    const badge = look.widgetStyle === "split" && look.splitIcon === "badge" && look.widgetGrouping !== "merged";
    return badge && look.widgetShape === "tab" ? "rounded" : look.widgetShape;
  }

  // Whether a powerline segment's fill hides what's under it, so the next
  // can start square beneath its end cap: filled, and split's joined label
  // on a color of its own
  function opaque(fill, splitIcon, labelFill) {
    return fill === "filled" || (fill === "split" && splitIcon === "joined" && labelFill === "color");
  }

  // What an Auto color is seen against and how much it must stand out
  // (BarsConfig.withAutoColors): { onRun, minContrast }. onRun: against a
  // merged run's background instead of the bar. A fill need only show
  // (1.3); text, strokes and icons must read (3). Split's color is its
  // icon part's fill, and the label's text too where the label sits on a
  // tint of it or the bar.
  function autoContrast(fill, grouping, splitIcon, labelFill) {
    const merged = grouping === "merged";
    if (fill === "filled")
      return root._contrast(merged, merged ? 3 : 1.3);
    if (fill === "split")
      return root._contrast(merged, merged || (splitIcon === "joined" && labelFill === "color") ? 1.3 : 3);
    return root._contrast(false, 3);
  }

  function _contrast(onRun, minContrast) {
    return {
      "onRun": onRun,
      "minContrast": minContrast
    };
  }

  // A value widget's pill (its background filled to its value) in its
  // `colors` (colors())
  function levelColor(colors) {
    return root.faded(colors.icon, 0.35);
  }

  // Whether a value widget with "Colour the text by state" on (its
  // display `appearance`) takes its state's colour for its text: only
  // where that isn't its background already (a filled widget's text must
  // read on it)
  function textByState(colors, appearance) {
    return appearance.colorText && colors.fill.a < 1;
  }

  // `color` at `alpha` of its own opacity: a clear color (a widget with no
  // color of its own, Workspaces' box with its background off) stays
  // clear, where Qt.alpha would make it black at that opacity
  function faded(color, alpha) {
    const c = Qt.color(color);
    return Qt.alpha(c, c.a * alpha);
  }

  // `preferred` if it contrasts with `background`, else black or white
  function readableOn(background, preferred) {
    return Utils.isColorDark(background) !== Utils.isColorDark(preferred) ? preferred : Utils.getContrastColor(background);
  }

  function _mix(a, b, f) {
    const p = Qt.color(a), q = Qt.color(b);
    return Qt.rgba(p.r + (q.r - p.r) * f, p.g + (q.g - p.g) * f, p.b + (q.b - p.b) * f, p.a + (q.a - p.a) * f);
  }

  function _part(part, alpha) {
    return {
      "part": part,
      "alpha": alpha
    };
  }

  function _makeCell(fill, stroke, indicator, content, showsHover) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "content": content,
      "showsHover": showsHover === true
    };
  }

  function _make(fill, stroke, indicator, text, icon, iconFill = "transparent") {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "text": text,
      "icon": icon,
      "iconFill": iconFill
    };
  }
}
