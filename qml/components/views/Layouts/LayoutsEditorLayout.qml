pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.hosts.overlay
import qs.components.views.base

// The layouts editor's page layout: its side panel on the left (this
// item's children, placed by the caller at `sideWidth` × `pageHeight`),
// and on the right the modules being edited drawn on a GridCanvas above
// the EditorInspector. Sized from the page's card grid; the drag layer
// covers all of it.
GridDragLayer {
  id: root

  // The overlay page's card grid (BaseView.grid), and the page itself, whose
  // whole-pixel sizes this lays out by
  required property OverlayGrid grid
  required property BaseView page

  // The canvas and the inspector, for the caller to fill in (what's
  // edited and how it's headed: see GridCanvas, EditorInspector)
  readonly property alias canvas: canvas
  readonly property alias inspector: inspector

  // The canvas header's Save / Reset, for the whole editor
  signal save
  signal reset

  readonly property real pageHeight: root.page.pageHeight
  readonly property real sideWidth: root.page.sideWidth
  // The canvas and inspector's width (BaseView.editorWidth)
  required property real mainWidth
  readonly property real canvasHeight: Math.round((root.pageHeight - OverlayConfig.cardSpacing) * 0.6)

  implicitWidth: root.sideWidth + OverlayConfig.cardSpacing + root.mainWidth
  implicitHeight: root.pageHeight

  Item {
    x: root.sideWidth + OverlayConfig.cardSpacing
    y: 0
    width: root.mainWidth
    height: root.canvasHeight

    GridCanvas {
      id: canvas
      wellMaxHeight: Widget.px(400)
      dragLayer: root
      onSave: root.save()
      onReset: root.reset()
    }
  }

  EditorInspector {
    id: inspector
    x: root.sideWidth + OverlayConfig.cardSpacing
    y: root.canvasHeight + OverlayConfig.cardSpacing
    width: root.mainWidth
    height: root.pageHeight - root.canvasHeight - OverlayConfig.cardSpacing
    dragLayer: root
  }
}
