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
}
