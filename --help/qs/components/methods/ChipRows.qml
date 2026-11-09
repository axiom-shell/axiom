pragma Singleton
import QtQuick

// Rows for a set of equal chips (CountdownTimer's presets): as few rows as
// `fit` to a row allows, the chips spread evenly over them, so every row
// fills its width and none ends in a gap
QtObject {
  id: root

  // The chips in each row, the fuller rows first: split(5, 3) is [3, 2],
  // split(7, 3) [3, 2, 2]
  function split(count, fit) {
    if (count <= 0)
      return [];
    const rows = Math.ceil(count / Math.max(1, fit));
    const base = Math.floor(count / rows);
    const extra = count % rows;
    const sizes = [];
    for (let i = 0; i < rows; i++)
      sizes.push(base + (i < extra ? 1 : 0));
    return sizes;
  }

  // The first chip's index in each row of `sizes`
  function starts(sizes) {
    const out = [];
    let at = 0;
    for (const size of sizes) {
      out.push(at);
      at += size;
    }
    return out;
  }
}
