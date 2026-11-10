import QtQuick
import QtTest
import qs.components.methods

// What a new edge menu starts as (MenuSeeds)
TestCase {
  name: "MenuSeeds"

  function test_edge() {
    compare(MenuSeeds.seed("edge", "menu-1", "Menu 1"), {
      "id": "menu-1",
      "name": "Menu 1",
      "layout": {
        "modules": []
      },
      "placement": "edge",
      "open": {
        "onHover": true
      }
    }, "on its edge, opening on hover");
  }

  function test_free() {
    for (const purpose of ["popout", "submenu"]) {
      const menu = MenuSeeds.seed(purpose, "menu-2", "Menu 2");
      compare(menu.placement, "free", purpose);
      compare(menu.open, undefined, purpose + " leaves opening at the defaults");
      compare(menu.freeAnchor, undefined, purpose + " opens where its opener puts it");
      compare(menu.close, undefined, purpose + " closes as the defaults say");
    }
  }

  function test_floating() {
    const menu = MenuSeeds.seed("free", "menu-3", "Menu 3");
    compare(menu.placement, "free");
    compare(menu.freeAnchor, {
      "at": "centre"
    }, "a floating one opens at the screen's centre");
    compare(menu.close, {
      "onLeave": false,
      "onOutsideClick": true
    }, "it stays open when the pointer leaves, and a click outside closes it");
    compare(MenuSeeds.seed("key", "m", "M").placement, "edge", "no keybind purpose any more");
  }

  function test_unknown() {
    compare(MenuSeeds.seed(undefined, "m", "M").placement, "edge", "no purpose: an edge menu, as New menu always made");
    compare(MenuSeeds.seed("bogus", "m", "M").placement, "edge");
  }

  function test_fresh() {
    const a = MenuSeeds.seed("edge", "a", "A");
    a.layout.modules.push({});
    compare(MenuSeeds.seed("edge", "b", "B").layout.modules, [], "each seed is a new object");
  }
}
