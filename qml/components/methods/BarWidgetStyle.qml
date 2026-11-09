pragma Singleton
import QtQuick

// Paint: which color each part of a bar widget, or of a cell inside one
// (a workspace), takes on a bar's look (BarLook.resolve, barConfig.look)
// for its state. What a style is (boxed, filled on hover, what takes the
// gradient, …) is the look's traits; this only colors.
//
// `palette` is the look's colors resolved once (palette(),
// barConfig.palette): barText (what reads on the bar itself), override
// (the bar's text color, replacing the automatic one, or null),
// labelColor (split's label color, or null), group and groupStroke (a
// merged run's background and outline), gradientStops (the bar
// gradient's colors, or null).
//
// `state` is what of the widget itself its colors depend on (state()):
//   splits    it shows an icon part and a label apart (split: an icon or a
//             lead graphic, and a label); without, a split bar draws it
//             filled (the style's `fallback`)
//   hovered   the pointer is over it (its hit area): a tinted or outlined
//             widget then draws as filled (Fill on hover)
//   gradient  the bar gradient's color where it sits (its middle), or
//             null: no gradient (or no place on a bar, a preview)
//   auto      its color is its Auto own color (its `accent` role left
//             empty, BarsConfig.withAutoColors): only that gives way to
//             the bar's gradient. A color set on the widget and its state
//             colors keep theirs.
//   run       it's a merged run's own background (runColors)
//   group     it sits in a merged run, which draws its background
//   solid     (a cell) a filled box whatever the bar's style
QtObject {
  id: root

  // The look's colors resolved (`palette` above): `resolve` maps a color
  // name to a color (Theme.resolveColor), `barText` reads on the bar
  function palette(look, resolve, barText) {
    return {
      "barText": barText,
      "override": look.textColor ? resolve(look.textColor) : null,
      "labelColor": look.split ? resolve(look.split.labelColor) : null,
      "group": resolve(look.group.color),
      "groupStroke": resolve(look.group.strokeColor),
      "gradientStops": look.gradient ? look.gradient.map(name => resolve(name)) : null
    };
  }

  // A widget's or cell's `state` (above) from what of it its look
  // depends on, each left out false or none: `spot`, where its middle
  // sits along the bar (0-1, -1 for nowhere: BarGradient.spot), stands for
  // `gradient`
  function state(palette, widget) {
    const spot = widget?.spot ?? -1;
    const stops = spot >= 0 ? palette.gradientStops : null;
    return {
      "gradient": stops ? BarGradient.gradientAt(stops, spot) : null,
      "splits": widget?.splits === true,
      "hovered": widget?.hovered === true,
      "auto": widget?.auto === true,
      "run": widget?.run === true,
      "group": widget?.group === true,
      "solid": widget?.solid === true
    };
  }

  // What a widget draws in: { fill, stroke, indicator, text, icon,
  // iconFill, gradient, textOnFill }. `accent` is its own color for its
  // state (its background while filled), `own` its text color (picked to
  // read on that background). `iconFill` is split's icon part (its icon or
  // badge), else transparent; `gradient` what of its background draws the
  // bar's gradient ({ part, alpha }: the look's `gradientPart` trait), else
  // null. `textOnFill`: its text sits on a fill it must read on (filled; in
  // a merged run on a filled or split bar, the run's; split's label on a
  // color of its own; filled on hover), so it never takes a state's color
  // (textByState).
  function colors(look, palette, state, accent, own) {
    const graded = state.gradient !== null && state.auto;
    const result = root._widget(look, palette, state, graded ? state.gradient : accent, graded ? root.readableOn(state.gradient, own) : own, graded);
    result.gradient = graded ? root._widgetGradient(look, state) : null;
    return result;
  }

  // What a merged run's shared background draws in (colors() as the run):
  // its group color (an outline run's line its stroke color), or with a
  // gradient on the bar one strip of it (`spot`: the run's middle, -1 for
  // none)
  function runColors(look, palette, spot) {
    const group = look.traits.stroke ? palette.groupStroke : palette.group;
    return root.colors(look, palette, root.state(palette, {
      "spot": spot,
      "auto": true,
      "run": true
    }), group, root.readableOn(group, palette.barText));
  }

  // A cell inside a widget (a workspace) in the same look: { fill, stroke,
  // indicator, content, showsHover, gradient }; a solid one (`state.solid`)
  // is a filled box whatever the bar's style, its outline and line (where
  // the bar draws them) its color too. `color` is the cell's color for its
  // state, `own` what reads on it filled, `cellState` "active" |
  // "occupied" | "urgent" | "empty". Where the content sits on the bar
  // rather than on the cell's color, an empty cell's is the bar's text
  // faded (its own color is meant to barely show), and plain text tells
  // the states apart by fading alone, but for an urgent cell, whose
  // content takes its color. `showsHover`: hovered, it's filled (Fill on
  // hover), so the cell draws no hover box of its own. An Auto color
  // (`state.auto`) gives way to the bar gradient's where the cell sits, as
  // a widget's does. In a merged run (`state.group`) the run draws the
  // background, as for a widget: a cell whose style's `groupCell` trait
  // holds draws no box, its color moving to its content (an empty one's
  // faded, reading on the run); a solid cell stays a filled box, and a
  // split one fills its box, a tab in the row as a widget that doesn't
  // split (the `cellBoxedInRun` trait).
  function cell(look, palette, state, color, own, cellState) {
    const graded = state.gradient !== null && state.auto;
    const result = root._cell(look, palette, state, graded ? state.gradient : color, graded ? root.readableOn(state.gradient, own) : own, cellState);
    result.gradient = graded ? root._cellGradient(look, state, result) : null;
    return result;
  }

  // The style a widget draws in: its look's, or the style's `fallback`
  // where it can't (split, for a widget that doesn't split)
  function _drawn(look, state) {
    const fallback = look.traits.fallback;
    return fallback && !state.splits ? fallback : look.style;
  }

  // The style a cell draws in: solid, or its look's (split's filled: a
  // cell has no label apart)
  function _cellDrawn(look, state) {
    return state.solid ? "solid" : look.traits.fallback ?? look.style;
  }

  // Whether a widget or cell of style `name` fills while hovered: "Fill on
  // hover" on (the look's, as drawn) for a style it applies to
  function _fills(look, name) {
    return look.hoverFill && BarLook.traitsOf(name, look).hoverFills;
  }

  // A box in `color` in style `name` and what reads in it, before the bar's
  // text color: { fill, stroke, indicator, text, icon, onFill, keepsIcon }.
  // `onFill`: the content reads on the box's own fill (`own`), not on the
  // bar; `keepsIcon`: the icon keeps its color under the bar's text color
  // (colored icons: it carries the state). `unfilled` is an unfilled
  // box's fill: its color cleared where it fills on hover, so the fill
  // fades in from nothing rather than through black. A widget's and a
  // cell's boxes are the same; split's own (an icon part and a label) is
  // the widget's alone (_widget).
  function _box(name, look, palette, color, own, unfilled) {
    const none = "transparent";
    const paint = (fill, stroke, indicator, text, icon, onFill, keepsIcon) => ({
          "fill": fill,
          "stroke": stroke,
          "indicator": indicator,
          "text": text,
          "icon": icon,
          "onFill": onFill,
          "keepsIcon": keepsIcon === true
        });
    switch (name) {
    case "solid":
      return paint(color, color, color, own, own, true);
    case "tinted":
      return paint(root.faded(color, look.tint), none, none, color, color, false);
    case "outline":
      return paint(unfilled, color, none, color, color, false);
    case "underline":
      return paint(none, none, color, palette.barText, palette.barText, false);
    case "accentText":
      // The icon carries the state, the label reads as the bar's text
      return paint(none, none, none, palette.barText, color, false, true);
    case "plain":
      return paint(none, none, none, palette.barText, palette.barText, false);
    default:
      return paint(color, none, none, own, own, true);
    }
  }

  function _widget(look, palette, state, accent, own, graded) {
    const none = "transparent";
    const text = c => palette.override ?? c;
    const drawn = root._drawn(look, state);
    const fills = root._fills(look, look.style);
    const unfilled = fills ? Qt.alpha(accent, 0) : none;
    if (state.hovered && fills)
      // Filled in its own color, its text and icon reading on it; an
      // outline keeps its stroke (unseen on the fill) so it doesn't fade
      // out and back. In a merged run, the widget's own part alone
      return root._make(accent, drawn === "outline" && !state.group ? accent : none, none, text(own), text(own), none, true);
    if (state.run && graded && look.style === "split")
      // A split run's strip of the gradient is its labels' tint, under
      // icon parts each in their own slice of it
      return root._make(root.faded(accent, look.tint), none, none, text(own), text(own), none, false);
    if (state.group) {
      // The run draws the background: the icon keeps the state, the label
      // reads on the run (or on the bar, through a tint or outline). A
      // split icon part keeps its own fill on the run, its label on the
      // run's color, or on a gradient's tint in the widget's color. On a
      // gradient run the run's color is the gradient's where the widget
      // sits, and an Auto icon reads on it as the label does (through a
      // tint or outline it takes that color)
      // (A split run with a gradient is its labels' tint, not a fill)
      if (drawn === "split")
        return root._make(none, none, none, text(state.gradient ? accent : root.readableOn(palette.group, palette.barText)), text(own), accent, !state.gradient);
      if (look.style === "split")
        // One that doesn't split fills its own box in the run, a tab in
        // the row of them
        return root._make(accent, none, none, text(own), text(own), none, true);
      const group = state.gradient ?? palette.group;
      const label = text(drawn === "filled" ? root.readableOn(group, palette.barText) : palette.barText);
      return root._make(unfilled, none, none, label, graded && drawn === "filled" ? label : accent, none, drawn === "filled");
    }
    if (drawn === "split") {
      // The icon part filled, the label on a tint of it, on a color of
      // its own (reading on it) or on the bar; a badge's always on the bar
      const label = look.split.icon === "badge" ? "none" : look.split.labelFill;
      if (label === "color")
        return root._make(palette.labelColor, none, none, text(root.readableOn(palette.labelColor, palette.barText)), text(own), accent, true);
      return root._make(label === "tint" ? root.faded(accent, look.tint) : none, none, none, text(accent), text(own), accent, false);
    }
    const box = root._box(drawn, look, palette, accent, own, unfilled);
    return root._make(box.fill, box.stroke, box.indicator, text(box.text), box.keepsIcon ? box.icon : text(box.icon), none, box.onFill);
  }

  // What of a widget's background takes the bar's gradient: filled on
  // hover, its fill in full; a split run's strip, at the labels' tint; in
  // a merged run (which draws it) none, but for a split icon part or the
  // box of one that doesn't split; else its drawn style's `gradientPart`
  function _widgetGradient(look, state) {
    const drawn = root._drawn(look, state);
    if (state.hovered && root._fills(look, look.style))
      return root._part("fill", 1);
    if (state.run && look.style === "split")
      return root._part("fill", look.tint);
    if (state.group)
      return drawn === "split" ? root._part("iconFill", 1) : look.style === "split" ? root._part("fill", 1) : null;
    return BarLook.traitsOf(drawn, look).gradientPart;
  }

  function _cell(look, palette, state, color, own, cellState) {
    const none = "transparent";
    const text = c => palette.override ?? c;
    const style = state.solid ? "solid" : look.style;
    const drawn = root._cellDrawn(look, state);
    const fills = root._fills(look, style);
    if (state.hovered && fills)
      return root._makeCell(color, drawn === "outline" && !state.group ? color : none, none, text(own), true);
    const merged = state.group && BarLook.traitsOf(style, look).groupCell;
    // What the content sits on: the run's color where it's filled, else
    // the bar (through a tint or an outline)
    const under = merged && drawn === "filled" ? root.readableOn(palette.group, palette.barText) : palette.barText;
    const faded = Qt.alpha(text(under), 0.4);
    const onBar = c => cellState === "empty" ? faded : text(c);
    const unfilled = fills ? Qt.alpha(color, 0) : none;
    if (merged)
      return root._makeCell(unfilled, none, none, onBar(color));
    const box = root._box(drawn, look, palette, color, own, unfilled);
    if (drawn === "plain")
      return root._makeCell(box.fill, box.stroke, box.indicator, cellState === "active" ? text(palette.barText) : cellState === "urgent" ? color : cellState === "occupied" ? Qt.alpha(text(palette.barText), 0.7) : faded);
    return root._makeCell(box.fill, box.stroke, box.indicator, box.onFill ? text(box.icon) : onBar(box.icon));
  }

  // What of a cell's box takes the bar's gradient (cell): filled on hover
  // its fill; in a merged run that draws its box, none; else its drawn
  // style's `gradientPart`
  function _cellGradient(look, state, result) {
    if (result.showsHover)
      return root._part("fill", 1);
    if (state.group && BarLook.traitsOf(state.solid ? "solid" : look.style, look).groupCell)
      return null;
    return BarLook.traitsOf(root._cellDrawn(look, state), look).gradientPart;
  }

  // A value widget's pill (its background filled to its value) in its
  // `colors` (colors())
  function levelColor(colors) {
    return root.faded(colors.icon, 0.35);
  }

  // Whether a value widget with "Colour the text by state" on (its
  // display `appearance`) takes its state's colour for its text: only
  // where its text doesn't sit on a fill it must read on (`textOnFill`)
  function textByState(colors, appearance) {
    return appearance.colorText && !colors.textOnFill;
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

  function _make(fill, stroke, indicator, text, icon, iconFill, textOnFill) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "text": text,
      "icon": icon,
      "iconFill": iconFill,
      "textOnFill": textOnFill
    };
  }
}
