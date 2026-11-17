pragma Singleton
import QtQuick

// The column count of a grid of equal choice tiles (ChoiceTiles): one line
// while all fit, else an even grid (the same rows, the fewest columns), and
// never one tile per line while two can sit side by side
QtObject {
  id: root

  // `count` tiles in `width`, `gap` apart. `comfortable` is the width a tile
  // likes, `least` the narrowest that still shows its label (and preview)
  // whole; comfortable is never below it. Returns the columns: all `count`
  // when they fit one line; else balanced (7 at 4 a row: 4 + 3, 4 at 3: 2 + 2);
  // 2 when only two `least` tiles fit; 1 below that or for no width
  function columns(count, width, comfortable, least, gap) {
    if (count <= 1 || width <= 0)
      return 1;
    const g = Math.max(0, gap);
    const fit = Math.floor((width + g) / (Math.max(comfortable, least) + g));
    if (fit >= count)
      return count;
    if (fit >= 2) {
      const rows = Math.ceil(count / fit);
      return Math.ceil(count / rows);
    }
    return 2 * least + g <= width ? 2 : 1;
  }
}
