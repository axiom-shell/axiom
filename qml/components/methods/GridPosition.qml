pragma Singleton
import QtQuick

// Where the workspace grid's switcher shows the bar to be: the row (column
// on a vertical bar) of the active workspace, its glyph, and the head that
// shows it as dots or an arrow. The grid strip and its position head both
// read these. No file access, processes or services.
QtObject {
  id: root

  // `{ line, count }` for workspace `activeId` in a `columns` × `rows`
  // grid starting at `base`: the column (vertical bar) or row it's in
  // (the first when it's outside the grid), and how many there are
  function line(activeId, base, columns, rows, vertical) {
    const place = activeId - base;
    const index = place >= 0 && place < columns * rows ? place : 0;
    return {
      "line": vertical ? index % columns : Math.floor(index / columns),
      "count": vertical ? columns : rows
    };
  }

  // The icon for line `position` of `count`: double arrows at the ends,
  // single ones between, a dot in the middle
  function glyph(position, count, vertical) {
    const middle = (count - 1) / 2;
    if (position === middle)
      return "circle";
    if (vertical)
      return position === 0 ? "keyboard_double_arrow_left" : position === count - 1 ? "keyboard_double_arrow_right" : position < middle ? "keyboard_arrow_left" : "keyboard_arrow_right";
    return position === 0 ? "keyboard_double_arrow_up" : position === count - 1 ? "keyboard_double_arrow_down" : position < middle ? "keyboard_arrow_up" : "keyboard_arrow_down";
  }

  // The head for line `active` of `count`, across a bar `across` px thick
  // with text `fontSize`: `{ kind: "none" | "pips" | "arrow", dot, gap,
  // length, glyph }`. Pips are the biggest whole-pixel dots (3 px or more)
  // that fit with a margin; none fit: the arrow's glyph. A single line
  // has no position to show.
  function head(count, active, vertical, across, fontSize) {
    if (count < 2)
      return {
        "kind": "none"
      };
    const room = across - 2 * Math.max(2, Math.round(across * 0.1));
    const maxDot = Math.max(3, Math.round(fontSize * 0.4));
    for (let dot = maxDot; dot >= 3; dot--) {
      const gap = Math.max(1, Math.floor(dot / 2));
      const length = count * dot + (count - 1) * gap;
      if (length <= room)
        return {
          "kind": "pips",
          "dot": dot,
          "gap": gap,
          "length": length
        };
    }
    return {
      "kind": "arrow",
      "glyph": glyph(active, count, vertical)
    };
  }
}
