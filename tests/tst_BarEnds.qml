import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarEnds"

  readonly property var withBorder: ({
      "border": true,
      "borderWidth": 2,
      "gapsOut": {
        "top": 10,
        "bottom": 10,
        "left": 10,
        "right": 10
      },
      "floatGaps": {
        "top": 10,
        "bottom": 10,
        "left": 10,
        "right": 10
      }
    })
  readonly property var borderless: Object.assign({}, withBorder, {
    "border": false
  })

  // An enriched bar, as far as BarEnds reads it
  function bar(location, background, extra) {
    const vertical = location === "left" || location === "right";
    const solid = background === "solid";
    return Object.assign({
      "enabled": true,
      "monitor": "DP-1",
      "reserveSpace": true,
      "background": background,
      "solid": solid,
      "island": background === "floating" || background === "floatingPills",
      "insideBorder": !solid,
      "floatGap": 0,
      "floatGapAuto": true,
      "trim": background === "transparent" ? 10 : 0,
      "vertical": vertical,
      // A landscape screen: the side bars lie along its shorter edges
      "shortEdge": vertical,
      "top": location === "top",
      "bottom": location === "bottom",
      "left": location === "left",
      "right": location === "right"
    }, extra ?? {});
  }

  function ends(bars, opts) {
    return BarEnds.withEnds(bars, opts).map(b => b.ends);
  }

  function test_alone_meets_the_frame() {
    const [e] = ends([bar("right", "pills")], withBorder);
    compare(e.start.kind, "border");
    compare(e.end.kind, "border");
    verify(e.end.joinable && !e.end.straight && !e.end.held);
    compare(e.end.reach, 2);
    const [bare] = ends([bar("right", "pills", {
        "insideBorder": false
      })], borderless);
    compare(bare.end.kind, "bare");
    verify(bare.end.straight);
    compare(bare.end.reach, 0);
  }

  function test_on_short_edge() {
    verify(BarEnds.onShortEdge(true, 2560, 1440), "a side bar on landscape");
    verify(!BarEnds.onShortEdge(false, 2560, 1440));
    verify(BarEnds.onShortEdge(false, 1440, 2560), "a top bar on portrait");
    verify(!BarEnds.onShortEdge(true, 1440, 2560));
    verify(BarEnds.onShortEdge(true, 1000, 1000), "a side bar on a square screen");
    verify(!BarEnds.onShortEdge(false, 1000, 1000));
  }

  function test_same_kind_short_edge_wins() {
    const [side, bottom] = ends([bar("right", "floatingPills"), bar("bottom", "floatingPills")], withBorder);
    compare(bottom.end.kind, "bar", "the bottom bar, the longer, yields at its end");
    verify(bottom.end.held && !bottom.end.joinable);
    compare(bottom.end.reach, 0);
    compare(bottom.start.kind, "border", "its other end is untouched");
    compare(side.end.kind, "border", "the side bar keeps the corner");
    // On a portrait screen the top and bottom bars are the shorter
    const [pSide, pBottom] = ends([bar("right", "floatingPills", {
        "shortEdge": false
      }), bar("bottom", "floatingPills", {
        "shortEdge": true
      })], withBorder);
    compare(pSide.end.kind, "bar", "the side bar yields on portrait");
    compare(pBottom.end.kind, "border");
  }

  function test_kinds_in_order() {
    // floating < transparent < pills < solid, whatever the edges
    const kinds = ["floating", "transparent", "pills", "solid"];
    for (let i = 0; i < kinds.length; i++) {
      for (let j = 0; j < kinds.length; j++) {
        if (i === j)
          continue;
        const lower = bar("right", kinds[i]), higher = bar("bottom", kinds[j]);
        compare(BarEnds.yieldsTo(lower, higher), i < j, kinds[i] + " vs " + kinds[j]);
      }
    }
    verify(BarEnds.yieldsTo(bar("right", "floatingPills"), bar("bottom", "transparent")), "floating pills are floating");
  }

  function test_pill_bars_merge_at_their_corner() {
    for (const opts of [withBorder, borderless]) {
      const [side, bottom] = ends([bar("right", "pills"), bar("bottom", "pills")], opts);
      compare(bottom.end.kind, "pillBar", "the bottom bar joins the side bar's pills");
      verify(bottom.end.joinable && !bottom.end.held && !bottom.end.straight);
      compare(bottom.end.reach, 2, "onto their far stroke");
      compare(side.end.kind, opts.border ? "border" : "bare", "the side bar keeps the corner");
    }
    const [held] = ends([bar("right", "floatingPills"), bar("bottom", "pills")], withBorder);
    compare(held.end.kind, "bar", "a floating side bar stays held");
  }

  function test_transparent_always_yields() {
    // Screenshot: pills on the right, transparent along the bottom
    const [side, bottom] = ends([bar("right", "pills"), bar("bottom", "transparent")], withBorder);
    compare(side.end.kind, "border");
    compare(bottom.end.kind, "bar");
    verify(bottom.end.held);
    // Its window ends at the pill bar's reserved line, which is its edge
    compare(bottom.end.over, 0);
    compare(bottom.end.gap, 10);
    // Borderless: pills on the left, transparent along the top
    const [left, top] = ends([bar("left", "pills", {
        "insideBorder": false
      }), bar("top", "transparent", {
        "insideBorder": false
      })], borderless);
    compare(left.start.kind, "bare");
    compare(top.start.kind, "bar");
  }

  function test_held_gap_past_a_transparent_bar() {
    // A transparent bar reserves gaps_out short of its edge: the window
    // runs on that far into it, and windows start right at its edge
    const [, bottom] = ends([bar("left", "transparent"), bar("bottom", "transparent")], withBorder);
    compare(bottom.start.over, 10);
    compare(bottom.start.gap, 0);
    // A floating bar's own float gap past a bar it yields to
    const [island] = ends([bar("left", "floating", {
        "floatGap": 6,
        "floatGapAuto": false
      }), bar("bottom", "pills")], withBorder);
    compare(island.end.kind, "bar");
    compare(island.end.over, 0);
    compare(island.end.gap, 6);
    // ...and past a transparent one, which keeps the corner
    const [under, owner] = ends([bar("left", "floating"), bar("bottom", "transparent")], withBorder);
    compare(owner.start.kind, "border");
    compare(under.end.kind, "bar");
    compare(under.end.over, 10);
  }

  function test_automatic_float_gap_without_a_backend() {
    // No backend: gaps_out is 0, a floating bar's Automatic gap the margin
    const opts = Object.assign({}, withBorder, {
      "gapsOut": {
        "top": 0,
        "bottom": 0,
        "left": 0,
        "right": 0
      },
      "floatGaps": {
        "top": 8,
        "bottom": 8,
        "left": 8,
        "right": 8
      }
    });
    const [island] = ends([bar("left", "floating"), bar("bottom", "pills")], opts);
    compare(island.end.gap, 8, "a floating bar keeps the margin");
    const [pills] = ends([bar("left", "transparent"), bar("bottom", "pills")], opts);
    compare(pills.end.gap, 0, "any other bar keeps gaps_out");
  }

  function test_solid_owns_its_corners() {
    const [side, bottom] = ends([bar("right", "solid", {
        "insideBorder": false
      }), bar("bottom", "pills")], withBorder);
    compare(side.end.kind, "border");
    // Inside the border, the bottom bar meets the border's stroke, which
    // lies on the solid bar
    compare(bottom.end.kind, "border");
    verify(bottom.end.joinable && !bottom.end.held);
    compare(bottom.end.reach, 2);
  }

  function test_borderless_joins_a_solid_bars_stroke() {
    // Pills on the left meeting a solid bottom bar curve into its stroke
    const [side] = ends([bar("left", "pills", {
        "insideBorder": false
      }), bar("bottom", "solid", {
        "insideBorder": false
      })], borderless);
    compare(side.end.kind, "solidBar");
    verify(side.end.joinable && !side.end.straight);
    compare(side.end.reach, 2);
    compare(side.start.kind, "bare");
    verify(side.start.straight);
  }

  function test_nothing_yields_to_a_bar_reserving_nothing() {
    const [side] = ends([bar("right", "transparent"), bar("bottom", "pills", {
        "reserveSpace": false
      })], withBorder);
    compare(side.end.kind, "border");
  }

  function test_other_screens_and_disabled_bars_ignored() {
    const [side] = ends([bar("right", "transparent"), bar("bottom", "pills", {
        "monitor": "HDMI-A-1"
      }), bar("top", "pills", {
        "enabled": false
      })], withBorder);
    compare(side.start.kind, "border");
    compare(side.end.kind, "border");
  }
}
