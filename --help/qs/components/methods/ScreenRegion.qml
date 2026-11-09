pragma Singleton
import QtQuick

// Rectangles across monitors, for the screenshot picker: a selection
// kept in global logical pixels (the compositor's layout) and each
// screen's part of it. Rects and screens are { x, y, width, height }
// (a screen may carry a name); every result is a new plain object.
QtObject {
  id: root

  // The rect between two points { x, y }, whichever way it was dragged
  function between(a, b) {
    return {
      "x": Math.min(a.x, b.x),
      "y": Math.min(a.y, b.y),
      "width": Math.abs(b.x - a.x),
      "height": Math.abs(b.y - a.y)
    };
  }

  // Where `a` and `b` overlap; an empty rect (width and height 0, at
  // a's clamped corner) when they don't
  function intersect(a, b) {
    const left = Math.max(a.x, b.x);
    const top = Math.max(a.y, b.y);
    const right = Math.min(a.x + a.width, b.x + b.width);
    const bottom = Math.min(a.y + a.height, b.y + b.height);
    if (right <= left || bottom <= top)
      return {
        "x": Math.min(Math.max(a.x, b.x), b.x + b.width),
        "y": Math.min(Math.max(a.y, b.y), b.y + b.height),
        "width": 0,
        "height": 0
      };
    return {
      "x": left,
      "y": top,
      "width": right - left,
      "height": bottom - top
    };
  }

  // Whether a rect has an area
  function isEmpty(rect) {
    return !rect || !(rect.width > 0 && rect.height > 0);
  }

  // `global`'s part on `screen`, in the screen's own pixels from its top
  // left (empty when it isn't on it)
  function local(global, screen) {
    const part = root.intersect(global, screen);
    return {
      "x": part.x - screen.x,
      "y": part.y - screen.y,
      "width": part.width,
      "height": part.height
    };
  }

  // A rect in `screen`'s own pixels, in global ones
  function toGlobal(rect, screen) {
    return {
      "x": rect.x + screen.x,
      "y": rect.y + screen.y,
      "width": rect.width,
      "height": rect.height
    };
  }

  // The screens `rect` has an area on, in their order
  function covered(rect, screens) {
    return (screens ?? []).filter(s => !root.isEmpty(root.intersect(rect, s)));
  }

  // Whether a point is inside a rect (its right and bottom edges out)
  function contains(rect, x, y) {
    return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
  }

  // The first of `boxes` (topmost first, each with an `output` name)
  // under the point, those of `output` (the screen the point is on)
  // before the others: a window spilling onto a monitor is under that
  // monitor's own windows. null when none
  function boxAt(boxes, x, y, output) {
    const hits = (boxes ?? []).filter(b => root.contains(b, x, y));
    return hits.find(b => b.output === output) ?? hits[0] ?? null;
  }
}
