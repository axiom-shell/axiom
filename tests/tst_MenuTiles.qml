import QtQuick
import QtTest
import qs.components.methods

// A menu drawn as tiles (MenuTiles)
TestCase {
  name: "MenuTiles"

  function rect(x, y, width, height) {
    return {
      "x": x,
      "y": y,
      "width": width,
      "height": height
    };
  }

  function test_tiled() {
    verify(MenuTiles.tiled({
      "placement": "free",
      "background": "none"
    }), "a free menu");
    verify(MenuTiles.tiled({
      "placement": "edge",
      "background": "none"
    }), "an edge menu");
    verify(!MenuTiles.tiled({
      "placement": "strip",
      "background": "none"
    }), "a strip always draws its frame");
    verify(!MenuTiles.tiled({
      "placement": "free",
      "background": "panel"
    }), "a panel");
    verify(!MenuTiles.tiled(null));
  }

  function test_detached() {
    verify(!MenuTiles.detached({
      "placement": "edge",
      "background": "panel",
      "detached": false
    }), "a panel on its edge");
    verify(MenuTiles.detached({
      "placement": "edge",
      "background": "panel",
      "detached": true
    }), "held off by its setting");
    verify(MenuTiles.detached({
      "placement": "edge",
      "background": "none",
      "detached": false
    }), "tiles are held off their edge whatever `detached` says");
    verify(!MenuTiles.detached({
      "placement": "strip",
      "background": "none",
      "detached": true
    }), "a strip is never held off");
  }

  function test_close_delay_floor() {
    compare(MenuTiles.closeDelay(0, true), MenuTiles.closeFloor, "tiled: a fast crossing never closes it");
    compare(MenuTiles.closeDelay(400, true), 400, "a longer delay is kept");
    compare(MenuTiles.closeDelay(0, false), 0, "a panel closes as set");
  }

  function test_shown_cards() {
    const cards = [rect(0, 0, 100, 100), rect(0, 110, 100, 100), rect(0, 220, 100, 100), null];
    compare(MenuTiles.shown(cards, {
      "x": 0,
      "y": 50
    }, {
      "width": 100,
      "height": 200
    }), [rect(0, 0, 100, 50), rect(0, 60, 100, 100), rect(0, 170, 100, 30), null], "scrolled, cut to the view, index for index");
    compare(MenuTiles.shown([rect(0, 300, 100, 100)], {
      "x": 0,
      "y": 0
    }, {
      "width": 100,
      "height": 200
    }), [null], "out of sight");
  }

  function test_union() {
    compare(MenuTiles.union([rect(0, 0, 100, 100), null, rect(10, 10, 20, 20), rect(0, 0, 0, 40), rect(110, 0, 100, 100), rect(110, 0, 100, 100)]), [rect(0, 0, 100, 100), rect(110, 0, 100, 100)], "empty, contained and repeated rects dropped");
    compare(MenuTiles.union([rect(90, 0, 40, 20), rect(0, 0, 100, 100)]), [rect(90, 0, 40, 20), rect(0, 0, 100, 100)], "overlapping rects are both kept");
  }

  function test_aim() {
    const rects = [rect(0, 0, 100, 100), rect(120, 0, 100, 100)];
    compare(MenuTiles.aim(rects, {
      "x": 110,
      "y": 50
    }), {
      "x": 50,
      "y": 50
    }, "from a gap, the nearest card's centre (the first of two as near)");
    compare(MenuTiles.aim(rects, {
      "x": 130,
      "y": 10
    }), {
      "x": 170,
      "y": 50
    }, "the card holding it");
    compare(MenuTiles.aim([], {
      "x": 0,
      "y": 0
    }), null);
  }
}
