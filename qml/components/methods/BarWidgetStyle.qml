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
// `iconFill` is split's icon part (its icon or badge), else transparent.
QtObject {
  id: root

  function colors(style, accent, own) {
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
    if (style.group) {
      // The run draws the background: the icon keeps the state, the label
      // reads on the run (or on the bar, through a tint or outline). A
      // split icon part keeps its own fill on the run.
      if (fill === "split")
        return root._make(none, none, none, text(root.readableOn(style.group, style.barText)), text(own), accent);
      return root._make(unfilled, none, none, text(fill === "filled" ? root.readableOn(style.group, style.barText) : style.barText), accent);
    }
    switch (fill) {
    case "split":
      {
        // The icon part filled, the label on a tint of it, on a color of
        // its own (reading on it) or on the bar; a badge's always on the bar
        const label = style.splitIcon === "badge" ? "none" : style.labelFill;
        if (label === "color")
          return root._make(style.labelColor, none, none, text(root.readableOn(style.labelColor, style.barText)), text(own), accent);
        return root._make(label === "tint" ? Qt.alpha(accent, style.tint) : none, none, none, text(accent), text(own), accent);
      }
    case "tinted":
      return root._make(Qt.alpha(accent, style.tint), none, none, text(accent), text(accent));
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
  // indicator, content, showsHover }. `color` is the cell's color for its
  // state, `own` what reads on it filled, `state` "active" | "occupied" |
  // "empty"; `style.hovered` the pointer over it. Where the content sits on the
  // bar rather than on the cell's color, an empty cell's is the bar's text
  // faded (its own color is meant to barely show), and plain text tells
  // the states apart by fading alone. `showsHover`: hovered, it's filled
  // (fillsOnHover), so the cell draws no hover box of its own.
  function cell(style, color, own, state) {
    const none = "transparent";
    const text = c => style.override ?? c;
    if (style.hovered === true && root.fillsOnHover(style))
      return root._makeCell(color, style.fill === "outline" ? color : none, none, text(own), true);
    const faded = Qt.alpha(text(style.barText), 0.4);
    const onBar = c => state === "empty" ? faded : text(c);
    switch (style.fill) {
    case "split":
      // A cell has no label apart: filled
      return root._makeCell(color, none, none, text(own));
    case "tinted":
      return root._makeCell(Qt.alpha(color, style.tint), none, none, onBar(color));
    case "outline":
      return root._makeCell(root.fillsOnHover(style) ? Qt.alpha(color, 0) : none, color, none, onBar(color));
    case "underline":
      return root._makeCell(none, none, color, onBar(style.barText));
    case "accentText":
      return root._makeCell(none, none, none, onBar(color));
    case "plain":
      return root._makeCell(none, none, none, state === "active" ? text(style.barText) : state === "occupied" ? Qt.alpha(text(style.barText), 0.7) : faded);
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
    return Qt.alpha(colors.icon, 0.35);
  }

  // Whether a value widget with "Colour the text by state" on (its
  // display `appearance`) takes its state's colour for its text: only
  // where that isn't its background already (a filled widget's text must
  // read on it)
  function textByState(colors, appearance) {
    return appearance.colorText && colors.fill.a < 1;
  }

  // `preferred` if it contrasts with `background`, else black or white
  function readableOn(background, preferred) {
    return Utils.isColorDark(background) !== Utils.isColorDark(preferred) ? preferred : Utils.getContrastColor(background);
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
