import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: root
  name: "Sizing"

  function test_factor() {
    compare(Sizing.factor(null), 1, "null follows the level above");
    compare(Sizing.factor(undefined), 1);
    compare(Sizing.factor(150), 1.5);
    compare(Sizing.factor(50), 0.5);
  }

  function test_moduleZoom() {
    compare(Sizing.moduleZoom(1, null), 1, "no module factor: the grid's zoom");
    compare(Sizing.moduleZoom(1.5, null), 1.5);
    compare(Sizing.moduleZoom(1, 150), 1.5, "on a page the grid zooms nothing: the factor alone");
    compare(Sizing.moduleZoom(1.25, 80), 1, "a module under a zoomed grid multiplies, snapping to 1 within 2 %");
    compare(Sizing.moduleZoom(0.8, 150), 1.2);
    compare(Sizing.moduleZoom(1, 101), 1, "within 2 % is 1");
  }

  function test_fitInto() {
    compare(Sizing.fitInto({
      "width": 300,
      "height": 200
    }, {
      "width": 400,
      "height": 400
    }), 1, "it fits: 1");
    compare(Sizing.fitInto({
      "width": 300,
      "height": 200
    }, {
      "width": 300,
      "height": 200
    }), 1, "exactly: 1");
    compare(Sizing.fitInto({
      "width": 400,
      "height": 200
    }, {
      "width": 300,
      "height": 400
    }), 0.75, "too wide: the width's share");
    compare(Sizing.fitInto({
      "width": 400,
      "height": 800
    }, {
      "width": 300,
      "height": 400
    }), 0.5, "the tighter axis wins");
    compare(Sizing.fitInto({
      "width": 300,
      "height": 100
    }, {
      "width": 100,
      "height": 100
    }), 0.333, "floored to 3 decimals, never rounded up past what fits");
    compare(Sizing.fitInto({
      "width": 1000,
      "height": 100
    }, {
      "width": 10,
      "height": 100
    }), 0.1, "at least 0.1");
    compare(Sizing.fitInto({
      "width": 0,
      "height": 0
    }, {
      "width": 0,
      "height": 0
    }), 1, "nothing to fit");
  }

  function test_factors_linked() {
    const none = Sizing.factors({
      "cardSize": null,
      "linked": true,
      "contentSize": null
    });
    compare([none.card, none.content], [1, 1], "following: 100 % over the global sizes");
    const linked = Sizing.factors({
      "cardSize": 120,
      "linked": true,
      "contentSize": 80
    });
    compare([linked.card, linked.content], [1.2, 1.2], "linked: the content grows with the cards, its own value unused");
  }

  function test_factors_unlinked() {
    const own = Sizing.factors({
      "cardSize": 150,
      "linked": false,
      "contentSize": 100
    });
    compare([own.card, own.content], [1.5, 1]);
    const content = Sizing.factors({
      "cardSize": null,
      "linked": false,
      "contentSize": 75
    });
    compare([content.card, content.content], [1, 0.75], "each set alone");
  }

  function test_factors_whole_surface() {
    const zoomed = Sizing.factors({
      "contentSize": 80
    });
    compare([zoomed.card, zoomed.content], [0.8, 0.8], "no link: cards and content are the one factor");
    const following = Sizing.factors({
      "contentSize": null
    });
    compare([following.card, following.content], [1, 1], "following: 100 % over the global size");
  }

  function test_factors_without_a_sizing() {
    compare(Sizing.factors(null), {
      "card": 1,
      "content": 1
    });
    compare(Sizing.factors(undefined), {
      "card": 1,
      "content": 1
    });
  }

  // Unlinking keeps the content at the size it had; linking again drops it
  function test_edited() {
    const linked = {
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    };
    const unlinked = Sizing.edited(linked, Object.assign({}, linked, {
      "linked": false
    }));
    compare(unlinked, {
      "cardSize": 150,
      "linked": false,
      "contentSize": 150
    }, "the content stays at the cards' size");
    compare(Sizing.edited(unlinked, Object.assign({}, unlinked, {
      "linked": true
    })), {
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    }, "linked again: its own size goes");
    compare(Sizing.edited({
      "cardSize": null,
      "linked": true,
      "contentSize": null
    }, {
      "cardSize": null,
      "linked": false,
      "contentSize": null
    }).contentSize, null, "following stays following");
  }

  function test_edited_other_edits_pass_through() {
    const old = {
      "cardSize": 150,
      "linked": false,
      "contentSize": 90
    };
    const next = Object.assign({}, old, {
      "contentSize": 110
    });
    verify(Sizing.edited(old, next) === next, "the same object, nothing carried");
    const moved = {
      "cardSize": 120,
      "linked": false,
      "contentSize": 90
    };
    verify(Sizing.edited(old, moved) === moved);
    compare(Sizing.edited(old, null), null);
  }

  function test_editedIn_the_sizing_itself() {
    const old = {
      "cardSize": 80,
      "linked": true,
      "contentSize": null
    };
    compare(Sizing.editedIn(old, Object.assign({}, old, {
      "linked": false
    }), []).contentSize, 80);
  }

  // A form emits a nested edit as the whole top-level object
  function test_editedIn_nested() {
    const old = {
      "grid": {
        "fine": false
      },
      "sizing": {
        "cardSize": 150,
        "linked": true,
        "contentSize": null
      }
    };
    const next = {
      "grid": {
        "fine": false
      },
      "sizing": {
        "cardSize": 150,
        "linked": false,
        "contentSize": null
      }
    };
    const result = Sizing.editedIn(old, next, ["sizing"]);
    compare(result.sizing.contentSize, 150);
    compare(result.grid, next.grid, "the rest is kept");
    compare(next.sizing.contentSize, null, "the argument isn't mutated");
    const other = {
      "grid": {
        "fine": true
      },
      "sizing": old.sizing
    };
    verify(Sizing.editedIn(old, other, ["sizing"]) === other, "an edit elsewhere returns the object itself");
  }

  function test_editedIn_missing_parts() {
    const next = {
      "grid": {
        "fine": true
      }
    };
    verify(Sizing.editedIn(null, next, ["sizing"]) === next, "no sizing at all");
    compare(Sizing.editedIn(null, null, ["sizing"]), null);
  }

  // Card and Content differ globally (Look & Feel: 120% and 90%)
  readonly property var _global: ({
      "card": 120,
      "content": 90
    })

  function test_breakdown_linked_keeps_card_and_content_totals_apart() {
    const b = Sizing.breakdown({
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    }, root._global, null, false);
    compare(b.kind, "linked");
    compare(b.card.global, 120);
    compare(b.card.here, 150);
    compare(b.card.total, 180);
    compare(b.content.global, 90);
    compare(b.content.here, 150, "linked: its content grows with its cards");
    compare(b.content.total, 135, "the global Content size, not the Card size");
    verify(!b.shrunk);
    verify(!b.capped);
  }

  function test_breakdown_global_card_not_content() {
    const b = Sizing.breakdown({
      "cardSize": 100,
      "linked": true,
      "contentSize": null
    }, root._global, null, false);
    compare([b.card.total, b.content.total], [120, 90], "100% here: each its own global size");
  }

  function test_breakdown_following() {
    for (const own of [null, undefined,
      {
        "cardSize": null,
        "linked": true,
        "contentSize": null
      }
    ]) {
      const b = Sizing.breakdown(own, root._global, null, false);
      compare(b.kind, "following");
      compare([b.card.total, b.content.total], [120, 90], "the global sizes alone");
      compare([b.card.here, b.content.here], [100, 100]);
    }
  }

  function test_breakdown_unlinked_set_by_hand() {
    const b = Sizing.breakdown({
      "cardSize": 80,
      "linked": false,
      "contentSize": 120
    }, root._global, null, false);
    compare(b.kind, "unlinked");
    compare([b.card.here, b.card.total], [80, 96]);
    compare([b.content.here, b.content.total], [120, 108]);
    const own = Sizing.breakdown({
      "cardSize": null,
      "linked": false,
      "contentSize": null
    }, root._global, null, false);
    compare(own.kind, "unlinked", "both unset and unlinked is still unlinked");
    compare([own.card.total, own.content.total], [120, 90]);
  }

  function test_breakdown_whole_surface_zoom() {
    const b = Sizing.breakdown({
      "contentSize": 80
    }, root._global, null, false);
    compare(b.kind, "zoom", "no linked: a tool page or a built-in popout");
    compare([b.card.here, b.content.here], [80, 80]);
    compare(b.content.total, 72);
    compare(b.card.total, 96, "its cards zoom with it");
  }

  function test_breakdown_fit_and_cap() {
    const own = {
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    };
    const fits = Sizing.breakdown(own, root._global, 1, false);
    verify(!fits.shrunk);
    compare(fits.shrunkTo, 100);
    const shrunk = Sizing.breakdown(own, root._global, 0.8, true);
    verify(shrunk.shrunk);
    compare(shrunk.shrunkTo, 80);
    verify(shrunk.capped);
    compare(shrunk.card.total, 180, "the fit is its own clause, not in the totals");
    verify(!Sizing.breakdown(own, root._global, 0.9995, false).shrunk, "a hair under 1 is no shrink");
    verify(!Sizing.breakdown(own, root._global, 0.996, false).shrunk, "rounds to 100%: no shrink to name");
  }

  function test_shrinkOf_is_the_one_rule() {
    compare(Sizing.shrinkOf(null), {
      "shrunkTo": 100,
      "shrunk": false
    });
    compare(Sizing.shrinkOf(0.996), {
      "shrunkTo": 100,
      "shrunk": false
    }, "rounds to 100%: not shrunk, so no page says 'Shrunk to 100%'");
    compare(Sizing.shrinkOf(0.994), {
      "shrunkTo": 99,
      "shrunk": true
    });
  }

  function test_breakdown_tool_page_fit() {
    // A tool page's fit is what its OverlayPages reported (OverlayManager.reportFit)
    const b = Sizing.breakdown({
      "contentSize": 100
    }, root._global, 0.6, false);
    compare(b.kind, "zoom");
    compare(b.shrunkTo, 60);
    verify(b.shrunk);
  }

  function test_moduleBreakdown_includes_its_surface_fit() {
    const own = {
      "cardSize": 120,
      "linked": true,
      "contentSize": null
    };
    const plain = Sizing.moduleBreakdown(own, root._global, null, 150);
    compare([plain.global, plain.here, plain.module, plain.total], [90, 120, 150, 162]);
    const fitted = Sizing.moduleBreakdown(own, root._global, 0.5, 150);
    compare([fitted.here, fitted.module, fitted.shrunkTo, fitted.total], [120, 150, 50, 81], "here is the surface's own factor; the fit is in the total");
    verify(fitted.shrunk);
    verify(!plain.shrunk);
    const none = Sizing.moduleBreakdown(null, root._global, null, null);
    compare([none.here, none.module, none.total], [100, 100, 90], "no sizing and no module Content size: the global size");
  }

  function test_tightest() {
    compare(Sizing.tightest([]), null);
    const a = {
      "screen": "A",
      "scale": 0.8,
      "capped": false,
      "card": 400
    };
    const b = {
      "screen": "B",
      "scale": 0.6,
      "capped": false,
      "card": 500
    };
    compare(Sizing.tightest([a, b]).screen, "B", "the smallest scale");
    compare(Sizing.tightest([b, a]).screen, "B");
    const c = {
      "screen": "C",
      "scale": 0.6,
      "capped": true,
      "card": 300
    };
    compare(Sizing.tightest([b, c]).screen, "C", "equal scales: the smaller card");
    compare(Sizing.tightest([c, b]).screen, "C");
  }

  function test_popoutLayout() {
    const card = 100;
    const big = Sizing.popoutLayout(null, card, {
      "width": 800,
      "height": 600
    }, {
      "width": 400,
      "height": 600
    });
    compare([big.fit, big.zoom, big.unit], [0.5, 0.5, card], "a popout too big for its screen shrinks at 100%");
    const fits = Sizing.popoutLayout({
      "contentSize": 150
    }, card, {
      "width": 200,
      "height": 100
    }, {
      "width": 1000,
      "height": 1000
    });
    compare([fits.fit, fits.zoom, fits.unit], [1, 1.5, card], "fits: no shrink; the layout unit is the drawn card over the zoom");
    const linked = Sizing.popoutLayout({
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    }, card, {
      "width": 400,
      "height": 400
    }, {
      "width": 300,
      "height": 300
    });
    compare([linked.fit, linked.zoom, linked.unit], [0.5, 0.75, card], "the fit never reaches the unit");
  }
}
