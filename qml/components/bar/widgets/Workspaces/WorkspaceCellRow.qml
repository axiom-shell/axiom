pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.services.system

// A bar switcher's row (a column on a vertical bar) of WorkspaceCells for
// workspaces `ids`: the cells' boxes at rest, the active one's sliding over
// them (ActiveCellIndicator), then their labels and icons over both. Every
// shown workspace in the standard layout (WorkspaceStrip), a row of the
// grid in the grid layout (WorkspaceGridStrip).
Item {
  id: root

  required property var barConfig
  required property var properties
  required property var monitor
  // The monitor's first workspace id (relative numbers count from it)
  required property int base
  required property var ids
  // The workspace shown active; none of `ids` for none
  required property int activeId
  required property real cell
  required property real cellLength
  required property real cellRadius
  required property color activeColor
  required property color occupiedColor
  required property color emptyColor
  required property color textColor
  required property color hoverColor
  // A hook: the glyph a cell shows instead of its label and app icon (the
  // grid's position arrow), or ""
  property var glyphOf: (id, active) => ""
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null

  readonly property bool isVertical: barConfig.vertical
  readonly property real spacing: barConfig.innerGap
  // App icons on occupied cells: always where the compositor makes the
  // workspaces (niri's show only the occupied ones, so a bare number says
  // little)
  readonly property bool appIcons: properties.showAppIcons || CompositorManager.dynamicWorkspaces
  // The workspace whose cell is hovered, which its box (drawn apart from
  // it) shows
  property int hoveredId: -1

  // Measured from the cells' lengths to be, never their gliding ones
  // (composition.md › Bar motion), and clipped to it: a cell that left the
  // active state still shrinking, the active box wrapping past an end
  readonly property real _measured: ids.length * cellLength + Math.max(0, ids.length - 1) * spacing + (properties.wideActive && ids.indexOf(activeId) >= 0 ? cellLength : 0)
  implicitWidth: isVertical ? cells.implicitWidth : _measured
  implicitHeight: isVertical ? _measured : cells.implicitHeight
  clip: true

  // A step past one end is coming: the active box leaves that end and
  // comes in at the other
  function expectWrap(forward) {
    indicator.expectWrap(forward);
  }

  function _occupied(id) {
    return (CompositorManager.workspaces.find(ws => ws.id === id)?.windowCount ?? 0) > 0;
  }

  // BarsConfig.cellColors for a workspace's cell, active or at rest, and
  // lit (the pointer over it)
  function _look(id, active, lit) {
    return BarsConfig.workspaceCellColors(root.barConfig, root, active, root._occupied(id), lit);
  }

  function _length(active) {
    return root.cellLength * (active && root.properties.wideActive ? 2 : 1);
  }

  Grid {
    rows: cells.rows
    columns: cells.columns
    spacing: cells.spacing

    Repeater {
      model: root.ids.length

      WorkspaceCell {
        id: backgroundCell
        required property int index
        readonly property int wsId: root.ids[index] ?? 0

        part: "background"
        barConfig: root.barConfig
        isActive: wsId === root.activeId
        indicated: indicator.slides
        lit: wsId === root.hoveredId
        look: root._look(wsId, isActive && !indicator.slides, backgroundCell.lit)
        thickness: root.cell
        restLength: root.cellLength
        length: root._length(isActive)
        radius: root.cellRadius
        hoverColor: root.hoverColor
      }
    }
  }

  ActiveCellIndicator {
    id: indicator
    barConfig: root.barConfig
    look: BarsConfig.cellColors(root.barConfig, root.activeColor, root.textColor, "active", {
      "hovered": root.hoveredId !== -1 && root.hoveredId === root.activeId
    })
    index: root.ids.indexOf(root.activeId)
    thickness: root.cell
    restLength: root.cellLength
    activeLength: root._length(true)
    spacing: root.spacing
    radius: root.cellRadius
  }

  Grid {
    id: cells
    // -1: as many as there are cells, so a cell added before a count
    // would follow can't overflow the grid. Each 1 waits for the other to
    // leave it, so a bar turning never makes it 1 by 1
    rows: !root.isVertical && columns === -1 ? 1 : -1
    columns: root.isVertical && rows === -1 ? 1 : -1
    spacing: root.spacing

    Repeater {
      model: root.ids.length

      WorkspaceCell {
        id: contentCell
        required property int index
        readonly property int wsId: root.ids[index] ?? 0
        readonly property string _glyph: root.glyphOf(wsId, isActive)
        readonly property var biggestWindow: root.appIcons && _glyph === "" && root._occupied(wsId) ? CompositorManager.biggestWindowForWorkspace(wsId) : null

        part: "content"
        hitArea: root.hitArea
        barConfig: root.barConfig
        isActive: wsId === root.activeId
        look: root._look(wsId, isActive, contentCell.lit)
        thickness: root.cell
        restLength: root.cellLength
        length: root._length(isActive)
        radius: root.cellRadius
        hoverColor: root.hoverColor
        labels: root.properties.labels
        // The workspace id, or counted from the monitor's first (its place
        // in the grid)
        label: root.properties.relativeNumbers ? wsId - root.base + 1 : wsId
        glyph: _glyph
        iconPath: biggestWindow ? AppIconManager.resolveWindowIcon(biggestWindow.appId, biggestWindow.title) : ""
        clickable: root.properties.clickToSwitch
        onClicked: CompositorManager.goToWorkspace(wsId, "go", root.monitor?.name ?? "")
        // Also when the cell under the pointer comes to stand for another
        // workspace (the shown set changed) or goes, so no box stays lit
        function _syncHover(): void {
          if (hovered)
            root.hoveredId = wsId;
          else if (root.hoveredId === wsId)
            root.hoveredId = -1;
        }
        onHoveredChanged: _syncHover()
        onWsIdChanged: {
          if (hovered)
            root.hoveredId = wsId;
        }
        Component.onDestruction: {
          if (root.hoveredId === wsId)
            root.hoveredId = -1;
        }
      }
    }
  }
}
