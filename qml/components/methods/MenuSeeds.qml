pragma Singleton
import QtQuick

// What a new edge menu starts as, by what it's made for (the layouts
// editor's New menu, a Submenu module's New submenu…, the bar editor's
// New menu…): its own fields, set over the Menu schema's defaults by
// the editor (MenuEditor). Pure.
QtObject {
  id: root

  // What a menu can be made for, in the order New menu offers them
  readonly property var purposes: ["edge", "popout", "submenu", "free"]

  // A new menu's own fields for `purpose` (one of `purposes`; anything
  // else is "edge"), with its `id` and `name` and no modules yet: an edge
  // menu opens on hovering its edge; a bar widget's popout, a submenu and a
  // floating menu are free (no edge) and fade in, as free menus did before
  // they shared the edge menus' `animation` (whose default slides). A
  // floating one opens at the screen's centre, mostly by a bind or a
  // script, with the pointer elsewhere: it stays open when the pointer
  // leaves, and a click outside closes it
  function seed(purpose, id, name) {
    const menu = {
      "id": id,
      "name": name,
      "layout": {
        "modules": []
      }
    };
    if (!root.purposes.includes(purpose) || purpose === "edge") {
      menu.placement = "edge";
      menu.open = {
        "onHover": true
      };
      return menu;
    }
    menu.placement = "free";
    menu.animation = "fade";
    if (purpose === "free") {
      menu.freeAnchor = {
        "at": "centre"
      };
      menu.close = {
        "onLeave": false,
        "onOutsideClick": true
      };
    }
    return menu;
  }
}
