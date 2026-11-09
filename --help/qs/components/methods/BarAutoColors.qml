pragma Singleton
import QtQuick

// The colors a bar picks for its widgets' Auto color fields (a schema
// `x-autoColor` role, left empty). `widgets` is the bar's widgets in order,
// each { roles: { key: role }, set: { key: color } }: its Auto-capable
// fields and the colors the user fixed among them. `palette`:
//   accents      [{ name, color }] the colors widgets are told apart by
//   neutrals     [{ name, color }] from subtle to strong, for "off" states
//   warning      { name, color }
//   critical     { name, color }
//   backdrop     what the colors are seen against (the bar, or a merged
//                run's background)
//   minContrast  how far (WCAG ratio) a color must stand out from it
// Roles:
//   accent    the widget's own color: unlike its neighbours' (fixed ones
//             included), and every accent used before one repeats
//   alt       a second state: as unlike its accent as the palette allows
//   warning, critical   the palette's
//   off       the subtlest neutral that still stands out
//   neutral   the same, for a box whose content brings its own colors
//             (tray icons, workspace cells)
// Returns one { key: name } per widget, for its fields not in `set`.
QtObject {
  id: root

  function assign(widgets, palette) {
    const usable = root._usable(palette.accents, palette.backdrop, palette.minContrast);
    const off = palette.neutrals.find(n => root.contrast(n.color, palette.backdrop) >= palette.minContrast) ?? palette.neutrals[palette.neutrals.length - 1];
    // Each widget's accent as it's settled: fixed ones are known up front
    const accents = widgets.map(w => root._accentKey(w) !== null ? (w.set[root._accentKey(w)] ?? null) : null);
    const used = accents.filter(c => c !== null);
    // Widgets with no accent (nothing Auto-capable) aren't anyone's neighbour
    const order = widgets.map((w, i) => i).filter(i => root._accentKey(widgets[i]) !== null);

    return widgets.map((w, i) => {
      const out = {};
      const roles = w.roles;
      const at = order.indexOf(i);
      const near = step => {
        const j = at < 0 ? undefined : order[at + step];
        return j === undefined ? null : accents[j];
      };
      const key = root._accentKey(w);
      if (key !== null && !(key in w.set)) {
        // Its own state colors stay distinguishable from it
        const states = Object.keys(roles).filter(k => roles[k] === "warning" || roles[k] === "critical").map(k => w.set[k] ?? palette[roles[k]].color);
        const pick = root._best(usable, at, c => 8 * (root.similarity(c, near(-1)) + root.similarity(c, near(1)) + Math.max(0, ...states.map(s => root.similarity(c, s)))) + 3 * (root.similarity(c, near(-2)) + root.similarity(c, near(2))) + used.reduce((sum, u) => sum + root.similarity(c, u), 0));
        out[key] = pick.name;
        accents[i] = pick.color;
        used.push(pick.color);
      }
      Object.keys(roles).forEach(k => {
        if (k in w.set || k === key)
          return;
        switch (roles[k]) {
        case "alt":
          out[k] = root._best(usable, at, c => 4 * (root.similarity(c, near(-1)) + root.similarity(c, near(1))) - (accents[i] === null ? 0 : root.distance(c, accents[i]))).name;
          break;
        case "warning":
        case "critical":
          out[k] = palette[roles[k]].name;
          break;
        default:
          // off, neutral
          out[k] = off.name;
        }
      });
      return out;
    });
  }

  // WCAG contrast ratio, 1 to 21
  function contrast(a, b) {
    const la = root._luminance(a);
    const lb = root._luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }

  // 0 (alike) to 1 (black against white)
  function distance(a, b) {
    const ca = Qt.color(a);
    const cb = Qt.color(b);
    return Math.sqrt(((ca.r - cb.r) ** 2 + (ca.g - cb.g) ** 2 + (ca.b - cb.b) ** 2) / 3);
  }

  // 1 for the same color, falling to 0 at 15% of the way to its opposite
  function similarity(a, b) {
    return b === null ? 0 : Math.max(0, 1 - root.distance(a, b) / 0.15);
  }

  // The field a widget's accent is in, or null
  function _accentKey(widget) {
    return Object.keys(widget.roles).find(k => widget.roles[k] === "accent") ?? null;
  }

  // The accents that stand out from the backdrop, else the three that do most
  function _usable(accents, backdrop, minContrast) {
    const enough = accents.filter(a => root.contrast(a.color, backdrop) >= minContrast);
    if (enough.length >= 3)
      return enough;
    return accents.slice().sort((a, b) => root.contrast(b.color, backdrop) - root.contrast(a.color, backdrop)).slice(0, 3);
  }

  // The lowest-scoring candidate; ties go round the palette from `index`,
  // so equal choices cycle along the bar
  function _best(candidates, index, score) {
    let best = null;
    let bestScore = Infinity;
    for (let n = 0; n < candidates.length; n++) {
      const c = candidates[(Math.max(0, index) + n) % candidates.length];
      const s = score(c.color);
      if (s < bestScore - 1e-6) {
        best = c;
        bestScore = s;
      }
    }
    return best;
  }

  function _luminance(color) {
    const c = Qt.color(color);
    const lin = v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  }
}
