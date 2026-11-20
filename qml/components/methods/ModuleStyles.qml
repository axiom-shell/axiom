pragma Singleton
import QtQuick

// Which style a module draws, by its room: the one the user chose, or for
// "auto" the first of its candidates that fits. No file access, processes or
// services.
QtObject {
  id: root

  // The style to draw: `style` unless it is "auto", else the style of the
  // first of `candidates` ([{ style, minWidth, minHeight }], px, in
  // preference order) with `width >= minWidth && height >= minHeight`, else
  // the last candidate, or "" for none. A list ends with its fallback at
  // minWidth 0, minHeight 0, so it is explicit and always fits.
  function resolvedStyle(style, candidates, width, height) {
    if (style !== "auto")
      return style;
    const fit = candidates.find(c => width >= c.minWidth && height >= c.minHeight) ?? candidates[candidates.length - 1];
    return fit ? fit.style : "";
  }
}
