import QtQuick
import QtTest
import qs.components.methods

// Where a free menu's box goes (FreeMenuPlace)
TestCase {
  name: "FreeMenuPlace"

  // A 1000 × 600 screen with a 40 px bar on top (plus a 10 px gap) and
  // 10 px kept at the other edges
  function params(extra) {
    return Object.assign({
      "width": 1000,
      "height": 600,
      "insets": {
        "top": 50,
        "bottom": 10,
        "left": 10,
        "right": 10
      },
      "box": {
        "width": 200,
        "height": 100
      },
      "opener": null,
      "anchor": {
        "at": "centre",
        "x": 50,
        "y": 50
      },
      "cursor": null
    }, extra);
  }

  function test_centre_of_the_free_area() {
    compare(FreeMenuPlace.place(params({})), {
      "x": 400,
      "y": 270,
      "slideFrom": "bottom"
    }, "centred between the insets, sliding from the nearest edge");
  }

  function test_point() {
    const at = FreeMenuPlace.place(params({
      "anchor": {
        "at": "point",
        "x": 80,
        "y": 70
      }
    }));
    compare(at.x, 700, "centre at 80 % across");
    compare(at.y, 370, "centre at 70 % down");
    compare(at.slideFrom, "bottom");
  }

  function test_point_clamped_clear_of_the_bar() {
    const at = FreeMenuPlace.place(params({
      "anchor": {
        "at": "point",
        "x": 0,
        "y": 0
      }
    }));
    compare(at.x, 10);
    compare(at.y, 50, "kept below the bar's inset");
  }

  function test_cursor() {
    const at = FreeMenuPlace.place(params({
      "anchor": {
        "at": "cursor",
        "x": 50,
        "y": 50
      },
      "cursor": {
        "x": 900,
        "y": 550
      }
    }));
    compare(at.x, 790, "clamped at the right inset");
    compare(at.y, 490, "clamped at the bottom inset");
    compare(at.slideFrom, "bottom");
  }

  function test_cursor_unknown_centres() {
    const at = FreeMenuPlace.place(params({
      "anchor": {
        "at": "cursor",
        "x": 50,
        "y": 50
      }
    }));
    compare(at.x, 400);
    compare(at.y, 270);
  }

  function test_at_its_widget() {
    const top = FreeMenuPlace.place(params({
      "opener": {
        "x": 860,
        "y": 5,
        "width": 30,
        "height": 30,
        "edge": "top"
      }
    }));
    compare(top, {
      "x": 775,
      "y": 50,
      "slideFrom": "top"
    }, "centred on the widget, flush with the bar's inset");
    const clamped = FreeMenuPlace.place(params({
      "opener": {
        "x": 980,
        "y": 5,
        "width": 20,
        "height": 20,
        "edge": "top"
      }
    }));
    compare(clamped.x, 790, "kept on the screen");
    const left = FreeMenuPlace.place(params({
      "insets": {
        "top": 10,
        "bottom": 10,
        "left": 50,
        "right": 10
      },
      "opener": {
        "x": 5,
        "y": 300,
        "width": 30,
        "height": 40,
        "edge": "left"
      }
    }));
    compare(left, {
      "x": 50,
      "y": 270,
      "slideFrom": "left"
    });
    const bottom = FreeMenuPlace.place(params({
      "opener": {
        "x": 100,
        "y": 570,
        "width": 30,
        "height": 30,
        "edge": "bottom"
      }
    }));
    compare(bottom.y, 490, "on a bottom bar it sits above it");
    compare(bottom.x, 15);
    compare(bottom.slideFrom, "bottom");
  }

  function test_too_big_keeps_its_start() {
    const at = FreeMenuPlace.place(params({
      "box": {
        "width": 1200,
        "height": 800
      }
    }));
    compare(at.x, 10);
    compare(at.y, 50);
  }

  function test_nearestEdge() {
    compare(FreeMenuPlace.nearestEdge(500, 10, 1000, 600), "top");
    compare(FreeMenuPlace.nearestEdge(500, 590, 1000, 600), "bottom");
    compare(FreeMenuPlace.nearestEdge(5, 300, 1000, 600), "left");
    compare(FreeMenuPlace.nearestEdge(995, 300, 1000, 600), "right");
    compare(FreeMenuPlace.nearestEdge(300, 300, 600, 600), "top", "ties go to the first");
  }
}
