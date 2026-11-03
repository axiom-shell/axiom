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

  // Where something on a screen edge (its name: "top", …) sits, 0-1 from
  // the screen's top left: `along` the edge from its start (left/top) and
  // `across` the screen from it
  function edgeSpot(edgeName, along, across) {
    switch (edgeName) {
    case "top":
      return Qt.point(along, across);
    case "left":
      return Qt.point(across, along);
    case "right":
      return Qt.point(1 - across, along);
    }
    return Qt.point(along, 1 - across);
  }

  // edgeSpot's inverse: the edge nearest a spot (0-1 from the top left,
  // clamped), as { edge (its name), along, across (0-0.5) }. A spot as
  // near another edge as `preferEdge` (a name) keeps that one, so the
  // middle doesn't flip edges.
  function spotPlace(x, y, preferEdge) {
    const sx = Math.max(0, Math.min(1, x));
    const sy = Math.max(0, Math.min(1, y));
    const away = {
      "top": sy,
      "bottom": 1 - sy,
      "left": sx,
      "right": 1 - sx
    };
    const nearest = Math.min(sy, 1 - sy, sx, 1 - sx);
    const tied = root._names.filter(name => away[name] - nearest < 1e-9);
    const edge = tied.includes(preferEdge) ? preferEdge : tied[0];
    return {
      "edge": edge,
      "along": edge === "top" || edge === "bottom" ? sx : sy,
      "across": nearest
    };
  }
}
