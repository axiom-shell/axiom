import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SurfaceOutline"

  // Radius 28, stroke 2, connector gap 56: a fillet takes 27 along the
  // edge, its arc's run
  function spec(extra) {
    return Object.assign({
      "edge": ScreenEdge.Top,
      "boxAlong": 200,
      "boxDepth": 100,
      "strokeWidth": 2,
      "filletRadius": 28,
      "cornerRadius": 27,
      "connectorGap": 56,
      "joinStart": false,
      "joinEnd": false,
      "flushStart": false,
      "flushEnd": false,
      "detached": false,
      "detachedOffset": 0,
      "backfill": 0,
      "straight": false,
      "straightJoins": false
    }, extra);
  }

  function test_metrics_attached() {
    const m = SurfaceOutline.metrics(spec({}));
    compare(m.startMargin, 27);
    compare(m.endMargin, 27);
    compare(m.alongLength, 254);
    // A deep box starts on the attach edge
    compare(m.boxStart, 0);
    compare(m.depth, 128);
    compare(m.sideU, 28);
    compare(m.farV, 99);
  }

  function test_metrics_shallow_box_pushed_back() {
    // fillet 29 + corner 27 + half 1 - depth 20 = 37, capped at half the gap
    compare(SurfaceOutline.metrics(spec({
      "boxDepth": 20
    })).boxStart, 28);
  }

  function test_metrics_joined_and_sharp() {
    const joined = SurfaceOutline.metrics(spec({
      "joinStart": true
    }));
    compare(joined.startMargin, 0);
    verify(joined.joinFillet);
    compare(joined.depth, 156);
    const sharp = SurfaceOutline.metrics(spec({
      "filletRadius": 0
    }));
    verify(sharp.sharp);
    compare(sharp.startMargin, 0);
    verify(sharp.straightJoins);
  }

  function test_straight_join_per_end() {
    // A pill on a bare edge: straight off the screen edge at its start,
    // a fillet into a solid bar's stroke at its end
    const s = spec({
      "joinStart": true,
      "joinEnd": true,
      "straight": true,
      "straightJoins": true,
      "straightJoinEnd": false
    });
    const m = SurfaceOutline.metrics(s);
    verify(m.straightJoinStart);
    verify(!m.straightJoinEnd);
    verify(!m.straightJoins);
    verify(m.joinFillet, "the end's fillet deepens the surface");
    const fp = SurfaceOutline.footprint(s, m, m.depth, m.alongLength);
    // The box and the end's fillet square only
    compare(fp.length, 2);
    // Both ends straight: no fillet anywhere
    const both = SurfaceOutline.metrics(spec({
      "joinStart": true,
      "joinEnd": true,
      "straightJoins": true
    }));
    verify(!both.joinFillet);
  }

  function test_straight_join_runs_through_join_backfill() {
    // A submenu joined straight at its parent's bar side: its far wall
    // runs on through the row it covers past that end (joinBackfill), into
    // the squared pill it meets, rather than stopping a pixel short of it
    const s = spec({
      "joinStart": true,
      "joinEnd": true,
      "straightJoins": true,
      "joinBackfill": 1
    });
    const m = SurfaceOutline.metrics(s);
    compare(m.joinThroughStart, 1);
    compare(m.joinThroughEnd, 1);
    // Filleted joins and unjoined ends take none
    const filleted = SurfaceOutline.metrics(spec({
      "joinStart": true,
      "joinBackfill": 1
    }));
    compare(filleted.joinThroughStart, 0);
    compare(filleted.joinThroughEnd, 0);
  }

  function test_withBoxStart() {
    const s = spec({});
    const m = SurfaceOutline.withBoxStart(s, SurfaceOutline.metrics(s), 28);
    compare(m.boxStart, 28);
    compare(m.depth, 156);
    compare(m.farV, 127);
    compare(m.naturalBoxStart, 0);
  }

  function test_corners_capped_at_the_box() {
    // A shallow filleted box: the wall runs from the fillet's end (29) to
    // farV 47, so a corner gets 18 of its 27, and the box keeps its size
    const shallow = SurfaceOutline.metrics(spec({
      "boxDepth": 20
    }));
    compare(shallow.startCornerRadius, 18);
    compare(shallow.endCornerRadius, 18);
    compare(shallow.depth, 76);
    // A pill (no fillets) 30 along and 10 deep on the attach edge, radius
    // 20: capped at its depth less half the stroke, then half its length
    const s = spec({
      "boxAlong": 30,
      "boxDepth": 10,
      "cornerRadius": 20,
      "straight": true
    });
    const pill = SurfaceOutline.withBoxStart(s, SurfaceOutline.metrics(s), 0);
    compare(pill.startCornerRadius, 9);
    const along = SurfaceOutline.withBoxStart(s, SurfaceOutline.metrics(s), 20);
    compare(along.endCornerRadius, 14);
    // A box with room keeps its radius
    compare(SurfaceOutline.metrics(spec({})).startCornerRadius, 27);
  }

  function test_toItem_edges() {
    // 100 wide, 50 high; u = 10 along, v = 5 away from the edge
    compare(SurfaceOutline.toItem(ScreenEdge.Top, 100, 50, 0, 10, 5), {
      "x": 10,
      "y": 5
    });
    compare(SurfaceOutline.toItem(ScreenEdge.Bottom, 100, 50, 0, 10, 5), {
      "x": 10,
      "y": 45
    });
    compare(SurfaceOutline.toItem(ScreenEdge.Left, 50, 100, 1, 10, 5), {
      "x": 6,
      "y": 10
    });
    compare(SurfaceOutline.toItem(ScreenEdge.Right, 50, 100, 0, 10, 5), {
      "x": 45,
      "y": 10
    });
  }

  function test_footprint_attached_top() {
    const s = spec({});
    const m = SurfaceOutline.metrics(s);
    const sz = SurfaceOutline.size(s, m);
    compare(sz, {
      "width": 254,
      "height": 128
    });
    compare(SurfaceOutline.footprint(s, m, sz.width, sz.height), [
      {
        "x": 27,
        "y": 0,
        "width": 200,
        "height": 100
      },
      {
        "x": 0,
        "y": 0,
        "width": 27,
        "height": 29
      },
      {
        "x": 227,
        "y": 0,
        "width": 27,
        "height": 29
      }
    ]);
  }

  function test_footprint_bottom_is_mirrored() {
    const s = spec({
      "edge": ScreenEdge.Bottom
    });
    const m = SurfaceOutline.metrics(s);
    const fp = SurfaceOutline.footprint(s, m, 254, 128);
    // The box reaches down to the attach edge at the bottom
    compare(fp[0], {
      "x": 27,
      "y": 28,
      "width": 200,
      "height": 100
    });
    compare(fp[1].y, 99);
  }

  function test_footprint_detached_is_the_box() {
    const s = spec({
      "detached": true,
      "detachedOffset": 10
    });
    const m = SurfaceOutline.metrics(s);
    compare(SurfaceOutline.footprint(s, m, 254, 166), [
      {
        "x": 27,
        "y": 38,
        "width": 200,
        "height": 100
      }
    ]);
  }

  function test_footprint_join_and_backfill() {
    const s = spec({
      "joinEnd": true,
      "backfill": 1
    });
    const m = SurfaceOutline.metrics(s);
    const fp = SurfaceOutline.footprint(s, m, m.alongLength, m.depth);
    // The box, the start fillet, the joined end's fillet, the backfill row
    compare(fp.length, 4);
    compare(fp[2], {
      "x": 198,
      "y": 100,
      "width": 29,
      "height": 29
    });
    compare(fp[3], {
      "x": 0,
      "y": 0,
      "width": 227,
      "height": 1
    });
  }

  function test_paths() {
    const s = spec({});
    const m = SurfaceOutline.metrics(s);
    compare(SurfaceOutline.fillPath(s, m, 0, 0), "");
    const fill = SurfaceOutline.fillPath(s, m, 254, 128);
    // A filleted end's fill stops a pixel short of the stroke's flat cap
    // (here the fillet's arc reaches the end: it starts and ends on it)
    const v1 = 1 + 28 - Math.sqrt(28 * 28 - 1);
    verify(fill.startsWith("M 1 0 L 1 " + v1 + " A 28 28 0 0 1 28 29 "), fill);
    verify(fill.indexOf("A 28 28 0 0 1 253 " + v1 + " L 253 0 ") >= 0, fill);
    verify(fill.endsWith("Z"));
    // Top edge: the fillet sweeps clockwise; on the bottom edge it flips
    verify(SurfaceOutline.strokePath(s, m, 254, 128).indexOf("A 28 28 0 0 1 28 29") >= 0);
    const b = spec({
      "edge": ScreenEdge.Bottom
    });
    verify(SurfaceOutline.strokePath(b, SurfaceOutline.metrics(b), 254, 128).indexOf("A 28 28 0 0 0 28 99") >= 0);
  }

  function test_join_fill_stops_short_of_stroke_end() {
    // A joined end's fill covers the stroke it meets a pixel short of the
    // fillet's flat cap, its edge leaving the fillet's arc there (never
    // running down beside it to the cap), so it can't show through the
    // cap's soft edge
    const s = spec({
      "joinStart": true,
      "joinEnd": true
    });
    const m = SurfaceOutline.metrics(s);
    const w = m.alongLength, h = m.depth, v = m.farV + 28;
    const ju = 1 + 28 - Math.sqrt(28 * 28 - 1);
    const fill = SurfaceOutline.fillPath(s, m, w, h);
    verify(fill.startsWith("M 0 0 L 0 " + (v - 1) + " L " + ju + " " + (v - 1) + " A 28 28 0 0 1 29 " + m.farV + " "), fill);
    verify(fill.indexOf("A 28 28 0 0 1 " + (w - ju) + " " + (v - 1) + " L " + w + " " + (v - 1) + " ") >= 0, fill);
    verify(fill.indexOf(" " + v + " ") < 0, fill);
    // The stroke still runs to the stroke it meets
    verify(SurfaceOutline.strokePath(s, m, w, h).trim().endsWith((w - 1) + " " + v));
  }

  // The blur region: the fill out to the stroke's outer edge, rounded
  // where the outline is, the fillets' circles cut out of their squares
  function test_blurRegion_attached_top() {
    const s = spec({});
    const m = SurfaceOutline.metrics(s);
    const pieces = SurfaceOutline.blurRegion(s, m, 254, 128, 0, 0);
    compare(pieces.length, 3);
    const box = pieces[0];
    compare([box.x, box.y, box.width, box.height], [27, 0, 200, 100], "out to the far stroke's outer edge");
    compare([box.topLeft, box.topRight, box.bottomLeft, box.bottomRight], [0, 0, 28, 28], "the far corners, as the stroke's outer edge rounds them");
    const start = pieces[1];
    compare([start.x, start.y, start.width, start.height], [0, 0, 27, 29]);
    compare(start.cuts.length, 1);
    compare([start.cuts[0].x, start.cuts[0].y, start.cuts[0].width, start.cuts[0].height], [-27, 2, 54, 54], "the circle beyond the fillet's arc");
    verify(start.cuts[0].ellipse);
    compare([pieces[2].x, pieces[2].cuts[0].x], [227, 227]);
  }

  function test_blurRegion_bottom_is_mirrored() {
    const s = spec({
      "edge": ScreenEdge.Bottom
    });
    const pieces = SurfaceOutline.blurRegion(s, SurfaceOutline.metrics(s), 254, 128, 0, 0);
    const box = pieces[0];
    compare([box.x, box.y, box.width, box.height], [27, 28, 200, 100]);
    compare([box.topLeft, box.topRight, box.bottomLeft, box.bottomRight], [28, 28, 0, 0]);
    compare([pieces[1].y, pieces[1].cuts[0].y], [99, 72]);
  }

  function test_blurRegion_left_edge_far_corners_right() {
    const s = spec({
      "edge": ScreenEdge.Left
    });
    const box = SurfaceOutline.blurRegion(s, SurfaceOutline.metrics(s), 128, 254, 0, 0)[0];
    compare([box.x, box.y, box.width, box.height], [0, 27, 100, 200]);
    compare([box.topLeft, box.topRight, box.bottomLeft, box.bottomRight], [0, 28, 0, 28]);
  }

  function test_blurRegion_slid_is_cut_to_the_item() {
    const s = spec({});
    const pieces = SurfaceOutline.blurRegion(s, SurfaceOutline.metrics(s), 254, 128, 0, -80);
    compare(pieces.length, 1, "the fillets are behind the edge");
    compare([pieces[0].y, pieces[0].height], [0, 20]);
    compare(pieces[0].bottomLeft, 10, "a corner no bigger than what shows");
  }

  function test_blurRegion_joined_and_detached() {
    const joined = spec({
      "joinStart": true,
      "backfill": 3
    });
    const jm = SurfaceOutline.metrics(joined);
    const pieces = SurfaceOutline.blurRegion(joined, jm, jm.alongLength, jm.depth, 0, 0);
    compare([pieces[0].x, pieces[0].bottomLeft, pieces[0].bottomRight], [0, 0, 28], "the joined end runs on, square");
    const fillet = pieces.find(p => p.y === 3 + 99 && p.x === 0);
    verify(fillet !== undefined, JSON.stringify(pieces));
    compare([fillet.width, fillet.height, fillet.cuts[0].x, fillet.cuts[0].y], [29, 28, 2, 103]);
    const detached = spec({
      "detached": true,
      "detachedOffset": 10
    });
    const dm = SurfaceOutline.metrics(detached);
    const size = SurfaceOutline.size(detached, dm);
    const box = SurfaceOutline.blurRegion(detached, dm, size.width, size.height, 0, 0, {
      "start": 6,
      "end": 0
    });
    compare(box.length, 1);
    const rect = SurfaceOutline.boxRect(detached, dm, size.width, size.height);
    compare([box[0].x, box[0].y, box[0].width, box[0].height], [rect.x, rect.y, rect.width, rect.height]);
    compare([box[0].topLeft, box[0].topRight, box[0].bottomLeft, box[0].bottomRight], [6, 0, 28, 28]);
  }

  function test_placeRegion() {
    const placed = SurfaceOutline.placeRegion([
      {
        "x": 0.5,
        "y": 0,
        "width": 10,
        "height": 10,
        "topLeft": 8,
        "cuts": [
          {
            "x": 1,
            "y": 1,
            "width": 4,
            "height": 4,
            "ellipse": true
          }
        ]
      }
    ], 100, 50, {
      "x": 100,
      "y": 50,
      "width": 6,
      "height": 100
    });
    compare([placed[0].x, placed[0].y, placed[0].width, placed[0].height, placed[0].topLeft], [100, 50, 6, 10, 3]);
    compare([placed[0].cuts[0].x, placed[0].cuts[0].y], [101, 51]);
    compare(SurfaceOutline.placeRegion([
      {
        "x": 0,
        "y": 0,
        "width": 4,
        "height": 4
      }
    ], 0, 0, {
      "x": 10,
      "y": 10,
      "width": 4,
      "height": 4
    }), [], "nothing past the clip");
  }
}
