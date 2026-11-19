import QtQuick
import QtTest
import qs.components.methods

TestCase {
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
}
