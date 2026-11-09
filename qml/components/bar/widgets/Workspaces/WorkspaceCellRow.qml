pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.bar.look

// A bar switcher's row (a column on a vertical bar) of WorkspaceCells for
// workspaces `ids`: the cells' boxes at rest, the active one's sliding over
// them (ActiveCellIndicator), then their labels and icons over both. Every
// shown workspace in the standard layout (WorkspaceStrip), a row of the
// grid in the grid layout (WorkspaceGridStrip). With the widget's
// Background off its cells are segments of the bar's run (its cell look's
// `run`): each in the bar's widget shape and with room for its caps
// (CellLook.shapeOf, roomOf), cells `chainFirst` on of the widget's
// `chainCount`.
Item {
  id: root

  required property var barConfig
  required property var properties
  // How the widget's cells draw on this bar (its switcher's)
  required property CellLook cellLook
  required property var monitor
  // The monitor's first workspace id (relative numbers count from it)
  required property int base
  required property var ids
  // The workspace shown active; none of `ids` for none
  required property int activeId
  required property color activeColor
  required property color occupiedColor
  required property color urgentColor
  required property color emptyColor
  required property color textColor
  // A hook: the glyph a cell shows instead of its label and app icon (the
  // grid's position arrow), or ""
  property var glyphOf: (id, active) => ""
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  // Where a point of an item of it sits along the bar (BarWidget.barSpotOf):
  // the active cell's Auto color gives way to the bar's gradient there.
  // Null to keep it.
  property var barSpotOf: null
  // Whether the active workspace's cell may show app icons (off: its
  // label instead, while the strip windows after the row show them:
  // `activeWorkspaceIcons`)
  property bool activeIcons: true
  // Where its cells start among the widget's chained ones (the row's, then
  // the strip's windows'), and how many those are
  property int chainFirst: 0
  property int chainCount: ids.length

  readonly property bool isVertical: barConfig.vertical
  // Between cells, chained in a powerline as segments
  readonly property real spacing: cellLook.gap
  // Each cell's shape as a segment of the run and the room it keeps clear
  // of its caps, else null. A cell after the widget's first starts square
  // beneath the one before where their boxes hide what's under them (drawn
  // earlier over later); the sliding active box, drawn over them all,
  // always fits against it
  readonly property var _shapes: cellLook.run ? ids.map((_, j) => cellLook.shapeOf(chainFirst + j, chainCount, cellLook.opaque, cellLook.content)) : null
  readonly property var _rooms: cellLook.run ? ids.map((_, j) => cellLook.roomOf(chainFirst + j, chainCount, cellLook.content)) : null
  // The workspace whose cell is hovered, which its box (drawn apart from
  // it) shows
  property int hoveredId: -1

  // Each cell's length at rest, and where they sit with the active one
  // widened by one normal cell's length (`wideActive`: WorkspaceCells)
  readonly property int _activeIndex: ids.indexOf(activeId)
  // What each cell shows (CellContents.of), in `ids` order
  readonly property var _contents: ids.map(id => contents.of(id, root.glyphOf(id, id === root.activeId), id !== root.activeId || root.activeIcons))
  readonly property var _lengths: WorkspaceCells.roomed(_contents.map(c => c.length), _rooms)
  readonly property var _layout: WorkspaceCells.layout(_lengths, spacing, _activeIndex, properties.wideActive ? cellLook.length : 0)
  // Measured from the cells' lengths to be, never their gliding ones
  // (composition.md › Bar motion), and clipped to it: a cell that left the
  // active state still shrinking, the active box wrapping past an end
  readonly property real _measured: _layout.total
  implicitWidth: isVertical ? cells.implicitWidth : _measured
  implicitHeight: isVertical ? _measured : cells.implicitHeight

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
    thickness: root.cellLook.thickness
    restLength: root.cellLook.length
  }

  // Every urgent cell's fade, in step
  UrgentPulse {
    id: urgentPulse
    running: root.properties.urgentPulse && root._contents.some(c => c.urgent)
  }

  // The cell look's colors for cell `index`'s, active or at rest, and lit
  // (the pointer over it)
  function _look(index, active, lit) {
    if (active)
      return root._activeLook(index, lit);
    const content = root._contents[index];
    return root.cellLook.workspaceColorsOf(root, false, content?.occupied ?? false, content?.urgent ?? false, {
      "hovered": lit === true
    });
  }

  // The active cell's look at index `index` of the row, `lit` or not: in
  // the bar's gradient where its middle sits, its color Auto
  function _activeLook(index, lit) {
    const middle = (root._layout.starts[index] ?? 0) + (root._layout.lengths[index] ?? 0) / 2;
    const spot = root.barSpotOf && index >= 0 ? root.barSpotOf(root, middle) : -1;
    return root.cellLook.workspaceColorsOf(root, true, false, false, {
      "hovered": lit === true,
      "spot": spot
    });
  }

  // As segments, the active box's slice of the bar's gradient in `look`
  // (its `gradient`), from where it starts (back under the cell before)
  // to its end, at rest at cell `index`; else null (a flat color)
  function _activeSlice(look, index) {
    const part = look.gradient ?? null;
    if (!root.cellLook.run || part === null || !root.barSpotOf || index < 0)
      return null;
    const start = (root._layout.starts[index] ?? 0) - (root._shapes[index]?.segment.back ?? 0);
    const end = (root._layout.starts[index] ?? 0) + (root._layout.lengths[index] ?? 0);
    return BarGradient.gradientSlice(root.barConfig.palette.gradientStops, root.barSpotOf(root, start), root.barSpotOf(root, end), part.alpha);
  }

  // Clipped (a cell that left the active state still shrinking, the active
  // box wrapping past an end), but for what its cells draw past it as
  // segments (BarCells.cellMargins): back under the one before, a flared
  // tab's fillets past its ends, out to a tab's edge
  MarginClip {
    readonly property var _margins: BarCells.cellMargins(root._shapes?.[0] ?? null, root._shapes?.[root.ids.length - 1] ?? null, root.isVertical)

    anchors.fill: parent
    leftMargin: _margins.left
    topMargin: _margins.top
    rightMargin: _margins.right
    bottomMargin: _margins.bottom

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
          // Drawn over the next, which may start beneath it
          z: -index
          barConfig: root.barConfig
          cellLook: root.cellLook
          isActive: wsId === root.activeId
          indicated: indicator.slides
          lit: wsId === root.hoveredId
          look: root._look(index, isActive && !indicator.slides, backgroundCell.lit)
          urgent: root._contents[index]?.urgent ?? false
          pulse: urgentPulse.value
          thickness: root.cellLook.thickness
          restLength: root._lengths[index] ?? root.cellLook.length
          length: root._layout.lengths[index] ?? root.cellLook.length
          shape: root._shapes?.[index] ?? null
          room: root._rooms?.[index] ?? null
        }
      }
    }

    ActiveCellIndicator {
      id: indicator
      barConfig: root.barConfig
      cellLook: root.cellLook
      look: root._activeLook(indicator.index, root.hoveredId !== -1 && root.hoveredId === root.activeId)
      index: root._activeIndex
      thickness: root.cellLook.thickness
      lengths: root._lengths
      extra: root.properties.wideActive ? root.cellLook.length : 0
      spacing: root.spacing
      shape: indicator.index >= 0 ? root.cellLook.shapeOf(root.chainFirst + indicator.index, root.chainCount, false, root.cellLook.content) : null
      slice: root._activeSlice(indicator.look, indicator.index)
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
          readonly property var _content: root._contents[index] ?? null

          part: "content"
          hitArea: root.hitArea
          barConfig: root.barConfig
          cellLook: root.cellLook
          isActive: wsId === root.activeId
          look: root._look(index, isActive, contentCell.lit)
          urgent: _content?.urgent ?? false
          pulse: urgentPulse.value
          urgentColor: root.urgentColor
          thickness: root.cellLook.thickness
          restLength: root._lengths[index] ?? root.cellLook.length
          length: root._layout.lengths[index] ?? root.cellLook.length
          shape: root._shapes?.[index] ?? null
          room: root._rooms?.[index] ?? null
          labels: root.properties.labels
          label: _content ? _content.number : ""
          glyph: _content?.kind === "glyph" ? _content.text : ""
          text: _content?.kind === "text" || _content?.kind === "name" ? _content.text : ""
          textPlain: _content ? _content.plain : false
          leadIcon: _content?.kind === "text" ? _content.lead : ""
          leadPlain: _content ? _content.leadPlain : false
          iconPaths: _content ? _content.icons : []
          iconLayout: contents.iconLayout
          iconSlots: contents.iconSlots
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
}
