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
