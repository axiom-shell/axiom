pragma Singleton
import QtQuick

// A menu drawn as tiles (`background: none`): no box of its own, only its
// cards, each a tile with its own shadow and blur, input on the cards
// alone (hosts/popout/CardMask). Pure: which menus are tiled, which are
// held off their edge, how long a crossing between two cards may take,
// and the rects its input mask is built from.
QtObject {
  id: root

  // The least a tiled menu waits before closing once the pointer leaves
  // a card (ms): crossing a gap leaves one card before it enters the next
  readonly property int closeFloor: 150

  // Whether `menu` is drawn as tiles: `background: none` on an edge or a
  // free menu (a strip always draws its frame)
  function tiled(menu) {
    return menu?.background === "none" && (menu.placement === "edge" || menu.placement === "free");
  }

  // Whether an edge menu is held off its edge: `detached`, or tiled (a
  // tile can't grow out of the edge)
  function detached(menu) {
    return menu?.placement === "edge" && (!!menu.detached || root.tiled(menu));
  }

  // The close delay a menu waits once the pointer leaves it: its own
  // (`close.delay`), at least closeFloor when tiled
  function closeDelay(delay, tiled) {
    return tiled ? Math.max(delay, root.closeFloor) : delay;
  }

  // The cards as shown, in the scrolling view's coordinates: each of
  // `cards` ({ x, y, width, height } in the scrolled content) moved by
  // `scroll` ({ x, y }, the content's offset) and cut to `view`
  // ({ width, height }); null for a card scrolled out of sight. Index for
  // index with `cards`
  function shown(cards, scroll, view) {
    const sx = scroll?.x ?? 0, sy = scroll?.y ?? 0;
    return (cards ?? []).map(card => {
      if (!card)
        return null;
      const x0 = Math.max(0, card.x - sx), y0 = Math.max(0, card.y - sy);
      const x1 = Math.min(view.width, card.x - sx + card.width), y1 = Math.min(view.height, card.y - sy + card.height);
      return x1 > x0 && y1 > y0 ? {
        "x": x0,
        "y": y0,
        "width": x1 - x0,
        "height": y1 - y0
      } : null;
    });
  }

  // The rects an input mask is the union of: `rects` without the empty
  // ones (null, no area) and those inside another (the first of equal
  // ones kept)
  function union(rects) {
    const some = (rects ?? []).filter(r => r && r.width > 0 && r.height > 0);
    const inside = (a, b) => a.x >= b.x && a.y >= b.y && a.x + a.width <= b.x + b.width && a.y + a.height <= b.y + b.height;
    return some.filter((r, i) => !some.some((other, j) => j !== i && inside(r, other) && (!inside(other, r) || j < i))).map(r => ({
          "x": r.x,
          "y": r.y,
          "width": r.width,
          "height": r.height
        }));
  }

  // Where to move the pointer into a tiled menu ({ x, y }): the centre of
  // the rect nearest `at` (the one holding it, else the one whose centre
  // is closest), or null with none
  function aim(rects, at) {
    let best = null, bestDistance = Infinity;
    for (const r of root.union(rects)) {
      const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
      const holds = at.x >= r.x && at.x < r.x + r.width && at.y >= r.y && at.y < r.y + r.height;
      const distance = holds ? -1 : Math.hypot(cx - at.x, cy - at.y);
      if (distance < bestDistance) {
        best = {
          "x": cx,
          "y": cy
        };
        bestDistance = distance;
      }
    }
    return best;
  }
}
