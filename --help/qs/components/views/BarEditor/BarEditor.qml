pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.views.base

// The bar editor page: the bars and the selected one's settings on the
// left; on the right its sections drawn as a board across the top,
// whatever the bar's edge (drag widgets within and between them), over
// the selected widget's options and the widget library. Edits go through
// BarManager's draft and show live on the running bars, which outline the
// selected widget and report how they fit while the page is on screen.
BaseView {
  id: root

  // The board's height, from its rows
  readonly property real boardHeight: board.implicitHeight

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
      width: barDragLayer.width
      height: root.boardHeight
      label: "bar sections board"
      sourceComponent: SectionsBoard {
        dragLayer: barDragLayer
      }
    }

    StreamedLoader {
      y: root.boardHeight + OverlayConfig.cardSpacing
      width: barDragLayer.width
      height: barDragLayer.height - y
      label: "widget inspector"
      sourceComponent: WidgetInspector {
        dragLayer: barDragLayer
      }
    }
  }
}
