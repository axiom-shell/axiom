import QtQuick
import QtTest
import qs.components.forms

// SizingNote's lines (the muted note under a Size row) against the Look &
// Feel sizes at 100%: one row per kind of sizing (zoom, linked, following,
// unlinked) and Size row, a capped and a shrunk one, and a module's line.
TestCase {
  id: root

  name: "SizingNote"

  Harness {
    id: harness
  }

  Component {
    id: noteComp

    SizingNote {}
  }

  function note(own, fit) {
    harness.configure({});
    return createTemporaryObject(noteComp, root, {
      "own": own,
      "fit": fit
    });
  }

  function test_zoom() {
    const n = root.note({
      "contentSize": 150
    }, null);
    compare(n.lineFor("contentSize"), "Content at 150% (100% × 150% here); cards zoom with it");
    compare(n.lineFor("cardSize"), "");
  }

  function test_linked() {
    const n = root.note({
      "cardSize": 150,
      "linked": true,
      "contentSize": null
    }, null);
    compare(n.lineFor("cardSize"), "Cards at 150% (100% × 150% here), content at 150% (100% × 150% here)");
    compare(n.lineFor("contentSize"), "");
  }

  function test_following() {
    const n = root.note({
      "cardSize": null,
      "linked": true,
      "contentSize": null
    }, null);
    compare(n.lineFor("cardSize"), "Cards at 100% and content at 100%, as in Look & Feel");
    compare(n.lineFor("contentSize"), "");
  }

  function test_unlinked() {
    const n = root.note({
      "cardSize": 150,
      "linked": false,
      "contentSize": 80
    }, null);
    compare(n.lineFor("cardSize"), "Cards at 150% (100% × 150% here)");
    compare(n.lineFor("contentSize"), "Content at 80% (100% × 80% here)");
  }

  function test_capped_and_shrunk() {
    const capped = root.note(null, {
      "screen": "DP-1",
      "scale": 1,
      "capped": true,
      "card": 200
    });
    compare(capped.lineFor("cardSize"), "Cards at 100% and content at 100%, as in Look & Feel · Capped at two cards high (200 px)");
    const shrunk = root.note(null, {
      "screen": "DP-1",
      "scale": 0.8,
      "capped": false,
      "card": 180
    });
    compare(shrunk.lineFor("cardSize"), "Cards at 100% and content at 100%, as in Look & Feel · Cards 180 px · Shrunk to 80% to fit DP-1");
  }

  function test_moduleLine() {
    const n = root.note(null, null);
    compare(n.moduleLine(150), "Content at 150% (100% × 100% here × 150% this module)");
    const shrunk = root.note(null, {
      "screen": "DP-1",
      "scale": 0.5,
      "capped": false,
      "card": 100
    });
    compare(shrunk.moduleLine(null), "Content at 50% (100% × 100% here × 100% this module) · Shrunk to 50% to fit DP-1");
  }
}
