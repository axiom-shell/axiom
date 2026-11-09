pragma Singleton
import QtQuick

// A bar widget's display-style graphic (ValueGraphic,
// docs/dev/bar/display-styles.md): the style it draws as, and its extent
// across the bar, from config, for the room at a run's end
// (BarIconWidget.contentAcross)
QtObject {
  id: root

  // Stacked's two lines: a line is about 1.2 of its font, the value's 0.8
  // of the bar's font and the caption's 0.6
  readonly property real lineHeight: 1.2
  readonly property real stackedLines: 0.8 + 0.6

  // The style a widget's `style` draws as where it can't draw it: stacked
  // on a vertical bar is a label, a sparkline with no history a fill, and
  // a value style with no value (`ratio` below 0) a label
  function resolvedStyle(style, vertical, hasHistory, ratio) {
    if (style === "stacked" && vertical)
      return "label";
    if (style === "sparkline" && !hasHistory)
      style = "fill";
    if (["ring", "fill", "segments", "pill"].includes(style) && ratio < 0)
      return "label";
    return style;
  }

  // The room across a bar `thickness` thick inside a widget's box, in
  // the look's `shape` (look.shape): the thickness less its outline's
  // stroke band (BarShapes.strokeBand) either side; the whole thickness
  // where no box is drawn (`capped` false: an unboxed style) or it has no
  // outline
  function boxRoom(thickness, shape) {
    const band = shape?.capped ? BarShapes.strokeBand(shape.outline ?? null) : 0;
    return Math.max(0, thickness - band * 2);
  }

  // The scale stacked's two lines shrink by to fit in `room` across the
  // bar (boxRoom) at `fontSize` (a text scale past 100%): 1 where they
  // fit or either size is unknown
  function stackedFit(room, fontSize) {
    return fontSize > 0 && room > 0 ? Math.min(1, room / (root.lineHeight * root.stackedLines * fontSize)) : 1;
  }

  // How far across the bar the graphic of `style` (resolved) reaches, in
  // px, on a bar `crossSize` thick at `fontSize`, `room` of it inside the
  // widget's box (boxRoom); 0 for one no taller than a line at the font
  // size (fill, segments, the ticker's one line) or none. The ring is
  // 0.62 of the thickness; the sparkline 0.6 of it on a horizontal bar,
  // inset 0.2 either side, and the whole thickness on a vertical one (its
  // inset is along the bar there); stacked its two lines at their fit in
  // the room.
  function across(style, vertical, crossSize, fontSize, room) {
    switch (style) {
    case "ring":
      return crossSize * 0.62;
    case "sparkline":
      return vertical ? crossSize : crossSize * 0.6;
    case "stacked":
      return root.lineHeight * root.stackedLines * fontSize * root.stackedFit(room, fontSize);
    }
    return 0;
  }
}
