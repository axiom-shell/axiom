pragma Singleton
import QtQuick

// How a surface's own `sizing` ({ cardSize, linked, contentSize }: each size
// a % or null for "as the level above"; a tool page's or popout's is
// { contentSize } alone) becomes the factors its host draws at (factors,
// moduleZoom), how much of its room it is shrunk to fit (fitInto, and
// popoutLayout for a popout), how an edit of it keeps its link's meaning
// (edited, editedIn), and the numbers of the line that says it all
// (breakdown, moduleBreakdown). The global Card and Content sizes are
// already inside the card size and Widget; hosts apply only these factors
// on top. No config, no text.
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

  // The numbers behind a Size row's line, in whole %: `own` (the surface's
  // `sizing`), `global` ({ card, content }: the Look & Feel sizes in %), the
  // `fit` (a factor, at most 1; null for none) the surface is shrunk by and
  // whether its height `capped` its cards. { kind, card, content, fit,
  // shrunk, capped }: `kind` is how it combines, "zoom" (no `linked`: the
  // whole surface zooms), "linked", "unlinked" or "following" (linked, its
  // Card size unset: the global sizes alone); `card` and `content` each
  // { global, here (the surface's factor), total } with total = global ×
  // here, so the two differ where the global sizes do. The fit is not in
  // the totals: it is its own clause (the cap is drawn px only)
  function breakdown(own, global, fit, capped) {
    const factors = root.factors(own);
    const shrinks = fit ?? 1;
    let kind = "following";
    if (own && !("linked" in own))
      kind = "zoom";
    else if (own && !own.linked)
      kind = "unlinked";
    else if (own && own.cardSize !== null && own.cardSize !== undefined)
      kind = "linked";
    return {
      "kind": kind,
      "card": root._level(global.card, factors.card),
      "content": root._level(global.content, factors.content),
      "fit": Math.round(shrinks * 100),
      "shrunk": Math.round(shrinks * 100) < 100,
      "capped": capped
    };
  }

  // `breakdown` for a module's Content size (`contentSize`, a % or null)
  // on that surface: its `content` is { global, here (the surface's own
  // content factor, as its line shows), module, fit, shrunk (as breakdown),
  // total }; the total has the surface's fit in, as that is what its
  // modules are drawn at
  function moduleBreakdown(own, global, fit, contentSize) {
    const factors = root.factors(own);
    const shrinks = fit ?? 1;
    const module = root.factor(contentSize);
    return {
      "content": Object.assign(root._level(global.content, factors.content), {
        "module": Math.round(module * 100),
        "fit": Math.round(shrinks * 100),
        "shrunk": Math.round(shrinks * 100) < 100,
        "total": Math.round(global.content * factors.content * shrinks * module)
      })
    };
  }

  // How a popout lays out and draws: `own` its `sizing` (or null), `card`
  // the card unit on its screen, `content` ({ width, height }: the most its
  // layout size will be) and `room` ({ width, height }: the px the screen
  // has for it). { zoom, unit, fit } as PopoutsConfig.layoutOf describes
  function popoutLayout(own, card, content, room) {
    const factors = root.factors(own);
    const zoom = GridPlacement.zoomOf(factors.content);
    const fit = root.fitInto({
      "width": content.width * zoom,
      "height": content.height * zoom
    }, room);
    return {
      "zoom": GridPlacement.zoomOf(factors.content * fit),
      "unit": card * factors.card / zoom,
      "fit": fit
    };
  }

  // { global, here, total } in whole %: one size's global % and the
  // surface's `factor` of it
  function _level(global, factor) {
    return {
      "global": Math.round(global),
      "here": Math.round(factor * 100),
      "total": Math.round(global * factor)
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
