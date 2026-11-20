pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// The tiles of an action module (QuickActions, Power, Screenshot), as a
// TileGrid of ActionTiles (an icon over a name) or ActionPills (wide, with
// a status line). `style` "auto" draws tiles where the card is tall enough
// for a named one, else pills; the module passes `tiles` and answers
// `clicked`/`opened`. One names rule for every module: "auto" shows each
// tile's name where it fits (ActionTile.labelFits), "show" always (elided),
// "hide" never; pills always carry theirs.
Item {
  id: root

  // "auto" | "tiles" | "pills"
  property string style: "tiles"
  // "auto" | "show" | "hide"
  property string labels: "auto"
  // [{ icon, label, status, active, tone ("accent" | "error"), countdown, opens }]
  property var tiles: []

  // The style drawn now: a named tile needs one row of 4.5 em
  readonly property string shownStyle: ModuleStyles.resolvedStyle(root.style, [
    {
      "style": "tiles",
      "minWidth": 0,
      "minHeight": Appearance.fontSize * 4.5
    },
    {
      "style": "pills",
      "minWidth": 0,
      "minHeight": 0
    }
  ], root.width, root.height)
  readonly property bool pills: root.shownStyle === "pills"

  signal clicked(int index, Item tile)
  signal opened(int index, Item tile)

  TileGrid {
    id: grid
    anchors.fill: parent
    count: root.tiles.length
    maxAspect: root.pills ? 4 : 1.6
    minAspect: root.pills ? 2.2 : 0

    Repeater {
      model: root.pills ? 0 : root.tiles.length

      ActionTile {
        id: tile
        required property int index
        readonly property var def: root.tiles[index] ?? ({})
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: def.icon ?? ""
        label: def.label ?? ""
        active: def.active ?? false
        showLabel: root.labels !== "hide"
        forceLabel: root.labels === "show"
        activeTone: def.tone ?? "accent"
        countdown: def.countdown ?? 0
        opens: def.opens ?? false
        onClicked: root.clicked(index, tile)
        onOpened: root.opened(index, tile)
      }
    }

    Repeater {
      model: root.pills ? root.tiles.length : 0

      ActionPill {
        id: pill
        required property int index
        readonly property var def: root.tiles[index] ?? ({})
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: def.icon ?? ""
        label: def.label ?? ""
        status: def.status ?? ""
        active: def.active ?? false
        activeTone: def.tone ?? "accent"
        countdown: def.countdown ?? 0
        opens: def.opens ?? false
        onClicked: root.clicked(index, pill)
        onOpened: root.opened(index, pill)
      }
    }
  }
}
