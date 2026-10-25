pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.views.base

// The bar editor page: the bars and the selected one's settings on the
// left; on the right its sections drawn as a strip along the side of the
// page its bar is on (or stacked down the left, for a top or bottom bar;
// drag widgets within and between them), beside the
// selected widget's options (or the widget library). Edits go through
// BarManager's draft and show live on the running bars, which outline the
// selected widget and report how they fit while the page is on screen.
BaseView {
  id: root

  // The side of the page the sections are drawn along: the bar's, or the
  // left when a top or bottom bar's are stacked
  readonly property string side: barDragLayer.side
  readonly property bool vertical: barDragLayer.vertical
  // The strip's depth across the bar: a vertical one is a column of chips
  readonly property real stripDepth: root.vertical ? root.grid.unit * 0.7 : board.implicitHeight

  // Only the current page is visible; its neighbours are loaded too
  onVisibleChanged: root._watch()
  Component.onCompleted: {
    BarManager.ensureLoaded();
    root._watch();
  }
  Component.onDestruction: BarManager.unwatch(root)

  function _watch() {
    if (root.visible)
      BarManager.watch(root);
    else
      BarManager.unwatch(root);
  }

  // Each panel is built a moment after the page (StreamedLoader), at its
  // size from the start
  StreamedLoader {
    Layout.preferredWidth: root.sideWidth
    Layout.preferredHeight: root.pageHeight
    label: "bars panel"
    sourceComponent: BarsPanel {}
  }

  BarDragLayer {
    id: barDragLayer
    implicitWidth: root.editorWidth
    implicitHeight: root.pageHeight

    StreamedLoader {
      id: board
      x: root.side === "right" ? barDragLayer.width - width : 0
      y: root.side === "bottom" ? barDragLayer.height - height : 0
      width: root.vertical ? root.stripDepth : barDragLayer.width
      height: root.vertical ? barDragLayer.height : root.stripDepth
      label: "bar sections board"
      sourceComponent: SectionsBoard {
        dragLayer: barDragLayer
      }
    }

    StreamedLoader {
      x: root.side === "left" ? root.stripDepth + OverlayConfig.cardSpacing : 0
      y: root.side === "top" ? root.stripDepth + OverlayConfig.cardSpacing : 0
      width: root.vertical ? barDragLayer.width - root.stripDepth - OverlayConfig.cardSpacing : barDragLayer.width
      height: root.vertical ? barDragLayer.height : barDragLayer.height - root.stripDepth - OverlayConfig.cardSpacing
      label: "widget inspector"
      sourceComponent: WidgetInspector {
        dragLayer: barDragLayer
      }
    }
  }
}
