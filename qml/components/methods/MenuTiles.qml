pragma Singleton
import QtQuick

// A menu drawn as tiles (`background: none`): no box of its own, only its
// cards, each a tile with its own shadow and blur (its input is still its
// whole box, gaps included). Pure: which menus are tiled, which are held
// off their edge, and where each card's tile shows in its scrolled view.
QtObject {
  id: root

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
}
