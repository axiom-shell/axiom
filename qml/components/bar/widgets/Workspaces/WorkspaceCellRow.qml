pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.components.methods
import qs.components.reusable

// A bar switcher's row (a column on a vertical bar) of WorkspaceCells for
// workspaces `ids`: the cells' boxes at rest, the active one's sliding over
// them (ActiveCellIndicator), then their labels and icons over both. Every
// shown workspace in the standard layout (WorkspaceStrip), a row of the
// grid in the grid layout (WorkspaceGridStrip). With the widget's
// Background off its cells are segments of the bar's run (`run`): each in
// the bar's widget shape and with room for its caps (BarShapes.cellShape,
// cellRoom), cells `chainFirst` on of the widget's `chainCount`.
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
  // Where a point of an item of it sits along the bar (BarWidget.barSpotOf):
  // the active cell's Auto color gives way to the bar's gradient there.
  // Null to keep it.
  property var barSpotOf: null
  // Whether the active workspace's cell may show app icons (off: its
  // label instead, while the strip windows after the row show them:
  // `activeWorkspaceIcons`)
  property bool activeIcons: true
  // The widget's place in the bar's run, its cells being segments of it
  // (Workspaces' `_run`), else null; where its cells start among the
  // widget's chained ones (the row's, then the strip's windows'), and how
  // many those are
  property var run: null
  property int chainFirst: 0
  property int chainCount: ids.length

  readonly property bool isVertical: barConfig.vertical
  // Between cells (`spacing`: BarsConfig.workspaceCellSpacing), chained in
  // a powerline as segments
  readonly property real spacing: run ? BarShapes.cellGap(barConfig.look.grouping, _cellSpacing) : _cellSpacing
  readonly property real _cellSpacing: BarsConfig.workspaceCellSpacing(barConfig, properties.spacing)
  // As segments of a merged run, the cells that draw a box of their own
  // there: solid ones, and split's fill (BarWidgetStyle.cell)
  readonly property var _traits: BarLook.cellTraits(barConfig.look, solidBoxes)
  readonly property bool _boxedInRun: _traits.boxedInRun
  // Each cell's shape as a segment of the run and the room it keeps clear
  // of its caps (BarShapes.cellShape, cellRoom), else null
  // A cell after the widget's first starts square beneath the one before
  // where their boxes hide what's under them (drawn earlier over later);
  // the sliding active box, drawn over them all, always fits against it
  readonly property var _shapes: run ? ids.map((_, j) => BarShapes.cellShape(barConfig, run, _boxedInRun, _traits.cellOpaque, spacing, chainFirst + j, chainCount)) : null
  readonly property var _rooms: run ? ids.map((_, j) => BarShapes.cellRoom(barConfig, run, _boxedInRun, chainFirst + j, chainCount)) : null
  // On the bar in a merged run, the run draws their box (BarsConfig.cellColors'
  // onBar)
  readonly property bool _inGroup: hitArea !== null && barConfig.look.grouping === "merged"
  // Every cell a filled box (`solidBoxes`; workspaceCellColors reads it)
  readonly property bool solidBoxes: properties.solidBoxes
  // The workspace whose cell is hovered, which its box (drawn apart from
  // it) shows
  property int hoveredId: -1

  // Each cell's length at rest, and where they sit with the active one
  // widened by one normal cell's length (`wideActive`: WorkspaceCells)
  readonly property int _activeIndex: ids.indexOf(activeId)
  // What each cell shows (CellContents.of), in `ids` order
  readonly property var _contents: ids.map(id => contents.of(id, root.glyphOf(id, id === root.activeId), id !== root.activeId || root.activeIcons))
  readonly property var _lengths: WorkspaceCells.roomed(_contents.map(c => c.length), _rooms)
  readonly property var _layout: WorkspaceCells.layout(_lengths, spacing, _activeIndex, properties.wideActive ? cellLength : 0)
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
    thickness: root.cell
    restLength: root.cellLength
  }

  // Every urgent cell's fade, in step
  UrgentPulse {
    id: urgentPulse
    running: root.properties.urgentPulse && root._contents.some(c => c.urgent)
  }

  // BarsConfig.cellColors for cell `index`'s, active or at rest, and lit
  // (the pointer over it)
  function _look(index, active, lit) {
    if (active)
      return root._activeLook(index, lit);
    const content = root._contents[index];
    return BarsConfig.workspaceCellColors(root.barConfig, root, false, content?.occupied ?? false, content?.urgent ?? false, {
      "hovered": lit === true,
      "onBar": root.hitArea !== null
    });
  }

  // The active cell's look (BarsConfig.cellColors) at index `index` of the
  // row, `lit` or not: in the bar's gradient where its middle sits, its
  // color Auto
  function _activeLook(index, lit) {
    const middle = (root._layout.starts[index] ?? 0) + (root._layout.lengths[index] ?? 0) / 2;
    const spot = root.barSpotOf && index >= 0 ? root.barSpotOf(root, middle) : -1;
    return BarsConfig.workspaceCellColors(root.barConfig, root, true, false, false, {
      "hovered": lit === true,
      "spot": spot,
      "onBar": root.hitArea !== null
    });
  }

  // As segments, the active box's slice of the bar's gradient in `look`
  // (its `gradient`), from where it starts (back under the cell before)
  // to its end, at rest at cell `index`; else null (a flat color)
  function _activeSlice(look, index) {
    const part = look.gradient ?? null;
    if (!root.run || part === null || !root.barSpotOf || index < 0)
      return null;
    const start = (root._layout.starts[index] ?? 0) - (root._shapes[index]?.segment.back ?? 0);
    const end = (root._layout.starts[index] ?? 0) + (root._layout.lengths[index] ?? 0);
    return BarGradient.gradientSlice(root.barConfig.palette.gradientStops, root.barSpotOf(root, start), root.barSpotOf(root, end), part.alpha);
  }

  // Clipped (a cell that left the active state still shrinking, the active
  // box wrapping past an end), but for what its cells draw past it as
  // segments (BarShapes.cellMargins): back under the one before, a flared
  // tab's fillets past its ends, out to a tab's edge
  MarginClip {
    readonly property var _margins: BarShapes.cellMargins(root._shapes?.[0] ?? null, root._shapes?.[root.ids.length - 1] ?? null, root.isVertical)

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
          isActive: wsId === root.activeId
          indicated: indicator.slides
          lit: wsId === root.hoveredId
          look: root._look(index, isActive && !indicator.slides, backgroundCell.lit)
          urgent: root._contents[index]?.urgent ?? false
          solid: root.solidBoxes
          pulse: urgentPulse.value
          thickness: root.cell
          restLength: root._lengths[index] ?? root.cellLength
          length: root._layout.lengths[index] ?? root.cellLength
          radius: root.cellRadius
          hoverColor: root.hoverColor
          shape: root._shapes?.[index] ?? null
          inRun: root._inGroup
          room: root._rooms?.[index] ?? null
        }
      }
    }

    ActiveCellIndicator {
      id: indicator
      barConfig: root.barConfig
      look: root._activeLook(indicator.index, root.hoveredId !== -1 && root.hoveredId === root.activeId)
      solid: root.solidBoxes
      index: root._activeIndex
      thickness: root.cell
      lengths: root._lengths
      extra: root.properties.wideActive ? root.cellLength : 0
      spacing: root.spacing
      radius: root.cellRadius
      shape: root.run && indicator.index >= 0 ? BarShapes.cellShape(root.barConfig, root.run, root._boxedInRun, false, root.spacing, root.chainFirst + indicator.index, root.chainCount) : null
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
          isActive: wsId === root.activeId
          look: root._look(index, isActive, contentCell.lit)
          urgent: _content?.urgent ?? false
          solid: root.solidBoxes
          pulse: urgentPulse.value
          urgentColor: root.urgentColor
          thickness: root.cell
          restLength: root._lengths[index] ?? root.cellLength
          length: root._layout.lengths[index] ?? root.cellLength
          radius: root.cellRadius
          hoverColor: root.hoverColor
          shape: root._shapes?.[index] ?? null
          inRun: root._inGroup
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
