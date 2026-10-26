pragma Singleton
import QtQuick

// The four screen edges as numbers, for everything that sits on one (bars,
// docks, OSDs, the launcher, popouts, edge menus, the border), and their
// names in config. The order is a contract: code indexes arrays by it.
QtObject {
  id: root

  enum Edge {
    Top,
    Bottom,
    Left,
    Right
  }

  readonly property var _names: ["top", "bottom", "left", "right"]

  // A ScreenEdge as the edge names config, zones and Hyprland use: "top" |
  // "bottom" | "left" | "right"
  function name(edge) {
    return root._names[edge];
  }

  // The ScreenEdge an edge name stands for (name's inverse), -1 for
  // anything else
  function fromName(edgeName) {
    return root._names.indexOf(edgeName);
  }

  // The ScreenEdge of an edge in config ("top" | "bottom" | "left" |
  // "right"), Top for anything else
  function fromConfig(edgeName) {
    return Math.max(ScreenEdge.Top, root.fromName(edgeName));
  }

  // The edge across the screen from a ScreenEdge
  function opposite(edge) {
    return [ScreenEdge.Bottom, ScreenEdge.Top, ScreenEdge.Right, ScreenEdge.Left][edge];
  }
}
