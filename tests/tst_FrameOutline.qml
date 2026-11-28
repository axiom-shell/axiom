import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FrameOutline"

  // A 160 x 100 screen, a 10 px border (inner side 10 px in), radius 8,
  // stroke 2
  function spec(extra) {
    return Object.assign({
      "width": 160,
      "height": 100,
      "outerLeft": 0,
      "outerTop": 0,
      "outerRight": 0,
      "outerBottom": 0,
      "innerLeft": 10,
      "innerTop": 10,
      "innerRight": 10,
      "innerBottom": 10,
      "innerBorderRadius": 8,
      "strokeWidth": 2
    }, extra);
  }

  // A rect as [x, y, width, height], as compare() doesn't compare objects
  // by value
  function r4(r) {
    return [r.x, r.y, r.width, r.height].map(v => Math.round(v * 100) / 100);
  }

  function test_corner_size() {
    compare(FrameOutline.cornerSize(spec({})), 10);
  }

  function test_inner_path() {
    compare(FrameOutline.innerPath(spec({}), 160, 100), "M 16 10 L 144 10 A 6 6 0 0 1 150 16 L 150 84 A 6 6 0 0 1 144 90 L 16 90 A 6 6 0 0 1 10 84 L 10 16 A 6 6 0 0 1 16 10 Z");
  }

  // Radius 0 and 1 with stroke 2: the arc's radius is 0 and the formula is clamped
  function test_inner_path_radius_0() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 0
    }), 160, 100), "M 10 10 L 150 10 A 0 0 0 0 1 150 10 L 150 90 A 0 0 0 0 1 150 90 L 10 90 A 0 0 0 0 1 10 90 L 10 10 A 0 0 0 0 1 10 10 Z");
  }
  function test_inner_path_radius_1() {
    compare(FrameOutline.innerPath(spec({
      "innerBorderRadius": 1
    }), 160, 100), "M 10 10 L 150 10 A 0 0 0 0 1 150 10 L 150 90 A 0 0 0 0 1 150 90 L 10 90 A 0 0 0 0 1 10 90 L 10 10 A 0 0 0 0 1 10 10 Z");
  }

  // A non-AA Rectangle's stroke on device px (the live 1.25 numbers: the
  // top stroke 7.5..10 fills rows 7, 8, 9; the bottom strip's at device 890
  // fills 890, 891)
  function test_stroke_pixels() {
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 6, 1280, 2), Qt.point(0, 0), 1.25)), r4(Qt.rect(0, 7 / 1.25, 1280, 3 / 1.25)));
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 712, 1280, 2), Qt.point(0, 712), 1.25)), r4(Qt.rect(0, 890 / 1.25, 1280, 2 / 1.25)));
  }
  function test_stroke_pixels_whole() {
    compare(r4(FrameOutline.strokePixels(Qt.rect(6, 6, 20, 2), Qt.point(0, 0), 1)), [6, 6, 20, 2]);
    compare(r4(FrameOutline.strokePixels(Qt.rect(0, 98, 160, 2), Qt.point(0, 98), 2)), [0, 98, 160, 2]);
  }
  function test_strip_stroke() {
    compare(r4(FrameOutline.stripStroke("top", 160, 8, 6, 2)), [14, 6, 132, 2]);
    compare(r4(FrameOutline.stripStroke("bottom", 160, 8, 6, 2)), [14, 0, 132, 2]);
    compare(r4(FrameOutline.stripStroke("left", 84, 8, 6, 2)), [6, 6, 2, 72]);
    compare(r4(FrameOutline.stripStroke("right", 84, 8, 6, 2)), [0, 6, 2, 72]);
  }
  function test_window_pixels() {
    compare(r4(FrameOutline.windowPixels(Qt.rect(6, 6, 8, 8), 1.25)), r4(Qt.rect(8 / 1.25, 8 / 1.25, 10 / 1.25, 10 / 1.25)));
    compare(r4(FrameOutline.windowPixels(Qt.rect(6, 6, 8, 8), 1)), [6, 6, 8, 8]);
  }

  function test_blur_region() {
    const pieces = FrameOutline.blurRegion(spec({}), 160, 100);
    compare(pieces.length, 1);
    compare(r4(pieces[0]), [0, 0, 160, 100]);
    compare(pieces[0].cuts.length, 1);
    compare(r4(pieces[0].cuts[0]), [10, 10, 140, 80]);
    compare(pieces[0].cuts[0].ellipse, false);
    compare(pieces[0].cuts[0].radius, 6);
  }
  // The cut's radius is innerPath's
  function test_blur_region_radius_0() {
    compare(FrameOutline.blurRegion(spec({
      "innerBorderRadius": 0
    }), 160, 100)[0].cuts[0].radius, 0);
  }
  function test_blur_region_radius_1() {
    compare(FrameOutline.blurRegion(spec({
      "innerBorderRadius": 1
    }), 160, 100)[0].cuts[0].radius, 0);
  }
  function test_blur_region_menus() {
    const pieces = FrameOutline.blurRegion(spec({
      "outerLeft": 4,
      "innerLeft": 14
    }), 160, 100);
    compare(r4(pieces[0]), [4, 0, 156, 100]);
    compare(r4(pieces[0].cuts[0]), [14, 10, 136, 80]);
  }

  function test_corner_box() {
    compare(r4(FrameOutline.cornerBox(spec({}), true, true)), [8, 8, 10, 10]);
    compare(r4(FrameOutline.cornerBox(spec({}), false, false)), [142, 82, 10, 10]);
  }

  // Each corner against an opening along its own edge (covering it, or
  // starting 6 px into its box / ending 4 px short of its end, short of
  // spanning it), along the perpendicular edge, and along the opposite edge
  function test_corner_covered_data() {
    const f = spec({});
    const size = FrameOutline.cornerSize(f);
    const run = (at, atStart, covers) => atStart ? {
        "start": covers ? at : at + 6,
        "end": at + 60
      } : {
        "start": at - 50,
        "end": covers ? at + size : at + size - 4
      };
    const rows = [];
    for (const c of FrameOutline.corners) {
      const box = FrameOutline.cornerBox(f, c.isLeft, c.isTop);
      const name = `${c.isTop ? "top" : "bottom"}-${c.isLeft ? "left" : "right"}`;
      const along = c.isTop ? "top" : "bottom", across = c.isLeft ? "left" : "right";
      for (const covers of [true, false]) {
        const label = covers ? "covered" : "uncovered";
        rows.push({
          "tag": `${name} along ${label}`,
          "c": c,
          "o": Object.assign({
            "edge": along
          }, run(box.x, c.isLeft, covers)),
          "covered": covers
        });
        rows.push({
          "tag": `${name} perpendicular ${label}`,
          "c": c,
          "o": Object.assign({
            "edge": across
          }, run(box.y, c.isTop, covers)),
          "covered": covers
        });
      }
      rows.push({
        "tag": `${name} opposite edge`,
        "c": c,
        "o": Object.assign({
          "edge": c.isTop ? "bottom" : "top"
        }, run(box.x, c.isLeft, true)),
        "covered": false
      });
    }
    return rows;
  }

  function test_corner_covered(data) {
    compare(FrameOutline.cornerCovered(spec({}), [data.o], data.c.isLeft, data.c.isTop), data.covered);
  }

  // The stroke less an opening at 50..70 along the strip, per edge: a 160 x
  // 100 screen, border 10, radius 8, stroke 2 (the strips' stroke rects
  // 18, 8 / 124 x 2 for top and bottom, 8, 8 / 2 x 64 for left and right,
  // in their windows). At 1.25 a piece's edges fall on the device px its
  // Rectangle fills (a pixel centred on the opening's edge is the stroke's,
  // at both ends)
  function test_screen_stroke_pieces_data() {
    const rows = [];
    const at = {
      "1": {
        "top": [[18, 8, 32, 2], [70, 8, 72, 2]],
        "bottom": [[18, 90, 32, 2], [70, 90, 72, 2]],
        "left": [[8, 18, 2, 42], [8, 80, 2, 2]],
        "right": [[150, 18, 2, 42], [150, 80, 2, 2]]
      },
      "1.25": {
        "top": [[17.6, 8, 32.8, 1.6], [69.6, 8, 72, 1.6]],
        "bottom": [[17.6, 90.4, 32.8, 1.6], [69.6, 90.4, 72, 1.6]],
        "left": [[8, 18.4, 1.6, 42.4], [8, 80, 1.6, 2.4]],
        "right": [[150.4, 18.4, 1.6, 42.4], [150.4, 80, 1.6, 2.4]]
      }
    };
    const strips = {
      "top": [160, Qt.point(0, 0)],
      "bottom": [160, Qt.point(0, 90)],
      "left": [80, Qt.point(0, 10)],
      "right": [80, Qt.point(150, 10)]
    };
    for (const dpr of [1, 1.25]) {
      for (const edge of ["top", "bottom", "left", "right"])
        rows.push({
          "tag": `${edge} at ${dpr}`,
          "edge": edge,
          "length": strips[edge][0],
          "origin": strips[edge][1],
          "dpr": dpr,
          "want": at[String(dpr)][edge]
        });
    }
    return rows;
  }

  function test_screen_stroke_pieces(data) {
    const pieces = FrameOutline.screenStrokePieces(data.edge, data.length, 10, 8, 2, [
      {
        "start": 50,
        "end": 70
      }
    ], data.origin, data.dpr);
    compare(pieces.length, data.want.length);
    for (let i = 0; i < pieces.length; i++)
      compare(r4(pieces[i]), data.want[i]);
  }
}
