pragma Singleton
import QtQuick

// What a bar widget draws in, by its bar's widget style: { fill, stroke,
// indicator, text, icon }. `accent` is the widget's own color for its state
// (its background while filled), `own` its text color (picked to read on
// that background). `style` is the bar's, colors resolved by the caller:
//   fill      the bar's widgetStyle
//   barText   what reads on the bar itself
//   override  the bar's text color, replacing the automatic one, or null
//   tint      a tinted fill's opacity (0-1)
//   group     the shared background of a merged run the widget sits in,
//             or null; the run's own background is colors(style, group)
QtObject {
  id: root

  function colors(style, accent, own) {
    const none = "transparent";
    const text = c => style.override ?? c;
    if (style.group)
      // The run draws the background: the icon keeps the state, the label
      // reads on the run (or on the bar, through a tint or outline)
      return root._make(none, none, none, text(style.fill === "filled" ? root.readableOn(style.group, style.barText) : style.barText), accent);
    switch (style.fill) {
    case "tinted":
      return root._make(Qt.alpha(accent, style.tint), none, none, text(accent), text(accent));
    case "outline":
      return root._make(none, accent, none, text(accent), text(accent));
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

  // A cell inside a widget (a workspace) in the same style: { fill, stroke,
  // indicator, content }. `color` is the cell's color for its state, `own`
  // what reads on it filled, `state` "active" | "occupied" | "empty". Where
  // the content sits on the bar rather than on the cell's color, an empty
  // cell's is the bar's text faded (its own color is meant to barely show),
  // and plain text tells the states apart by fading alone.
  function cell(style, color, own, state) {
    const none = "transparent";
    const text = c => style.override ?? c;
    const faded = Qt.alpha(text(style.barText), 0.4);
    const onBar = c => state === "empty" ? faded : text(c);
    switch (style.fill) {
    case "tinted":
      return root._makeCell(Qt.alpha(color, style.tint), none, none, onBar(color));
    case "outline":
      return root._makeCell(none, color, none, onBar(color));
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

  // `preferred` if it contrasts with `background`, else black or white
  function readableOn(background, preferred) {
    return Utils.isColorDark(background) !== Utils.isColorDark(preferred) ? preferred : Utils.getContrastColor(background);
  }

  function _makeCell(fill, stroke, indicator, content) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "content": content
    };
  }

  function _make(fill, stroke, indicator, text, icon) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "text": text,
      "icon": icon
    };
  }
}
