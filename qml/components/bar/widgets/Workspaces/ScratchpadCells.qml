pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.compositor
import qs.config
import qs.components.reusable
import qs.components.methods
import qs.components.bar.look

// What a switcher shows after its workspaces and strip windows (ActiveStrip):
// a divider (StripDivider), then a cell for each special workspace
// (scratchpad) its `scratchpads` option lists (Scratchpads.cells), click one
// to show or hide it on this monitor. A special open on this monitor draws
// active, one open on another (or closed) as occupied while it has windows.
// A powerline chains on with no divider, as the strip windows do. The
// cells are rebuilt only when the set of names changes. Nothing loads where
// the compositor has no named special workspaces or with the option off.
// Scrolling doesn't step through them, and the popouts don't show them.
Loader {
  id: root

  required property var barConfig
  required property var properties
  // How the widget's cells draw on this bar (its switcher's)
  required property CellLook cellLook
  // The bar's monitor, where a click shows its special
  required property string monitorName
  // The widget's (BarWidget.hitArea), which the cells read hover from
  property var hitArea: null
  // Where its cells start among the widget's chained ones, and how many
  // those are
  property int chainFirst: 0
  property int chainCount: cells

  readonly property bool isVertical: barConfig.vertical
  readonly property var _cells: Scratchpads.cells(CompositorManager.specials, CompositorManager.specialNames, root.properties.scratchpads)
  // A string, so the cells are only rebuilt when the set of names changes,
  // not on every compositor event
  readonly property string _key: root._cells.map(c => c.name).join("\n")
  readonly property var names: root._key === "" ? [] : root._key.split("\n")
  readonly property int cells: root.names.length
  // A powerline's segments chain on from the ones before, with no divider
  readonly property bool _chained: cellLook.run !== null && barConfig.look.grouping === "powerline"
  readonly property bool _divided: !_chained

  active: root.properties.scratchpads !== "off" && CompositorManager.supports.namedSpecial === true
  visible: root.cells > 0

  sourceComponent: Grid {
    // Only what's shown: a Grid keeps spacing for an empty column or row
    rows: root.isVertical && root._divided ? 2 : 1
    columns: !root.isVertical && root._divided ? 2 : 1
    spacing: root.barConfig.innerGap

    StripDivider {
      visible: root._divided
      barConfig: root.barConfig
      cell: root.cellLook.thickness
    }

    Grid {
      id: cellGrid
      flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
      rows: root.isVertical ? Math.max(1, root.cells) : 1
      columns: root.isVertical ? 1 : Math.max(1, root.cells)
      // Between its cells: chained in a powerline as segments
      spacing: root.cellLook.gap

      CellContents {
        id: contents
        barConfig: root.barConfig
        properties: root.properties
        base: 0
        thickness: root.cellLook.thickness
        restLength: root.cellLook.length
      }

      // Every urgent cell's pulse, in step
      UrgentPulse {
        id: urgentPulse
        running: root.properties.urgentPulse && root._cells.some(c => c.urgent)
      }

      Repeater {
        model: root.cells

        WorkspaceCell {
          id: cell
          required property int index
          readonly property string name: root.names[index] ?? ""
          readonly property var special: root._cells.find(c => c.name === name) ?? null
          readonly property var _content: special ? contents.ofScratchpad(special, Scratchpads.entryFor(WorkspacesConfig.scratchpads, name)) : null

          part: "all"
          barConfig: root.barConfig
          cellLook: root.cellLook
          hitArea: root.hitArea
          isActive: root.monitorName !== "" && special?.output === root.monitorName
          look: root.cellLook.workspaceColorsOf(isActive, _content?.occupied ?? false, _content?.urgent ?? false, {
            "hovered": cell.lit,
            "spot": isActive ? root.cellLook.spotAt(cell, cell.length / 2, cell.x + cell.y + root.x + root.y) : -1
          })
          pulse: pulsing ? urgentPulse.value : 0
          mutedLook: pulsing ? root.cellLook.workspaceColorsOf(false, _content?.occupied ?? false, true, {
            "hovered": cell.lit,
            "muted": true
          }) : null
          slice: isActive ? root.cellLook.sliceOf(cell.look, cell, -(cell.shape?.segment.back ?? 0), cell.length, cell.x + cell.y + root.x + root.y) : null
          urgent: _content?.urgent ?? false
          pulsing: (_content?.urgent ?? false) && !isActive && urgentPulse.pulsing
          thickness: root.cellLook.thickness
          // Drawn over the next, which may start beneath it
          z: -index
          shape: root.cellLook.shapeOf(root.chainFirst + index, root.chainCount, root.cellLook.opaque, root.cellLook.content)
          room: root.cellLook.roomOf(root.chainFirst + index, root.chainCount, root.cellLook.content)
          length: WorkspaceCells.roomed([_content?.length ?? root.cellLook.length], [room])[0]
          glyph: _content?.kind === "glyph" ? _content.text : ""
          text: _content?.kind === "text" || _content?.kind === "name" ? _content.text : ""
          textPlain: _content ? _content.plain : false
          leadIcon: _content ? _content.lead : ""
          leadPlain: _content ? _content.leadPlain : false
          tailPaths: _content ? _content.tail : []
          tailLength: _content ? _content.tailLength : 0
          tailEdge: _content ? _content.tailEdge : 0
          tailShift: _content ? _content.tailShift : 0
          dividerAlong: _content ? _content.dividerAlong : 0
          iconPaths: _content ? _content.icons : []
          iconLayout: contents.iconLayout
          iconSlots: contents.iconSlots
          clickable: root.properties.clickToSwitch
          onClicked: CompositorManager.toggleSpecial(name, root.monitorName)

          LazyLoader {
            // The unnamed one has nothing to call it by
            active: cell.hovered && cell.name !== ""

            StyledToolTip {
              target: cell
              text: cell.name
              edges: root.cellLook.innerEdges
            }
          }
        }
      }
    }
  }
}
