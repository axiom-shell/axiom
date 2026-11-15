pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.views.base

// Layouts editor, left: the overlay's pages as the navigator shows them,
// your own pages (duplicate, remove, New page) then the tool pages (only
// hidden, never removed; a section closed until opened), each group
// dragged to reorder within itself (click to edit), then the desktop, the
// lock screen and the login screen, which aren't pages but are laid out
// the same way
ColumnLayout {
  id: root

  required property var dragLayer
  // Whether the tools section is open (the panel remembers it)
  property bool toolsOpen: false

  readonly property var views: OverlayManager.localViews ?? []
  // Indices into the views, in the navigator's order
  readonly property var dashboards: root.views.map((view, i) => i).filter(i => !OverlayConfig.isTool(root.views[i].type))
  readonly property var tools: root.views.map((view, i) => i).filter(i => OverlayConfig.isTool(root.views[i].type))

  signal toolsToggled

  // Moves page `from` to place `to` within `group` (indices into the
  // views), counted as if it were still in place
  function moveWithin(group, from, to) {
    if (group.length === 0)
      return;
    OverlayManager.moveView(from, to < group.length ? group[to] : group[group.length - 1] + 1);
  }

  spacing: Widget.spacing / 2

  ListSection {
    title: I18n.tr("Overlay pages")
    count: root.dashboards.length

    EntryListTarget {
      id: pageList
      dragLayer: root.dragLayer
      moveKind: "page-move"
      count: root.dashboards.length
      onDropRequested: (drag, index) => root.moveWithin(root.dashboards, drag.index, index)

      Repeater {
        model: pageList.count

        EntryListRow {
          id: entry
          readonly property int viewIndex: root.dashboards[entry.index] ?? -1
          readonly property var entryView: root.views[entry.viewIndex] ?? ({})

          list: pageList
          entryIndex: entry.viewIndex
          icon: OverlayConfig.pageIcon(entry.entryView)
          label: OverlayConfig.viewLabel(entry.entryView, entry.viewIndex)
          dimmed: entry.entryView.visible === false
          selected: OverlayManager.editTarget === "page" && OverlayManager.selectedViewIndex === entry.viewIndex
          changed: OverlayManager.viewChanged(entry.viewIndex)
          onClicked: OverlayManager.editPage(entry.viewIndex)
          onRemoveRequested: OverlayManager.removeView(entry.viewIndex)

          RowAction {
            row: entry
            iconText: entry.entryView.visible === false ? "visibility_off" : "visibility"
            tooltipText: entry.entryView.visible === false ? I18n.tr("Show in the navigator") : I18n.tr("Hide from the navigator")
            onClicked: OverlayManager.setViewVisible(entry.viewIndex, entry.entryView.visible === false)
          }

          RowAction {
            row: entry
            iconText: "content_copy"
            tooltipText: I18n.tr("Duplicate this page")
            onClicked: OverlayManager.duplicateView(entry.viewIndex)
          }

          RowAction {
            row: entry
            danger: true
            iconText: "close"
            tooltipText: I18n.tr("Remove this page")
            onClicked: OverlayManager.removeView(entry.viewIndex)
          }
        }
      }
    }
  }

  AddEntryButton {
    Layout.topMargin: Widget.spacing / 2
    text: I18n.tr("New page")
    onClicked: OverlayManager.addView()
  }

  // The fixed tool pages: closed until opened
  ListSection {
    visible: root.tools.length > 0
    Layout.topMargin: Widget.spacing / 2
    title: I18n.tr("Tools")
    count: root.tools.length
    collapsible: true
    open: root.toolsOpen
    onToggled: root.toolsToggled()

    EntryListTarget {
      id: toolList
      dragLayer: root.dragLayer
      moveKind: "tool-move"
      count: root.tools.length
      onDropRequested: (drag, index) => root.moveWithin(root.tools, drag.index, index)

      Repeater {
        model: toolList.count

        EntryListRow {
          id: tool
          readonly property int viewIndex: root.tools[tool.index] ?? -1
          readonly property var entryView: root.views[tool.viewIndex] ?? ({})
          readonly property bool shown: tool.entryView.visible !== false

          list: toolList
          entryIndex: tool.viewIndex
          icon: OverlayConfig.viewIcon(tool.entryView.type)
          label: OverlayConfig.viewLabel(tool.entryView, tool.viewIndex)
          dimmed: !tool.shown
          selected: OverlayManager.editTarget === "page" && OverlayManager.selectedViewIndex === tool.viewIndex
          changed: OverlayManager.viewChanged(tool.viewIndex)
          onClicked: OverlayManager.editPage(tool.viewIndex)

          RowAction {
            row: tool
            lit: tool.shown
            iconText: tool.shown ? "visibility" : "visibility_off"
            tooltipText: tool.shown ? I18n.tr("Hide from the navigator") : I18n.tr("Show in the navigator")
            onClicked: OverlayManager.setViewVisible(tool.viewIndex, !tool.shown)
          }
        }
      }
    }
  }
}
