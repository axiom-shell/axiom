pragma Singleton
import QtQuick

// How a surface's own `sizing` ({ cardSize, linked, contentSize }: each size
// a % or null for "as the level above"; a tool page's or popout's is
// { contentSize } alone) becomes the factors its host draws at, and how an
// edit of it keeps its link's meaning, and how much of its room a popout
// is shrunk to fit. The global Card and
// Content sizes are already inside the card size and Widget; hosts apply
// only these factors on top. No config, no text.
QtObject {
  id: root

  // A size setting (%) as a factor; null follows the level above: 1
  function factor(value) {
    return value === null || value === undefined ? 1 : value / 100;
  }

  // What a surface's `sizing` draws at: { card, content } factors. Linked,
  // its content grows with its cards. One without a `linked` is zoomed whole
  // (a tool page, a popout): its cards and content are the one factor
  function factors(own) {
    if (own && !("linked" in own)) {
      const zoom = root.factor(own.contentSize);
      return {
        "card": zoom,
        "content": zoom
      };
    }
    const card = root.factor(own?.cardSize);
    return {
      "card": card,
      "content": own?.linked ? card : root.factor(own?.contentSize)
    };
  }

  // What a module's content is drawn at: its grid's `zoom` times the
  // module's own Content size (`contentSize`, a % or null for none)
  function moduleZoom(zoom, contentSize) {
    return GridPlacement.zoomOf(zoom * root.factor(contentSize));
  }

  // The most (a factor, at most 1, floored to 3 decimals, at least 0.1) of
  // its size at which `size` ({ width, height }) fits `room`, as
  // GridPlacement.fitFactor does for a grid: 1 when it fits
  function fitInto(size, room) {
    const fits = Math.min(size.width > room.width ? room.width / size.width : 1, size.height > room.height ? room.height / size.height : 1);
    return fits < 1 ? Math.max(0.1, Math.floor(fits * 1000) / 1000) : 1;
  }

  // `next` (an edited sizing) with what unlinking or linking again must
  // carry: unlinked, the content keeps the size it had (the cards'), linked
  // again its own size goes. `old` is the sizing before the edit
  function edited(old, next) {
    if (!next || Boolean(old?.linked) === Boolean(next.linked))
      return next;
    return Object.assign({}, next, {
      "contentSize": next.linked ? null : next.cardSize
    });
  }

  // `edited` for the sizing at path `at` (keys) inside a bigger object, as
  // a form emits a nested edit (a menu's whole layout): `nextTop` with
  // that sizing replaced, or `nextTop` itself when nothing changes. `[]`
  // when the object is the sizing
  function editedIn(oldTop, nextTop, at) {
    if (!nextTop || at.length === 0)
      return root.edited(oldTop, nextTop);
    const inner = root.editedIn(oldTop?.[at[0]], nextTop[at[0]], at.slice(1));
    return inner === nextTop[at[0]] ? nextTop : Object.assign({}, nextTop, {
      [at[0]]: inner
    });
  }
}
