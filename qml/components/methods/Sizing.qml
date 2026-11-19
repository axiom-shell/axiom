pragma Singleton
import QtQuick

// What a surface's own `sizing` ({ cardSize, linked, contentSize }: each size
// a % or null for "as the level above"; a tool page's or popout's is
// { contentSize } alone) comes to. The global Card and Content sizes are
// already inside the card size and Widget; hosts apply only these factors
// on top. No config, no text.
//   factors, moduleZoom: the factors its host draws at
//   fitInto, popoutLayout: how much of its room it is shrunk to fit
//   edited, editedIn: how an edit keeps its link's meaning
//   breakdown, moduleBreakdown, shrinkOf: the numbers of the line that says it all
//   tightest: which of a page's fits shrinks it most
QtObject {
  id: root

  // A size setting (%) as a factor; null follows the level above: 1
  function factor(value) {
    return value === null || value === undefined ? 1 : value / 100;
  }

  // A sizing without a `linked` zooms its whole surface (a tool page, a popout)
  function _zooms(own) {
    return !!own && !("linked" in own);
  }

  // What a surface's `sizing` draws at: { card, content } factors. Linked,
  // its content grows with its cards. One without a `linked` is zoomed whole
  // (a tool page, a popout): its cards and content are the one factor
  function factors(own) {
    if (root._zooms(own)) {
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
  // its size at which `size` ({ width, height }) fits `room`: per axis,
  // GridPlacement.fitLength, as fitFactor does for a grid; 1 when it fits
  function fitInto(size, room) {
    return Math.min(GridPlacement.fitLength(size.width, room.width), GridPlacement.fitLength(size.height, room.height));
  }

  // The entry of `fits` ([{ screen, scale, capped, card }], OverlayManager.fitOf's)
  // that shrinks most, the smallest cards where equal; null for none
  function tightest(fits) {
    return fits.reduce((tight, fit) => tight === null || fit.scale < tight.scale || (fit.scale === tight.scale && fit.card < tight.card) ? fit : tight, null);
  }

  // The numbers behind a Size row's line, in whole %: `own` (the surface's
  // `sizing`), `global` ({ card, content }: the Look & Feel sizes in %), the
  // `fitScale` (a factor, at most 1; null for none) the surface is shrunk by
  // and whether its height `capped` its cards. { kind, card, content,
  // shrunkTo (whole %), shrunk, capped }: `kind` is how it combines, "zoom"
  // (no `linked`: the whole surface zooms), "linked", "unlinked" or
  // "following" (linked, its Card size unset: the global sizes alone); `card`
  // and `content` each { global, here (the surface's factor), total } with
  // total = global × here, so the two differ where the global sizes do. The
  // fit is not in the totals: it is its own clause (the cap is drawn px only)
  function breakdown(own, global, fitScale, capped) {
    const factors = root.factors(own);
    let kind = "following";
    if (root._zooms(own))
      kind = "zoom";
    else if (own && !own.linked)
      kind = "unlinked";
    else if (own && own.cardSize !== null && own.cardSize !== undefined)
      kind = "linked";
    return Object.assign({
      "kind": kind,
      "card": root._level(global.card, factors.card),
      "content": root._level(global.content, factors.content),
      "capped": capped
    }, root.shrinkOf(fitScale));
  }

  // `breakdown` for a module's Content size (`contentSize`, a % or null)
  // on that surface: its `content` is { global, here (the surface's own
  // content factor, as its line shows), module, shrunkTo, shrunk (as
  // breakdown), total }; the total has the surface's fit in, as that is
  // what its modules are drawn at
  function moduleBreakdown(own, global, fitScale, contentSize) {
    const factors = root.factors(own);
    const module = root.factor(contentSize);
    return Object.assign(root._level(global.content, factors.content), {
      "module": Math.round(module * 100),
      "total": Math.round(global.content * factors.content * (fitScale ?? 1) * module)
    }, root.shrinkOf(fitScale));
  }

  // How a popout lays out and draws: `own` its `sizing` (or null), `card`
  // the card unit on its screen, `content` ({ width, height }: the most its
  // layout size will be) and `room` ({ width, height }: the px the screen
  // has for it). { zoom, unit, fit } as PopoutsConfig.layoutFor describes
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

  // A fit (a factor, null for none) as { shrunkTo: whole %, shrunk: below 100 }:
  // the one rule for "is it shrunk"
  function shrinkOf(fitScale) {
    const shrunkTo = Math.round((fitScale ?? 1) * 100);
    return {
      "shrunkTo": shrunkTo,
      "shrunk": shrunkTo < 100
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
