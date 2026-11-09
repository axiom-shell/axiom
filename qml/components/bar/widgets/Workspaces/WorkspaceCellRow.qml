pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.methods

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
  required property color urgentColor
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
  // The workspace whose cell is hovered, which its box (drawn apart from
  // it) shows
  property int hoveredId: -1

  // Each cell's length at rest, and where they sit with the active one
  // widened by one normal cell's length (`wideActive`: WorkspaceCells)
  readonly property int _activeIndex: ids.indexOf(activeId)
  // What each cell shows (CellContents.of), in `ids` order
  readonly property var _contents: ids.map(id => contents.of(id, root.glyphOf(id, id === root.activeId), true))
  readonly property var _lengths: _contents.map(c => c.length)
  readonly property var _layout: WorkspaceCells.layout(_lengths, spacing, _activeIndex, properties.wideActive ? cellLength : 0)
  // Measured from the cells' lengths to be, never their gliding ones
  // (composition.md › Bar motion), and clipped to it: a cell that left the
  // active state still shrinking, the active box wrapping past an end
  readonly property real _measured: _layout.total
  implicitWidth: isVertical ? cells.implicitWidth : _measured
  implicitHeight: isVertical ? _measured : cells.implicitHeight
  clip: true

  // A step past one end is coming: the active box leaves that end and
  // comes in at the other
  function expectWrap(forward) {
    indicator.expectWrap(forward);
  }

  CellContents {
    id: contents
    barConfig: root.barConfig
    properties: root.properties
    base: root.base
    thickness: root.cell
    restLength: root.cellLength
  }

  // Every urgent cell's fade, in step
  UrgentPulse {
    id: urgentPulse
    running: root.properties.urgentPulse && root._contents.some(c => c.urgent)
  }

  // BarsConfig.cellColors for cell `index`'s, active or at rest
  function _look(index, active) {
    const content = root._contents[index];
    return BarsConfig.workspaceCellColors(root.barConfig, root, active, content?.occupied ?? false, content?.urgent ?? false);
  }

  Grid {
    rows: cells.rows
    columns: cells.columns
    spacing: cells.spacing

    Repeater {
      model: root.ids.length

      WorkspaceCell {
        required property int index
        readonly property int wsId: root.ids[index] ?? 0

        part: "background"
        barConfig: root.barConfig
        isActive: wsId === root.activeId
        indicated: indicator.slides
        lit: wsId === root.hoveredId
        look: root._look(index, isActive && !indicator.slides)
        urgent: root._contents[index]?.urgent ?? false
        pulse: urgentPulse.value
        thickness: root.cell
        restLength: root._lengths[index] ?? root.cellLength
        length: root._layout.lengths[index] ?? root.cellLength
        radius: root.cellRadius
        hoverColor: root.hoverColor
      }
    }
  }

  ActiveCellIndicator {
    id: indicator
    barConfig: root.barConfig
    look: BarsConfig.cellColors(root.barConfig, root.activeColor, root.textColor, "active")
    index: root._activeIndex
    thickness: root.cell
    lengths: root._lengths
    extra: root.properties.wideActive ? root.cellLength : 0
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
        required property int index
        readonly property int wsId: root.ids[index] ?? 0
        readonly property var _content: root._contents[index] ?? null

        part: "content"
        hitArea: root.hitArea
        barConfig: root.barConfig
        isActive: wsId === root.activeId
        look: root._look(index, isActive)
        urgent: _content?.urgent ?? false
        pulse: urgentPulse.value
        urgentColor: root.urgentColor
        thickness: root.cell
        restLength: root._lengths[index] ?? root.cellLength
        length: root._layout.lengths[index] ?? root.cellLength
        radius: root.cellRadius
        hoverColor: root.hoverColor
        labels: root.properties.labels
        label: _content ? _content.number : ""
        glyph: _content?.kind === "glyph" ? _content.text : ""
        text: _content?.kind === "text" ? _content.text : ""
        iconPaths: _content ? _content.icons : []
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
