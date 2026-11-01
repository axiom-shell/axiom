import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarEnds"

  readonly property var withBorder: ({
      "border": true,
      "borderWidth": 2,
      "margin": 8,
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
      "id": location + ":" + background,
      "enabled": true,
      "monitor": "DP-1",
      "extent": 30,
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

  // ---- Bars stacked on one edge ----

  function placed(bars, opts) {
    return BarEnds.withEnds(bars, opts);
  }
  function edge(bars, name, opts) {
    return BarEnds.edgeOf(BarEnds.stacksOn(placed(bars, opts), "DP-1")[name], opts);
  }

  function test_a_lone_bar_places_as_before() {
    // Pill bar inside the border: its outer edge on the stroke, reserving
    // its extent less the -borderWidth margin it reaches out by
    let [b] = placed([bar("top", "pills")], withBorder);
    compare(b.zone, 30);
    compare(b.taken, 28);
    compare(b.outer, 6);
    compare(b.frame, 36);
    verify(b.innermost && b.facesWindows && !b.offBorder);
    let e = edge([bar("top", "pills")], "top", withBorder);
    compare(e.reserved, 36);
    compare(e.frame, 36);
    compare(e.corner, 8);
    compare(e.insideTaken, 28);
    verify(!e.strip);
    // A transparent bar keeps its trim facing the windows
    [b] = placed([bar("top", "transparent")], withBorder);
    compare(b.trim, 10);
    compare(b.zone, 20);
    compare(edge([bar("top", "transparent")], "top", withBorder).reserved, 26);
    // A solid bar under the border's strip, which lies over its inner part
    [b] = placed([bar("top", "solid", {
        "insideBorder": false
      })], withBorder);
    compare(b.zone, 24);
    compare(b.outer, 0);
    compare(b.frame, 32);
    verify(!b.offBorder);
    e = edge([bar("top", "solid", {
        "insideBorder": false
      })], "top", withBorder);
    compare(e.reserved, 32);
    compare(e.frame, 32);
    compare(e.corner, 32);
    compare(e.solidZone, 24);
    verify(e.strip);
    // A solid bar reserving nothing is laid inside the border: the frame
    // line stays the border's
    e = edge([bar("top", "solid", {
        "insideBorder": false,
        "reserveSpace": false
      })], "top", withBorder);
    compare(e.reserved, 8);
    compare(e.frame, 8);
    compare(e.corner, 8);
    verify(!e.strip);
    // Borderless
    [b] = placed([bar("top", "pills", {
        "insideBorder": false
      })], borderless);
    compare(b.zone, 30);
    compare(b.outer, 0);
    compare(b.frame, 30);
    compare(edge([bar("top", "pills", {
        "insideBorder": false
      })], "top", borderless).reserved, 30);
    compare(edge([], "top", withBorder).frame, 8, "no bar: the border");
    compare(edge([], "top", borderless).frame, 0);
  }

  function test_stack_order_is_the_arrangement() {
    const bars = [bar("top", "floatingPills"), bar("top", "transparent", {
        "id": "t1"
      }), bar("top", "floating"), bar("top", "pills"), bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "transparent", {
        "id": "t2"
      }), bar("top", "pills", {
        "id": "loose",
        "reserveSpace": false
      }), bar("left", "pills")];
    const stack = BarEnds.stacksOn(bars, "DP-1").top.map(b => b.id);
    compare(stack, ["top:solid", "top:pills", "t1", "t2", "top:floating", "top:floatingPills", "loose"]);
    compare(BarEnds.edgesOn(bars, "DP-1").top.id, "loose", "the innermost");
    compare(BarEnds.edgesOn(bars, "DP-1").left.id, "left:pills");
    compare(BarEnds.edgesOn(bars, "DP-1").bottom, null);
  }

  function test_stacked_bars_lie_one_inside_the_other() {
    // Pills outside a transparent bar: the transparent bar's window lands
    // where the pill bar's reserving ends, reaching back onto its far
    // stroke as onto the border's; the pill bar, with a bar reserving
    // inside it, keeps no trim
    const [p, t] = placed([bar("top", "pills"), bar("top", "transparent")], withBorder);
    verify(!p.innermost && !p.facesWindows && !p.offBorder);
    compare(p.zone, 30);
    compare(p.frame, 36);
    verify(t.innermost && t.facesWindows && t.offBorder);
    compare(t.trim, 10);
    compare(t.zone, 20);
    compare(t.outer, 34);
    compare(t.frame, 64);
    const e = edge([bar("top", "pills"), bar("top", "transparent")], "top", withBorder);
    compare(e.reserved, 8 + 28 + 18);
    compare(e.frame, 64);
    compare(e.inner.id, "top:transparent");
    compare(e.insideTaken, 28 + 18);
    // Two transparent bars: only the inner one trims
    const [outer, inner] = placed([bar("top", "transparent", {
        "id": "a"
      }), bar("top", "transparent", {
        "id": "b"
      })], withBorder);
    compare(outer.trim, 0);
    compare(outer.zone, 30);
    compare(inner.trim, 10);
    compare(inner.outer, 8 + 28 - 2);
    // A bar reserving nothing inside: the last reserving one still trims
    const [kept] = placed([bar("top", "transparent"), bar("top", "pills", {
        "reserveSpace": false
      })], withBorder);
    compare(kept.trim, 10);
    verify(kept.facesWindows && !kept.innermost);
    // Borderless: end to end, nothing reached onto
    const [bp, bt] = placed([bar("top", "pills", {
        "insideBorder": false
      }), bar("top", "transparent", {
        "insideBorder": false
      })], borderless);
    compare(bp.frame, 30);
    compare(bt.outer, 30);
    verify(!bt.offBorder);
  }

  function test_floating_bars_stack_inside_full_ones() {
    // A floating bar is arranged last of the reserving kinds: always
    // inside a full bar on its edge, whatever the config order
    const bars = [bar("top", "floatingPills"), bar("top", "floating"), bar("top", "pills")];
    const stack = BarEnds.stacksOn(bars, "DP-1").top.map(b => b.id);
    compare(stack, ["top:pills", "top:floating", "top:floatingPills"]);
    const [fp, f, p] = placed(bars, withBorder);
    compare(p.outer, 6);
    compare(f.outer, 8 + 28 - 2);
    compare(fp.outer, 8 + 28 + 28 - 2);
    verify(f.offBorder && fp.offBorder);
  }

  function test_a_transparent_bar_yields_its_inner_bars_gap() {
    // A floating bar inside a transparent one: the transparent bar
    // reserves the float gap less, so the islands sit the transparent
    // bar's padding from its widgets, as the bar outside it does
    const [p, t, f] = placed([bar("top", "pills"), bar("top", "transparent"), bar("top", "floatingPills", {
        "floatGap": 6
      })], withBorder);
    verify(!t.facesWindows);
    compare(t.trim, 6);
    compare(t.zone, 24);
    compare(t.frame, 64, "its own popouts still grow from its inner edge");
    compare(f.outer, 8 + 28 + 22 - 2);
    // An inner accent line is an edge to see: the floating bar keeps its
    // gap from it
    const [, lined] = placed([bar("top", "pills"), bar("top", "transparent", {
        "accentLine": "inner"
      }), bar("top", "floating", {
        "floatGap": 6
      })], withBorder);
    compare(lined.trim, 0);
    // A transparent bar inside: nothing trimmed but by the innermost
    const [outer, inner] = placed([bar("top", "transparent", {
        "id": "a"
      }), bar("top", "transparent", {
        "id": "b"
      })], withBorder);
    compare(outer.trim, 0);
    compare(inner.trim, 10);
  }

  function test_the_facing_bar_reserves_last() {
    // A bar reserving nothing is innermost, but the reserved space ends
    // at the reserving bar outside it
    const bars = [bar("top", "solid"), bar("top", "transparent", {
        "reserveSpace": false
      })];
    const e = edge(bars, "top", withBorder);
    compare(e.inner.background, "transparent");
    compare(e.facing.background, "solid");
    compare(edge([bar("top", "transparent", {
        "reserveSpace": false
      })], "top", withBorder).facing.background, "transparent", "alone, it still decides");
  }

  function test_popouts_grow_out_of_the_connected_run() {
    const stack = [bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills"), bar("top", "transparent"), bar("top", "floatingPills")];
    const ids = placed(stack, withBorder).map(b => b.attachId);
    compare(ids, ["top:pills", "top:pills", "top:transparent", "top:floatingPills"]);
    // Solid bars connect to each other and on to the pills
    compare(placed([bar("top", "solid", {
        "id": "s1",
        "insideBorder": false
      }), bar("top", "solid", {
        "id": "s2",
        "insideBorder": false
      }), bar("top", "pills")], withBorder).map(b => b.attachId), ["top:pills", "top:pills", "top:pills"]);
    // A pill bar inside another pill bar strokes no outer side: no run
    compare(placed([bar("top", "pills", {
        "id": "p1"
      }), bar("top", "pills", {
        "id": "p2"
      })], withBorder).map(b => b.attachId), ["p1", "p2"]);
    // A pill bar reserving nothing is laid over, never joined
    compare(placed([bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills", {
        "reserveSpace": false
      })], withBorder).map(b => b.attachId), ["top:solid", "top:pills"]);
    // Borderless: the pills hang off the solid bar's own stroke
    compare(placed([bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills", {
        "insideBorder": false
      })], borderless).map(b => b.attachId), ["top:pills", "top:pills"]);
    // A bar alone is its own
    compare(placed([bar("top", "pills")], withBorder)[0].attachId, "top:pills");
  }

  function test_outer_popouts_cover_inner_bars() {
    const stack = placed([bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills"), bar("top", "transparent"), bar("top", "floatingPills")], withBorder);
    const [s, p, t, f] = stack;
    const size = {
      "width": 1000,
      "height": 500
    };
    const claim = (barId, rects, extra) => Object.assign({
        "kind": "bar",
        "screen": "DP-1",
        "edge": "top",
        "barId": barId,
        "footprint": rects
      }, extra ?? {});
    // The solid bar's popout, grown out of the pill bar, reaching down past
    // the floating bar: the two bars inside the pill bar give way under it
    const deep = [claim(s.id, [Qt.rect(100, 0, 200, 300)])];
    compare(BarEnds.coveredSpans(t, stack, deep, "DP-1", 0, size), [
      {
        "start": 100,
        "end": 300
      }
    ]);
    compare(BarEnds.coveredSpans(f, stack, deep, "DP-1", 0, size).length, 1);
    // ...never the bar it grows out of (its pill stretches), nor its own
    compare(BarEnds.coveredSpans(p, stack, deep, "DP-1", 0, size), []);
    compare(BarEnds.coveredSpans(s, stack, deep, "DP-1", 0, size), []);
    // A popout not reaching a bar's band leaves it
    compare(BarEnds.coveredSpans(f, stack, [claim(s.id, [Qt.rect(100, 0, 200, t.frame - 4)])], "DP-1", 0, size), []);
    // Other screens, edges and kinds, and a bar's own or inner popouts
    compare(BarEnds.coveredSpans(t, stack, [claim(s.id, [Qt.rect(0, 0, 50, 300)], {
        "screen": "HDMI-A-1"
      }), claim(s.id, [Qt.rect(0, 0, 50, 300)], {
        "kind": "menu"
      }), claim(t.id, [Qt.rect(0, 0, 50, 300)]), claim(f.id, [Qt.rect(0, 0, 50, 300)])], "DP-1", 0, size), []);
    // A bottom edge measures across from the screen's bottom
    const low = placed([bar("bottom", "pills"), bar("bottom", "floating")], withBorder);
    compare(BarEnds.coveredSpans(low[1], low, [claim(low[0].id, [Qt.rect(400, 500 - 200, 100, 200)], {
        "edge": "bottom"
      })], "DP-1", 0, size), [
      {
        "start": 400,
        "end": 500
      }
    ]);
  }

  function test_stacked_solid_bars() {
    // The border's strip lies over the inner solid bar alone: the outer
    // one reserves its whole extent, and has no stroke at its inner edge
    const bars = [bar("top", "solid", {
        "id": "s1",
        "insideBorder": false
      }), bar("top", "solid", {
        "id": "s2",
        "insideBorder": false
      })];
    const [s1, s2] = placed(bars, withBorder);
    compare(s1.zone, 30);
    compare(s1.frame, 30);
    verify(s1.offBorder);
    compare(s2.zone, 24);
    compare(s2.outer, 30);
    compare(s2.frame, 62);
    verify(!s2.offBorder);
    const e = edge(bars, "top", withBorder);
    compare(e.reserved, 62);
    compare(e.corner, 62);
    compare(e.solidZone, 54);
    // Borderless, each draws its own stroke
    const [b1, b2] = placed(bars, borderless);
    compare(b1.zone, 30);
    compare(b2.frame, 60);
    verify(!b1.offBorder && !b2.offBorder);
    // A pill bar inside a solid one lies on the border's stroke as ever
    const [s, p] = placed([bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills")], withBorder);
    compare(s.zone, 24);
    compare(p.outer, 24 + 8 - 2);
    compare(p.frame, 60);
    verify(!p.offBorder);
    compare(edge([bar("top", "solid", {
        "insideBorder": false
      }), bar("top", "pills")], "top", withBorder).corner, 32);
  }

  function test_an_end_meets_the_bars_it_makes_way_for() {
    // A top pill bar (on the longer edge) makes way for the pill bar on
    // the left (the shorter), not the transparent bar inside that: it
    // merges into the pill bar's end, its window ending past it alone
    const bars = [bar("top", "pills"), bar("left", "pills", {
        "id": "l1"
      }), bar("left", "transparent", {
        "id": "l2"
      })];
    const [top, l1, l2] = placed(bars, withBorder);
    compare(top.ends.start.kind, "pillBar");
    compare(top.ends.start.barId, "l1");
    compare(top.ends.start.from, 8 + 28);
    compare(top.ends.end.kind, "border");
    compare(top.ends.end.barId, "");
    compare(top.ends.end.from, 8);
    // The transparent bar makes way for the top bar, held clear of it
    compare(l2.ends.start.kind, "bar");
    compare(l2.ends.start.barId, "top:pills");
    compare(l2.ends.start.from, 8 + 28);
    // A bar making way for the whole stack meets its innermost
    const [side, s1, s2] = placed([bar("left", "transparent"), bar("top", "pills", {
        "id": "a"
      }), bar("top", "pills", {
        "id": "b"
      })], withBorder);
    compare(side.ends.start.barId, "b");
    compare(side.ends.start.from, 8 + 28 + 28);
    // Past solid bars: the border's stroke on the inner one, the window
    // starting past them all
    const [ls] = placed([bar("left", "pills"), bar("top", "solid", {
        "id": "s1",
        "insideBorder": false
      }), bar("top", "solid", {
        "id": "s2",
        "insideBorder": false
      })], withBorder);
    compare(ls.ends.start.kind, "border");
    compare(ls.ends.start.from, 30 + 24 + 8);
    // A solid bar meets the solid bars it makes way for, before the border
    const [st] = placed([bar("top", "solid", {
        "insideBorder": false
      }), bar("left", "solid", {
        "insideBorder": false
      })], withBorder);
    compare(st.ends.start.from, 24);
    // ...and with the border off, a pill bar joins the inner one's stroke
    const [lb] = placed([bar("left", "pills", {
        "insideBorder": false
      }), bar("top", "solid", {
        "id": "s1",
        "insideBorder": false
      }), bar("top", "solid", {
        "id": "s2",
        "insideBorder": false
      })], borderless);
    compare(lb.ends.start.kind, "solidBar");
    compare(lb.ends.start.barId, "s2");
    compare(lb.ends.start.from, 60);
  }

  function test_layer_ranks() {
    // Floating bars map before floating pills (one layer rule), then in
    // config order; each edge, rule and screen apart
    const bars = [bar("top", "floatingPills"), bar("top", "floating", {
        "id": "f1"
      }), bar("bottom", "floating", {
        "id": "f2"
      }), bar("top", "pills"), bar("top", "floating", {
        "id": "other",
        "monitor": "HDMI-A-1"
      }), bar("left", "floating", {
        "id": "short"
      }), bar("top", "floating", {
        "id": "off",
        "enabled": false
      })];
    compare(placed(bars, withBorder).map(b => b.layerRank), [1, 0, 0, 0, 0, 0, 0]);
  }
}
