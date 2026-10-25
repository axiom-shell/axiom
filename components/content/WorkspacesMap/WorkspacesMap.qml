pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// Workspaces as tiles with their windows' app icons; click one to go there.
// Shows the focused monitor's workspaces (WorkspacesConfig).
// properties: { showEmpty }
Card {
  id: root

  readonly property int activeId: CompositorManager.focused?.activeWorkspaceId ?? -1
  // A string, so the tiles are only rebuilt when the set of workspaces
  // shown changes, not on every window event
  readonly property string _idsKey: {
    const ids = CompositorManager.workspaceIds(CompositorManager.focusedOutput);
    if (root.properties.showEmpty === false)
      return ids.filter(id => CompositorManager.windows.some(w => w.workspaceId === id) || id === root.activeId).join(",");
    return ids.join(",");
  }
  readonly property var ids: root._idsKey === "" ? [] : root._idsKey.split(",").map(Number)
  TileGrid {
    id: grid
    anchors.fill: parent
    anchors.margins: root.pad
    count: root.ids.length
    spacing: Widget.spacing / 2
    // Screen-shaped tiles
    maxAspect: 1.8

    Repeater {
      model: root.ids

      Rectangle {
        id: tile
        required property int modelData
        required property int index
        readonly property bool active: tile.modelData === root.activeId
        readonly property var windows: CompositorManager.windows.filter(w => w.workspaceId === tile.modelData)

        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        radius: Widget.radius
        color: tile.active ? Theme.accent : tileArea.containsMouse ? Theme.backgroundHighlight : Theme.backgroundAlt
        border.color: tile.active ? Theme.accent : Theme.border
        border.width: Appearance.borderWidth

        // The number, where it doesn't crowd the icons
        StyledText {
          visible: tile.width >= Appearance.fontSize * 3 && tile.height >= Appearance.fontSize * 3
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Widget.spacing
          text: tile.modelData
          textSize: Appearance.fontSizeBy(-3)
          textColor: tile.active ? Theme.background : Theme.foreground
          opacity: 0.7
        }

        // Rows of icons, each centred (a Flow left-aligns them), balanced so
        // a partial last row isn't left alone
        Column {
          id: icons
          readonly property int count: Math.min(tile.windows.length, 6)
          readonly property real available: tile.width - 8
          readonly property int iconSize: Math.floor(Math.max(Widget.px(12), Math.min(tile.height * 0.4, icons.available / Math.max(1, Math.min(icons.count, 3)) - 2)))
          readonly property int fitPerRow: Math.max(1, Math.floor((icons.available + icons.spacing) / (icons.iconSize + icons.spacing)))
          readonly property int rows: icons.count === 0 ? 0 : Math.ceil(icons.count / Math.min(icons.count, icons.fitPerRow))
          readonly property int perRow: icons.rows === 0 ? 0 : Math.ceil(icons.count / icons.rows)

          anchors.centerIn: parent
          spacing: 2

          Repeater {
            model: icons.rows

            Row {
              id: iconRow
              required property int index
              // Not anchored to `parent`, which a removed row reads as null
              x: (icons.width - width) / 2
              spacing: icons.spacing

              Repeater {
                model: Math.min(icons.perRow, icons.count - iconRow.index * icons.perRow)

                Image {
                  required property int index
                  readonly property var window: tile.windows[iconRow.index * icons.perRow + index]
                  width: icons.iconSize
                  height: icons.iconSize
                  fillMode: Image.PreserveAspectFit
                  sourceSize: Qt.size(64, 64)
                  source: window ? IconResolver.resolveWindowIcon(window.appId, window.title) : ""
                }
              }
            }
          }
        }

        MouseArea {
          id: tileArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: CompositorManager.goToWorkspace(tile.modelData)
        }
      }
    }
  }
}
