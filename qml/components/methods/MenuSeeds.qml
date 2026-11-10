pragma Singleton
import QtQuick

// What a new edge menu starts as, by what it's made for (the layouts
// editor's New menu, a Submenu module's New submenu…, the bar editor's
// New menu…): its own fields, set over the EdgeMenu schema's defaults by
// the editor (EdgeMenuEditor). Pure.
QtObject {
  id: root

  // What a menu can be made for, in the order New menu offers them
  readonly property var purposes: ["edge", "popout", "submenu", "key"]

  // A new menu's own fields for `purpose` (one of `purposes`; anything
  // else is "edge"), with its `id` and `name` and no modules yet: an edge
  // menu opens on hovering its edge; a bar widget's popout, a submenu and a
  // keybind's menu are free (no edge), a keybind's opening at the screen's
  // centre
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
    if (purpose === "key")
      menu.freeAnchor = {
        "at": "centre"
      };
    return menu;
  }
}
