pragma Singleton
import QtQuick

// How a surface's own `sizing` ({ cardSize, linked, contentSize }: each size
// a % or null for "as the level above") becomes the factors its host draws
// at, and how an edit of it keeps its link's meaning. The global Card and
// Content sizes are already inside the card size and Widget; hosts apply
// only these factors on top. No config, no text.
QtObject {
  id: root

  // A size setting (%) as a factor; null follows the level above: 1
  function factor(value) {
    return value === null || value === undefined ? 1 : value / 100;
  }

  // What a surface's `sizing` draws at: { card, content } factors. Linked,
  // its content grows with its cards
  function factors(own) {
    const card = root.factor(own?.cardSize);
    return {
      "card": card,
      "content": own?.linked ? card : root.factor(own?.contentSize)
    };
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
