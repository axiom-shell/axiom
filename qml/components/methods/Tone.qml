pragma Singleton
import QtQuick

// The shell's colour math: mixing, compositing, WCAG contrast and nudging a
// colour until it reads. Every colour decision (Style, the bar's
// BarWidgetStyle) calls these; UI never does (check.md R6). Pure: no files,
// processes or services.
//
// Two layers, one formula. The colour functions (`mix`, `nudged`, ...) take
// and return colors and are the bar's, moved verbatim, so its output stays
// bit-identical. The `*Rgb` functions are their twins on plain [r, g, b]
// arrays (0-1, opaque), which StyleTokens derives a whole theme on: a color
// per step costs several times a number (tokens.md > Performance 1). `apart`,
// `step` and `alphaFloor` are written once, on the arrays.
QtObject {
  id: root

  // WCAG contrast the content must reach: text, and icons and graphics
  readonly property real textContrast: 4.5
  readonly property real iconContrast: 3
  // The least contrast of a dimmed (muted) mark
  readonly property real mutedContrast: 3

  // ---- colors ----

  // `a` mixed `t` (0-1) of the way to `b`, every channel
  function mix(a, b, t) {
    const x = Qt.color(a);
    const y = Qt.color(b);
    return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t);
  }

  // `top` drawn over `under`, as an opaque color (`under` taken opaque)
  function over(top, under) {
    const t = Qt.color(top);
    const u = Qt.color(under);
    return Qt.rgba(t.r * t.a + u.r * (1 - t.a), t.g * t.a + u.g * (1 - t.a), t.b * t.a + u.b * (1 - t.a), 1);
  }

  // `color` at alpha `a` (the one Qt.alpha the shell needs)
  function alpha(color, a) {
    return Qt.alpha(Qt.color(color), a);
  }

  // `color` at `f` of its own opacity: a clear color (a widget with no
  // color of its own) stays clear, where Qt.alpha would make it black at
  // that opacity
  function faded(color, f) {
    const c = Qt.color(color);
    return Qt.alpha(c, c.a * f);
  }

  // `color` mixed `t` toward `back`, its alpha kept (a clear color stays
  // clear)
  function toward(color, back, t) {
    const c = Qt.color(color);
    if (c.a === 0)
      return color;
    const m = root.mix(c, back, t);
    return Qt.rgba(m.r, m.g, m.b, c.a);
  }

  // WCAG relative luminance, 0 (black) to 1 (white)
  function luminance(color) {
    const c = Qt.color(color);
    const lin = v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  }

  // WCAG contrast ratio, 1 to 21
  function contrast(a, b) {
    const la = root.luminance(a);
    const lb = root.luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }

  // `color` where it reads on every one of `backs` (opaque colors; WCAG
  // contrast at least `min`), else mixed toward white or black, whichever
  // reads better on them, by the least that does, its hue kept; the pole
  // itself where no mix does. Its alpha is kept; a clear color stays as it is.
  function nudged(backs, color, min) {
    const c = Qt.color(color);
    const worst = x => backs.reduce((least, b) => Math.min(least, root.contrast(b, x)), Infinity);
    if (c.a === 0 || worst(c) >= min)
      return color;
    const white = Qt.rgba(1, 1, 1, c.a);
    const black = Qt.rgba(0, 0, 0, c.a);
    const pole = worst(white) >= worst(black) ? white : black;
    const mix = t => Qt.rgba(c.r + (pole.r - c.r) * t, c.g + (pole.g - c.g) * t, c.b + (pole.b - c.b) * t, c.a);
    if (worst(pole) < min)
      return pole;
    let low = 0;
    let high = 1;
    for (let i = 0; i < 12; i++) {
      const middle = (low + high) / 2;
      if (worst(mix(middle)) >= min)
        high = middle;
      else
        low = middle;
    }
    return mix(high);
  }

  // `preferred` where it reads on `background` (WCAG contrast at least
  // 4.5), else whichever of it, the `alternates` (colors) and black and
  // white contrasts with it most (`preferred` on a tie)
  function readableOn(background, preferred, alternates) {
    if (root.contrast(background, preferred) >= 4.5)
      return preferred;
    const candidates = [preferred].concat(alternates ?? [], ["#000000", "#FFFFFF"]);
    return candidates.reduce((best, c) => root.contrast(background, c) > root.contrast(background, best) ? c : best);
  }

  // White or black, whichever has more WCAG contrast with `background`
  // (white on a tie)
  function bestOn(background) {
    return root.contrast(background, "#FFFFFF") >= root.contrast(background, "#000000") ? "#FFFFFF" : "#000000";
  }

  // Whether white has at least the contrast of black on `color` (WCAG: not
  // the YIQ test of Utils.isColorDark, which disagrees on saturated mid
  // colors)
  function isDark(color) {
    return root.contrast(color, "#ffffff") >= root.contrast(color, "#000000");
  }

  // `color` reads on every one of `backs` at `min`
  function reaches(backs, color, min) {
    return backs.every(b => root.contrast(color, b) >= min);
  }

  // `color` moved toward `pole` by the least that gives it at least `min`
  // contrast with `base`; itself where it has
  function apart(base, color, min, pole) {
    return root.fromRgb(root.apartRgb(root.rgb(base), root.rgb(color), min, root.rgb(pole)));
  }

  // The furthest mix of `base` toward `target` whose contrast with `base`
  // is at most `max`, then `apart` by `min`
  function step(base, target, min, max, pole) {
    return root.fromRgb(root.stepRgb(root.rgb(base), root.rgb(target), min, max, root.rgb(pole)));
  }

  // The least alpha of `fill` composited over every one of `backs` at which
  // `ink` reaches `min` on them: 0 when it already reads on the bare backs,
  // 1 when it can't even on the opaque `fill`, else a 12-step bisection
  // rounded up to 0.01
  function alphaFloor(fill, ink, backs, min) {
    const f = root.rgb(fill);
    const i = root.rgb(ink);
    const bs = backs.map(b => root.rgb(b));
    if (bs.every(b => root.conRgb(i, b) >= min))
      return 0;
    if (root.conRgb(i, f) < min)
      return 1;
    let low = 0;
    let high = 1;
    for (let n = 0; n < 12; n++) {
      const middle = (low + high) / 2;
      if (bs.every(b => root.conRgb(i, root.mixRgb(b, f, middle)) >= min))
        high = middle;
      else
        low = middle;
    }
    return Math.min(1, Math.ceil(Math.round(high * 1000) / 10) / 100);
  }

  // ---- plain [r, g, b] arrays (0-1, opaque) ----

  function rgb(color) {
    const c = Qt.color(color);
    return [c.r, c.g, c.b];
  }

  function fromRgb(c) {
    return Qt.rgba(c[0], c[1], c[2], 1);
  }

  function mixRgb(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  }

  function lumRgb(c) {
    const lin = v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
  }

  function conRgb(a, b) {
    return root._ratio(root.lumRgb(a), root.lumRgb(b));
  }

  // Contrast of two luminances
  function _ratio(la, lb) {
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }

  // `nudged` on arrays (opaque): each back's luminance taken once
  function nudgedRgb(backs, c, min) {
    const lums = backs.map(b => root.lumRgb(b));
    const worst = x => {
      const lx = root.lumRgb(x);
      return lums.reduce((least, lb) => Math.min(least, root._ratio(lb, lx)), Infinity);
    };
    if (worst(c) >= min)
      return c;
    const white = [1, 1, 1];
    const black = [0, 0, 0];
    const pole = worst(white) >= worst(black) ? white : black;
    if (worst(pole) < min)
      return pole;
    let low = 0;
    let high = 1;
    for (let i = 0; i < 12; i++) {
      const middle = (low + high) / 2;
      if (worst(root.mixRgb(c, pole, middle)) >= min)
        high = middle;
      else
        low = middle;
    }
    return root.mixRgb(c, pole, high);
  }

  // `apart` on arrays
  function apartRgb(base, c, min, pole) {
    const lb = root.lumRgb(base);
    if (root._ratio(lb, root.lumRgb(c)) >= min)
      return c;
    let low = 0;
    let high = 1;
    for (let i = 0; i < 12; i++) {
      const middle = (low + high) / 2;
      if (root._ratio(lb, root.lumRgb(root.mixRgb(c, pole, middle))) >= min)
        high = middle;
      else
        low = middle;
    }
    return root.mixRgb(c, pole, high);
  }

  // `step` on arrays
  function stepRgb(base, target, min, max, pole) {
    const lb = root.lumRgb(base);
    let c = target;
    if (root._ratio(lb, root.lumRgb(target)) > max) {
      let low = 0;
      let high = 1;
      for (let i = 0; i < 12; i++) {
        const middle = (low + high) / 2;
        if (root._ratio(lb, root.lumRgb(root.mixRgb(base, target, middle))) <= max)
          low = middle;
        else
          high = middle;
      }
      c = root.mixRgb(base, target, low);
    }
    return root.apartRgb(base, c, min, pole);
  }
}
