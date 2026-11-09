pragma Singleton
import QtQuick

// The bar gradient (a bar look's `gradient`, its colors resolved in
// barConfig.palette's `gradientStops`): one gradient along the whole bar,
// left to right (top to bottom on a vertical bar), each widget showing
// its part. Where a point sits along the bar (`spot`), its color there
// (`gradientAt`) and a part's slice of it (`gradientSlice`).
QtObject {
  id: root

  // Where the middle of a part `length` long, `offset` into what starts
  // `barStart` along a bar `barLength` long, sits along it (0-1), or -1
  // with no bar to measure against (no gradient, or no place on a bar)
  function spot(offset, length, barStart, barLength) {
    return barLength > 0 ? (barStart + offset + length / 2) / barLength : -1;
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

  function _mix(a, b, f) {
    const p = Qt.color(a), q = Qt.color(b);
    return Qt.rgba(p.r + (q.r - p.r) * f, p.g + (q.g - p.g) * f, p.b + (q.b - p.b) * f, p.a + (q.a - p.a) * f);
  }
}
